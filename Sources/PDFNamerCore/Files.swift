import Foundation

/// Renaming with backups, and the backup folder housekeeping.
public enum Files {
    static let backupRe = Rx("^\(NSRegularExpression.escapedPattern(for: Config.backupPrefix)) (\\d{4}-\\d{2}-\\d{2}) - ")
    static var fm: FileManager { .default }

    /// "x.pdf" → "RENAME BACKUP 2026-10-01 - x.pdf" (backup date hard-coded in the name).
    public static func backupName(_ filename: String, day: Day = .today()) -> String {
        "\(Config.backupPrefix) \(day.iso) - \(filename)"
    }

    /// Append " - N" to avoid overwriting existing files.
    public static func uniqueURL(_ url: URL) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let (root, ext) = url.path.pySplitExt
        var n = 1
        while fm.fileExists(atPath: "\(root) - \(n)\(ext)") { n += 1 }
        return URL(fileURLWithPath: "\(root) - \(n)\(ext)")
    }

    /// Copy the original to the backup folder, then rename it in place; returns the final URL.
    @discardableResult
    public static func rename(_ url: URL, to newName: String, backupDir: URL) throws -> URL {
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: uniqueURL(backupDir.appendingPathComponent(backupName(url.lastPathComponent))))
        return try move(url, to: newName)
    }

    /// Plain rename next to the file (undo, manual edit), never overwriting.
    @discardableResult
    public static func move(_ url: URL, to newName: String) throws -> URL {
        let final = uniqueURL(url.deletingLastPathComponent().appendingPathComponent(newName))
        try fm.moveItem(at: url, to: final)
        return final
    }

    // MARK: Housekeeping

    public struct Report: Sendable {
        public var purged: [String] = []
        public var trashed: [String] = []
    }

    /// Purge old RENAME BACKUPs, then (if asked) trash the folder's other expired items.
    /// nil ages mean "never". Walks a whole folder tree, so it runs off the caller's actor.
    @concurrent
    public static func housekeeping(_ folder: URL, dryRun: Bool = false,
                                    backupMaxAgeDays: Int?, expireMaxAgeDays: Int?) async -> Report {
        var report = Report()
        guard fm.fileExists(atPath: folder.path) else { return report }
        if let days = backupMaxAgeDays { report.purged = purgeOldBackups(folder, maxAgeDays: days, dryRun: dryRun) }
        if let days = expireMaxAgeDays {
            report.trashed = expireOldItems(folder, maxAgeDays: days, dryRun: dryRun)
        }
        return report
    }

    /// Delete "RENAME BACKUP <date> - …" files older than maxAgeDays (age read from the name).
    public static func purgeOldBackups(_ folder: URL, maxAgeDays: Int, dryRun: Bool = false,
                                       today: Day = .today()) -> [String] {
        let cutoff = today.adding(days: -maxAgeDays).iso
        var removed: [String] = []
        for name in ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() {
            guard let m = backupRe.first(name), m.group(1, in: name)! < cutoff else { continue }
            let url = folder.appendingPathComponent(name)
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
            if !dryRun { try? fm.removeItem(at: url) }
            removed.append(name)
        }
        return removed
    }

    static func dateAdded(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
    }

    /// Trash files added more than maxAgeDays ago, subfolders included; returns relative paths.
    /// Empty folders go too, if this run emptied them or they are themselves old.
    public static func expireOldItems(_ folder: URL, maxAgeDays: Int, dryRun: Bool = false) -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
        func old(_ url: URL) -> Bool { (dateAdded(url) ?? Date()) < cutoff }
        let base = folder.standardizedFileURL.path
        func rel(_ url: URL) -> String { String(url.standardizedFileURL.path.dropFirst(base.count + 1)) }
        var trashed: [String] = []
        var emptied = Set<String>()

        func walk(_ dir: URL) {
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            var files: [URL] = []
            for name in names {
                let url = dir.appendingPathComponent(name)
                let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if v?.isDirectory == true && v?.isSymbolicLink != true { walk(url) } else { files.append(url) }
            }
            let isRoot = dir.standardizedFileURL.path == base
            for url in files {
                let name = url.lastPathComponent
                if name.hasPrefix(".") || (isRoot && backupRe.test(name)) { continue }
                if old(url) && (dryRun || (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil) {
                    trashed.append(rel(url))
                    emptied.insert(dir.standardizedFileURL.path)
                }
            }
            guard !isRoot else { return }
            // Empty = nothing left but hidden files (.DS_Store), counting dry-run "removals".
            let gone = Set(trashed.map { $0.pyRStrip("/") })
            let left = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter {
                !$0.hasPrefix(".") && !gone.contains(rel(dir.appendingPathComponent($0)))
            }
            if left.isEmpty && (emptied.contains(dir.standardizedFileURL.path) || old(dir)) {
                if !dryRun { try? fm.removeItem(at: dir) }  // only hidden files remain
                trashed.append(rel(dir) + "/")
                emptied.insert(dir.deletingLastPathComponent().standardizedFileURL.path)
            }
        }
        walk(folder)
        return trashed
    }
}
