import Foundation

/// Personal settings, shared by the app and the CLI, in `~/.config/pdf-namer/`
/// (or `$XDG_CONFIG_HOME/pdf-namer/`), as two layers:
///
/// - `config.json`: hand-written, can live in a dotfiles repo; the app never writes it.
/// - `config.local.json`: this Mac only; the settings window writes there just the
///   keys that differ from `config.json`. Its keys win, one by one.
///
/// Every key is optional; paths may start with `~`.
///
///     {
///       "backupDir": "~/Documents/Archives",
///       "backupMaxAgeDays": 180,
///       "expireMaxAgeDays": 548,
///       "watchedFolders": [{ "path": "~/Downloads", "enabled": true }],
///       "confirmBeforeRename": false
///     }
public struct UserConfig: Codable, Equatable, Sendable {
    public struct Folder: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var path: String
        public var enabled = true
        public var id: String { path }
        public var url: URL { UserConfig.expand(path) }
        public var name: String { url.lastPathComponent }

        public init(path: String, enabled: Bool = true) {
            self.path = UserConfig.abbreviate(path)
            self.enabled = enabled
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    /// Where originals are copied ("RENAME BACKUP <date> - …") before a rename.
    public var backupDir = "~/Documents/PDF Namer/Originaux"
    /// Backups older than this are deleted (0 = never).
    public var backupMaxAgeDays = 180
    /// Other files in backupDir added longer ago go to the Trash (0 = never).
    public var expireMaxAgeDays = 0
    /// New PDFs and images arriving here are renamed automatically.
    public var watchedFolders: [Folder] = []
    /// Dropped files: show the name and wait for "Renommer".
    public var confirmBeforeRename = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserConfig()
        backupDir = try c.decodeIfPresent(String.self, forKey: .backupDir) ?? d.backupDir
        backupMaxAgeDays = try c.decodeIfPresent(Int.self, forKey: .backupMaxAgeDays) ?? d.backupMaxAgeDays
        expireMaxAgeDays = try c.decodeIfPresent(Int.self, forKey: .expireMaxAgeDays) ?? d.expireMaxAgeDays
        watchedFolders = try c.decodeIfPresent([Folder].self, forKey: .watchedFolders) ?? d.watchedFolders
        confirmBeforeRename = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeRename) ?? d.confirmBeforeRename
    }

    public var backupURL: URL { Self.expand(backupDir) }
    public var backupMaxAge: Int? { backupMaxAgeDays > 0 ? backupMaxAgeDays : nil }
    public var expireMaxAge: Int? { expireMaxAgeDays > 0 ? expireMaxAgeDays : nil }

    public static var directory: URL {
        let env = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        let base = env.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("pdf-namer")
    }

    /// Shared settings (dotfiles).
    public static var fileURL: URL { directory.appendingPathComponent("config.json") }
    /// This Mac's overrides, written by the app.
    public static var localFileURL: URL { directory.appendingPathComponent("config.local.json") }

    /// A JSON object file as a dictionary; [:] when missing. Malformed files throw (and are never overwritten).
    static func object(at url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt, userInfo: [NSFilePathErrorKey: url.path])
        }
        return obj
    }

    static func decode(_ obj: [String: Any]) throws -> UserConfig {
        try JSONDecoder().decode(UserConfig.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    /// config.json, then config.local.json over it, key by key; defaults for the rest.
    public static func load(shared: URL = fileURL, local: URL = localFileURL) throws -> UserConfig {
        try decode(try object(at: shared).merging(try object(at: local)) { $1 })
    }

    /// Keys this Mac overrides (from config.local.json).
    public static func localKeys(at url: URL = localFileURL) -> [String] {
        ((try? object(at: url)) ?? [:]).keys.sorted()
    }

    /// Write to config.local.json only what differs from config.json (removing the file if nothing does).
    public func saveLocal(shared: URL = fileURL, local: URL = localFileURL) throws {
        let base = try Self.object(at: shared)
        let effectiveBase = try Self.dictionary(Self.decode(base))
        var overrides: [String: Any] = [:]
        for (key, value) in try Self.dictionary(self) where !(effectiveBase[key].map { ($0 as AnyObject).isEqual(value) } ?? false) {
            overrides[key] = value
        }
        if overrides.isEmpty {
            try? FileManager.default.removeItem(at: local)
        } else {
            try Self.write(overrides, to: local)
        }
    }

    static func dictionary(_ c: UserConfig) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any] ?? [:]
    }

    static func write(_ obj: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    /// The whole configuration as one file (used to seed config.json).
    public func save(to url: URL) throws { try Self.write(Self.dictionary(self), to: url) }

    public static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    public static func abbreviate(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).abbreviatingWithTildeInPath
    }
}
