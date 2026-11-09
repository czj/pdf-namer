import Foundation

/// A suggested name for one file.
public struct Suggestion: Sendable {
    public let fields: [String: String]
    /// New file name, extension included.
    public let name: String
    public var chips: [String] { Naming.chips(fields) }
}

public enum Namer {
    /// Extraction runs off the model's path, so it can be started ahead for a whole batch.
    public static func extract(_ url: URL) async throws -> Extracted {
        try await Task.detached(priority: .userInitiated) { try Extractor.extract(url) }.value
    }

    /// nil when nothing in the file is readable.
    public static func suggest(_ url: URL, _ ex: Extracted, engine: Engine) async throws -> Suggestion? {
        guard !ex.isEmpty else { return nil }
        let isImage = Config.isImage(url)
        let fields = try await engine.ask(ex, isImage: isImage)
        let ext = url.lastPathComponent.pySplitExt.1.lowercased()
        let name = Naming.buildFilename(fields, original: url.lastPathComponent, captureDate: ex.captureDate) + ext
        return Suggestion(fields: fields, name: name)
    }
}
