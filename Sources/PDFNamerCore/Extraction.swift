import AppKit
import CoreServices
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// What we can read from a file: its text, a page image for the model, and (images) the shot date.
public struct Extracted: @unchecked Sendable {
    public var text: String?
    public var image: CGImage?
    public var captureDate: String?
    public var isEmpty: Bool { text == nil && image == nil }
}

public enum ExtractionError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self { case .unreadable(let name): return "Impossible d’ouvrir \(name)" }
    }
}

public enum Extractor {
    /// PDF: native text (Vision OCR for scans) + page 1. Image: OCR + downscaled image + shot date.
    public static func extract(_ url: URL) throws -> Extracted {
        Config.isImage(url) ? try extractImage(url) : try extractPDF(url)
    }

    static func limit(_ text: String) -> String? {
        let t = text.pyStrip.pySlice(nil, Config.maxChars)
        return t.isEmpty ? nil : t
    }

    static func extractPDF(_ url: URL) throws -> Extracted {
        guard let doc = PDFDocument(url: url) else { throw ExtractionError.unreadable(url.lastPathComponent) }
        let pages = (0..<min(doc.pageCount, Config.maxPages)).compactMap { doc.page(at: $0) }
        let image = pages.first.flatMap { render($0, dpi: Config.imageDPI) }
        var text = pages.map { $0.string ?? "" }.joined(separator: "\n").pyStrip
        if text.isEmpty {  // scan: OCR each page at 144 dpi
            text = pages.compactMap { render($0, dpi: Config.ocrDPI).flatMap(ocr) }
                .filter { !$0.isEmpty }.joined(separator: "\n").pyStrip
        }
        return Extracted(text: limit(text), image: image, captureDate: nil)
    }

    static func extractImage(_ url: URL) throws -> Extracted {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Config.imageMaxPx,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        return Extracted(text: limit(ocr(image) ?? ""), image: image, captureDate: captureDate(url, src))
    }

    /// Page rendered on white at `dpi`, rotation applied.
    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let scale = dpi / 72
        let w = Int(((rotated ? box.height : box.width) * scale).rounded())
        let h = Int(((rotated ? box.width : box.height) * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage()
    }

    /// macOS Vision OCR on one image. Accurate mode (the Python script used fast): slower,
    /// but far fewer misread digits on pale scans and receipts.
    public static func ocr(_ image: CGImage) -> String? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["fr-FR", "en-US", "de-DE", "es-ES", "it-IT"]
        req.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: image).perform([req]) } catch { return nil }
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static let exifDate = Rx(#"^(\d{4}):(\d{2}):(\d{2})"#)

    /// Shot date (YYYY-MM-DD): EXIF, then Spotlight (screenshots), then file creation date.
    static func captureDate(_ url: URL, _ src: CGImageSource) -> String {
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        for raw in [exif[kCGImagePropertyExifDateTimeOriginal], tiff[kCGImagePropertyTIFFDateTime]] {
            if let s = raw as? String, let m = exifDate.first(s) {
                return (1...3).map { m.group($0, in: s)! }.joined(separator: "-")
            }
        }
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date {
            return Day(date).iso
        }
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        return Day(created).iso
    }

    /// PNG written to a temporary file (the model takes images by URL).
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ExtractionError.unreadable(url.lastPathComponent) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExtractionError.unreadable(url.lastPathComponent) }
    }
}
