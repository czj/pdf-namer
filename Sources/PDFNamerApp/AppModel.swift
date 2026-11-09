import AppKit
import Observation
import OSLog
import PDFNamerCore
import ServiceManagement
import SwiftUI
import UserNotifications

struct RecentEntry: Codable, Identifiable {
    var id = UUID()
    var oldName: String
    var path: String
    var date: Date
    var newName: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// One file going through the pipeline.
@Observable
final class Item: Identifiable {
    enum Phase: Equatable {
        case waiting, reading, analyzing, proposed, done, unchanged, cancelled
        case skipped(String), failed(String)
        var isPending: Bool { [.waiting, .reading, .analyzing].contains(self) }
    }

    let id = UUID()
    let originalName: String
    let source: String?  // watched folder name, nil for a drop
    var url: URL
    var phase: Phase = .waiting
    var suggestion: Suggestion?
    var took: TimeInterval?
    @ObservationIgnored var extraction: Task<Extracted, Error>?

    init(url: URL, source: String?) {
        self.url = url
        self.source = source
        originalName = url.lastPathComponent
    }
}

enum EngineState: Equatable { case loading, ready, unavailable(String) }

@Observable
final class AppModel {
    var engineState: EngineState = .loading
    var items: [Item] = []
    var recent: [RecentEntry] = [] { didSet { save(recent, "recent") } }
    /// ~/.config/pdf-namer/config.json, written back on every change from the settings window.
    var settings = UserConfig() {
        didSet {
            guard settings != oldValue, loaded else { return }  // loading the file must not rewrite it
            saveConfig()
            if oldValue.watchedFolders != settings.watchedFolders { syncWatchers() }
        }
    }
    /// A config file exists but can't be read: shown, and nothing is written.
    var configError: String?
    /// Settings this Mac overrides in config.local.json.
    var localKeys: [String] = []
    @ObservationIgnored private var configSource: DispatchSourceFileSystemObject?
    var lastHousekeeping: String?

    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var engine: Engine?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var watchers: [String: FolderWatcher] = [:]
    @ObservationIgnored private var housekeepingLoop: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.github.czj.pdf-namer", category: "app")

    var isBusy: Bool { items.contains { $0.phase.isPending } }
    var finishedCount: Int { items.filter { !$0.phase.isPending }.count }
    var backupDir: URL { settings.backupURL }
    var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    init() {
        reloadConfig()
        watchConfig()
        recent = load("recent") ?? []
        do {
            engine = try Engine()
            engineState = .ready
        } catch {
            engineState = .unavailable(error.localizedDescription)
        }
        syncWatchers()
        housekeepingLoop = Task { [weak self] in  // at launch, then daily
            while !Task.isCancelled {
                await self?.runHousekeeping()
                try? await Task.sleep(for: .seconds(86400))
            }
        }
        if hasBundle { UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in } }
    }

    // MARK: Queue

