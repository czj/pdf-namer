import CoreServices
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// What we can read from a file: its text, page 1 as PNG for the model, and (images) the shot date.
public struct Extracted: Sendable {
    public var text: String?
    public var imagePNG: Data?
    public var captureDate: String?
    public var isEmpty: Bool { text == nil && imagePNG == nil }
}

public enum ExtractionError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self { case .unreadable(let name): "Impossible d’ouvrir \(name)" }
    }
}

public enum Extractor {
    /// PDF: native text (Vision OCR for scans) + page 1. Image: OCR + downscaled image + shot date.
    /// Rendering and OCR are CPU-heavy, so this always runs off the caller's actor.
    @concurrent
    public static func extract(_ url: URL) async throws -> Extracted {
        Config.isImage(url) ? try await extractImage(url) : try await extractPDF(url)
    }

    static func limit(_ text: String) -> String? {
        let t = text.pyStrip.pySlice(nil, Config.maxChars)
        return t.isEmpty ? nil : t
    }

    static func extractPDF(_ url: URL) async throws -> Extracted {
        guard let doc = PDFDocument(url: url) else { throw ExtractionError.unreadable(url.lastPathComponent) }
        let pages = (0..<min(doc.pageCount, Config.maxPages)).compactMap { doc.page(at: $0) }
        let image = pages.first.flatMap { render($0, dpi: Config.imageDPI) }
        var text = pages.map { $0.string ?? "" }.joined(separator: "\n").pyStrip
        if text.isEmpty {  // scan: OCR each page at 144 dpi
            var parts: [String] = []
            for page in pages {
                try Task.checkCancellation()
                if let img = render(page, dpi: Config.ocrDPI), let t = await ocr(img), !t.isEmpty { parts.append(t) }
            }
            text = parts.joined(separator: "\n").pyStrip
        }
        return Extracted(text: limit(text), imagePNG: image.flatMap(png), captureDate: nil)
    }

    static func extractImage(_ url: URL) async throws -> Extracted {
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
        let date = captureDate(url, src)
        return Extracted(text: limit(await ocr(image) ?? ""), imagePNG: png(image), captureDate: date)
    }

    /// Longest side of a rendered page, whatever its declared size: a crafted PDF
    /// (a watched Downloads folder takes anything) must not make us allocate gigabytes.
    static let maxRenderSide: CGFloat = 4000

    /// Page rendered on white at `dpi` (capped at maxRenderSide), rotation applied.
    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let side = max(box.width, box.height)
        guard side.isFinite, side > 0 else { return nil }
        let rotated = page.rotation % 180 != 0
        let scale = min(dpi / 72, maxRenderSide / side)
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

    /// Vision OCR on one image, accurate mode (the Python script used fast: far more misread digits).
    public static func ocr(_ image: CGImage) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US", "de-DE", "es-ES", "it-IT"].map { Locale.Language(identifier: $0) }
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return nil }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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

    /// PNG bytes (the model takes images by URL, so they get written to a temporary file).
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
