import Foundation
import PDFNamerCore

/// Reports PDFs and images that newly arrive in a folder, once their size has settled
/// (a scanner or a download may still be writing). Files present at start are left alone,
/// and so are files already named "AAAA-MM-JJ - …".
@MainActor
final class FolderWatcher {
    private let url: URL
    private let onNew: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String>
    private var pending: [String: Int] = [:]  // path → last seen size
    private var checkScheduled = false

    init(_ url: URL, onNew: @escaping ([URL]) -> Void) {
        self.url = url
        self.onNew = onNew
        known = Set(Self.candidates(in: url).map(\.path))
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { NSLog("PDF Namer: impossible de surveiller \(url.path)"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }

    func ignore(_ file: URL) { known.insert(file.path) }

    private static func candidates(in dir: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                                options: .skipsHiddenFiles)) ?? []
        return all.filter { Config.isSupported($0) && !Naming.isNamed($0.lastPathComponent) }
    }

    private func scan() {
        let present = Self.candidates(in: url)
        known = known.filter { FileManager.default.fileExists(atPath: $0) }  // forget files that left
        for file in present where !known.contains(file.path) && pending[file.path] == nil {
            pending[file.path] = -1
        }
        scheduleCheck()
    }

    private func scheduleCheck() {
        guard !pending.isEmpty, !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    /// Emit files whose size did not change since the last look.
    private func check() {
        checkScheduled = false
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
        scheduleCheck()
    }
}