    /// Files dropped, chosen or pasted (folders: their files), or arriving in a watched folder.
    func add(_ urls: [URL], source: String? = nil) {
        var files: [URL] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                           options: .skipsHiddenFiles)) ?? []
                files += inside.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else {
                files.append(url)
            }
        }
        for url in files where Config.isSupported(url) {
            guard !items.contains(where: { $0.url == url && $0.phase.isPending }) else { continue }
            let item = Item(url: url, source: source)
            if Naming.isNamed(url.lastPathComponent) { item.phase = .skipped("déjà nommé (« AAAA-MM-JJ - … »)") }
            items.append(item)
        }
        if worker == nil { worker = Task { await drain() } }
    }

    private func drain() async {
        while let item = items.first(where: { $0.phase == .waiting }) {
            await process(item)
        }
        worker = nil
    }

    /// Start reading a file (render + OCR, off the main actor) if it isn't already.
    private func startExtraction(_ item: Item) -> Task<Extracted, Error> {
        if let task = item.extraction { return task }
        let task = Task { [url = item.url] in try await Extractor.extract(url) }
        item.extraction = task
        return task
    }

    private func process(_ item: Item) async {
        let t0 = Date()
        do {
            item.phase = .reading
            let extraction = startExtraction(item)
            // Overlap the next file's OCR with this file's model call: one file ahead, never more.
            if let next = items.first(where: { $0.phase == .waiting }) { _ = startExtraction(next) }
            let ex = try await extraction.value
            guard let engine else { throw EngineError.unavailable("non chargé") }
            item.phase = .analyzing
            guard let s = try await Namer.suggest(item.url, ex, engine: engine) else {
                item.phase = .skipped("rien de lisible"); return
            }
            item.suggestion = s
            item.took = Date().timeIntervalSince(t0)
            if s.name == item.url.lastPathComponent {
                item.phase = .unchanged
            } else if settings.confirmBeforeRename && item.source == nil {
                item.phase = .proposed
            } else {
                apply(item, name: s.name)
            }
        } catch {
            item.phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Actions

    /// First rename (with backup), or a later edit of the name.
    func apply(_ item: Item, name rawName: String) {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        let ext = "." + item.url.pathExtension.lowercased()
        if !name.lowercased().hasSuffix(ext) { name += ext }
        guard name != item.url.lastPathComponent, !name.contains("/") else { return }
        do {
            let firstRename = item.phase != .done
            let final = firstRename ? try Files.rename(item.url, to: name, backupDir: backupDir)
                                    : try Files.move(item.url, to: name)
            ignore(final)
            item.url = final
            item.phase = .done
            recent.removeAll { $0.path == final.path || $0.oldName == item.originalName && !firstRename }
            recent.insert(RecentEntry(oldName: item.originalName, path: final.path, date: Date()), at: 0)
            recent = Array(recent.prefix(20))
            if firstRename, let source = item.source { notify(source, final.lastPathComponent) }
        } catch {
            item.phase = .failed(error.localizedDescription)
        }
    }

    /// Put the original name back (the backup copy stays in the backup folder).
    func undo(_ item: Item) {
        do {
            let original = item.url.deletingLastPathComponent().appendingPathComponent(item.originalName)
            ignore(original)
            item.url = try Files.move(item.url, to: item.originalName)
            item.phase = .cancelled
            recent.removeAll { $0.oldName == item.originalName }
        } catch {
            item.phase = .failed(error.localizedDescription)
        }
    }

    func skip(_ item: Item) { item.phase = .skipped("ignoré") }

    func stop() {
        for item in items where item.phase == .waiting {
            item.extraction?.cancel()
            item.phase = .skipped("arrêté")
        }
    }

    func clear() { items.removeAll { !$0.phase.isPending } }

    func chooseFiles() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf, .image]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func paste() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                    options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        add(urls)
    }

    func showBackups() {
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupDir)
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    // MARK: Watched folders

    private func syncWatchers() {
        let wanted = Set(settings.watchedFolders.filter(\.enabled).map(\.url.path))
        for path in watchers.keys where !wanted.contains(path) { watchers[path] = nil }
        for path in wanted where watchers[path] == nil {
            let url = URL(fileURLWithPath: path)
            watchers[path] = FolderWatcher(url) { [weak self] urls in self?.add(urls, source: url.lastPathComponent) }
        }
    }

    /// A file we just renamed or restored must not look like a new arrival.
    private func ignore(_ url: URL) {
        watchers[url.deletingLastPathComponent().path]?.ignore(url)
    }

    func addFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !settings.watchedFolders.contains(where: { $0.url.path == url.path }) {
            settings.watchedFolders.append(UserConfig.Folder(path: url.path))
        }
    }

    private func notify(_ folder: String, _ name: String) {
        guard hasBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "PDF Namer · dossier \(folder)"
        content.body = "Nouveau fichier renommé : « \(name) »"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: Housekeeping, login item

    func runHousekeeping() async {
        let r = await Files.housekeeping(backupDir, backupMaxAgeDays: settings.backupMaxAge,
                                         expireMaxAgeDays: settings.expireMaxAge)
        lastHousekeeping = "\(r.purged.count) sauvegarde(s) supprimée(s), \(r.trashed.count) élément(s) mis à la corbeille"
        log.info("Ménage : \(r.purged.count) sauvegarde(s), \(r.trashed.count) élément(s) à la corbeille")
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("Ouverture au démarrage : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Persistence

    /// The settings window only ever writes this Mac's overrides (config.local.json).
    private func saveConfig() {
        guard configError == nil else { return }
        do {
            try settings.saveLocal()
            localKeys = UserConfig.localKeys()
        } catch {
            configError = "Enregistrement impossible : \(error.localizedDescription)"
        }
    }

    /// Reload both files (at launch, and whenever one changes, e.g. after `chezmoi apply`).
    func reloadConfig() {
        loaded = false
        defer { loaded = true }
        do {
            let fresh = try UserConfig.load()
            configError = nil
            localKeys = UserConfig.localKeys()
            guard fresh != settings else { return }
            let foldersChanged = fresh.watchedFolders != settings.watchedFolders
            settings = fresh
            if foldersChanged { syncWatchers() }
        } catch {
            configError = "Configuration illisible : \(error.localizedDescription)"
        }
    }

    /// Drop this Mac's overrides: back to config.json.
    func resetLocalConfig() {
        try? FileManager.default.removeItem(at: UserConfig.localFileURL)
        reloadConfig()
    }

    func openConfigFolder() {
        try? FileManager.default.createDirectory(at: UserConfig.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(UserConfig.directory)
    }

    private func watchConfig() {
        try? FileManager.default.createDirectory(at: UserConfig.directory, withIntermediateDirectories: true)
        let fd = open(UserConfig.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reloadConfig() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        configSource = src
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
