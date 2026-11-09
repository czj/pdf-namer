import Foundation
import Testing
@testable import PDFNamerCore

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-namer-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ json: String, _ url: URL) throws { try Data(json.utf8).write(to: url) }

@Test func partialConfigKeepsDefaults() throws {
    let json = #"{"backupDir": "~/Archives", "watchedFolders": [{"path": "~/Downloads"}]}"#
    let c = try JSONDecoder().decode(UserConfig.self, from: Data(json.utf8))
    #expect(c.backupDir == "~/Archives")
    #expect(c.backupURL.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Archives").path)
    #expect(c.watchedFolders == [UserConfig.Folder(path: "~/Downloads", enabled: true)])
    #expect(c.backupMaxAgeDays == 180)
    #expect(c.expireMaxAge == nil)  // trashing is opt-in
    #expect(!c.confirmBeforeRename)
}

@Test func localOverridesSharedKeyByKey() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let shared = dir.appendingPathComponent("config.json"), local = dir.appendingPathComponent("config.local.json")
    try write(#"{"backupDir": "~/Archives", "expireMaxAgeDays": 548}"#, shared)
    try write(#"{"expireMaxAgeDays": 0, "watchedFolders": [{"path": "~/Scans"}]}"#, local)
    let c = try UserConfig.load(shared: shared, local: local)
    #expect(c.backupDir == "~/Archives")
    #expect(c.expireMaxAgeDays == 0)
    #expect(c.watchedFolders.map(\.path) == ["~/Scans"])
}

@Test func saveLocalWritesOnlyDifferencesAndNeverTouchesShared() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let shared = dir.appendingPathComponent("config.json"), local = dir.appendingPathComponent("config.local.json")
    let sharedText = #"{"backupDir": "~/Archives", "expireMaxAgeDays": 548}"#
    try write(sharedText, shared)

    var c = try UserConfig.load(shared: shared, local: local)
    c.watchedFolders = [UserConfig.Folder(path: FileManager.default.homeDirectoryForCurrentUser.path + "/Scans")]
    try c.saveLocal(shared: shared, local: local)

    #expect(try String(contentsOf: shared, encoding: .utf8) == sharedText)
    #expect(UserConfig.localKeys(at: local) == ["watchedFolders"])
    #expect(try String(contentsOf: local, encoding: .utf8).contains(#""path" : "~/Scans""#))
    #expect(try UserConfig.load(shared: shared, local: local) == c)

    c.watchedFolders = []  // back to the shared value: no override left
    try c.saveLocal(shared: shared, local: local)
    #expect(!FileManager.default.fileExists(atPath: local.path))
}

@Test func missingFilesGiveDefaults() throws {
    let none = URL(fileURLWithPath: "/nonexistent/config.json")
    #expect(try UserConfig.load(shared: none, local: none) == UserConfig())
}

@Test func malformedFileThrows() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bad = dir.appendingPathComponent("config.json")
    try write("{ oops", bad)
    #expect(throws: (any Error).self) { try UserConfig.load(shared: bad, local: dir.appendingPathComponent("x.json")) }
}
