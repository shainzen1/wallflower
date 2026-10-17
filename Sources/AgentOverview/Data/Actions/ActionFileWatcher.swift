import Foundation

/// Watches one file off the main actor and reports, debounced, whenever it changed, was replaced
/// or reappeared. Editors save by writing a new file and renaming it over the old one, so the file
/// descriptor sees a rename and must be reopened; while the file is missing its folder is watched.
/// Mutable state is confined to `queue`.
final class ActionFileWatcher: @unchecked Sendable {
    typealias ChangeHandler = @Sendable () -> Void

    private let url: URL
    private let onChange: ChangeHandler
    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).actions", qos: .utility)

    // Queue-confined state.
    private var fileSource: DispatchSourceFileSystemObject?
    private var folderSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var isStopped = false

    private static var eventMask: DispatchSource.FileSystemEvent { [.write, .extend, .attrib, .delete, .rename, .revoke] }
    private static var goneMask: DispatchSource.FileSystemEvent { [.delete, .rename, .revoke] }

    init(url: URL, onChange: @escaping ChangeHandler) {
        self.url = url
        self.onChange = onChange
    }

    /// Installs the sources before returning, so a write right after `start()` is seen.
    /// The initial read is the caller's business.
    func start() {
        queue.sync { [self] in
            guard !isStopped else { return }
            watchFile()
            watchFolder()
        }
    }

    func stop() {
        queue.async { [self] in
            isStopped = true
            pending?.cancel()
            pending = nil
            fileSource?.cancel()
            fileSource = nil
            folderSource?.cancel()
            folderSource = nil
        }
    }

    // MARK: Queue-confined

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: url.path) { [weak self] flags in
            guard let self else { return }
            if !flags.isDisjoint(with: Self.goneMask) { self.watchFile() }
            self.scheduleChange()
        }
    }

    private func watchFolder() {
        folderSource?.cancel()
        folderSource = makeSource(path: url.deletingLastPathComponent().path) { [weak self] _ in
            guard let self else { return }
            if self.fileSource == nil { self.watchFile() }
            self.scheduleChange()
        }
    }

    private func scheduleChange() {
        guard !isStopped else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.pending = nil
            self.onChange()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + DataTuning.scanDebounce, execute: item)
    }

    private func makeSource(path: String, handler: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: Self.eventMask, queue: queue)
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.setCancelHandler { close(fd) }
        source.activate()
        return source
    }
}
