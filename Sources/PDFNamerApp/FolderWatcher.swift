import Foundation
import OSLog
import PDFNamerCore

/// Reports PDFs and images that newly arrive in a folder, once their size has settled
/// (a scanner or a download may still be writing). Files present at start are left alone,
/// and so are files already named "AAAA-MM-JJ - …".
final class FolderWatcher {
    private let url: URL
    private let onNew: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String>
    private var pending: [String: Int] = [:]  // path → last seen size
    private var settling: Task<Void, Never>?

    init(_ url: URL, onNew: @escaping ([URL]) -> Void) {
        self.url = url
        self.onNew = onNew
        known = Set(Self.candidates(in: url).map(\.path))
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Logger(subsystem: "com.github.czj.pdf-namer", category: "watch")
                .error("Impossible de surveiller \(url.path, privacy: .private)")
            return
        }
        // Dispatch sources predate Swift concurrency; the handler runs on the main queue.
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    isolated deinit {
        source?.cancel()
        settling?.cancel()
    }

    func ignore(_ file: URL) { known.insert(file.path) }

    private static func candidates(in dir: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                                options: .skipsHiddenFiles)) ?? []
        return all.filter { Config.isSupported($0) && !Naming.isNamed($0.lastPathComponent) }
    }

    private func scan() {
        known = known.filter { FileManager.default.fileExists(atPath: $0) }  // forget files that left
        for file in Self.candidates(in: url) where !known.contains(file.path) && pending[file.path] == nil {
            pending[file.path] = -1
        }
        guard !pending.isEmpty, settling == nil else { return }
        settling = Task { [weak self] in
            while let self, !self.pending.isEmpty {
                try? await Task.sleep(for: .seconds(1.5))
                self.check()
            }
            self?.settling = nil
        }
    }

    /// Emit files whose size did not change since the last look.
    private func check() {
        var ready: [URL] = []
        for (path, last) in pending {
            guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int else {
                pending[path] = nil  // gone (moved, deleted, renamed by the download)
                continue
            }
            if size > 0 && size == last {
                pending[path] = nil
                known.insert(path)
                ready.append(URL(fileURLWithPath: path))
            } else {
                pending[path] = size
            }
        }
        if !ready.isEmpty { onNew(ready.sorted { $0.path < $1.path }) }
    }
}
