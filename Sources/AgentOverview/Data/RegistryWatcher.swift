import Foundation

/// Watches the registry folder off the main actor and reports debounced scan results.
///
/// One `DispatchSource` on the folder catches files appearing and disappearing. Claude Code
/// rewrites `<pid>.json` in place for status changes (same inode, `fs.writeFile`), which a
/// folder descriptor never sees, so every tracked file gets its own vnode source too.
/// All sources fire on one private serial queue; events are debounced and then one scan runs.
/// If the folder itself is deleted or renamed, the descriptor is reopened; while it is missing
/// its nearest existing ancestor is watched (`~/.claude`, or `~` when that is missing too), and each
/// change there re-arms one level further down until the folder itself is back. No polling.
///
/// The same watcher serves the external sessions folder (`external(folder:onScan:)`): only the scan
/// differs, and a pass can ask for one more scan at a time (`Pass.rescanAt`, the TTL expiry of a
/// pid-less external record), armed as a one-shot on the wall clock, never repeated.
///
/// All mutable state is confined to `queue`, which is what makes the class safe to share.
final class RegistryWatcher: @unchecked Sendable {
    typealias ScanHandler = @Sendable (RegistryScanResult) -> Void

    /// What one scan tells the watcher: the files to watch, and when to scan again without an event.
    struct Pass: Sendable {
        var fileURLs: [URL]
        var rescanAt: Date?
    }

    private let folder: URL
    /// Scans the folder, reports the typed result itself and returns what the watcher needs.
    private let scan: @Sendable () -> Pass
    private let queue: DispatchQueue

    // Queue-confined state.
    private var folderSource: DispatchSourceFileSystemObject?
    /// Watches `watchedAncestor` while the folder is missing.
    private var ancestorSource: DispatchSourceFileSystemObject?
    private var watchedAncestor: URL?
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingScan: DispatchWorkItem?
    /// The one-shot rescan of `Pass.rescanAt`, replaced by every scan.
    private var pendingExpiry: DispatchWorkItem?
    private var isStopped = false

    private static var eventMask: DispatchSource.FileSystemEvent { [.write, .extend, .attrib, .delete, .rename, .revoke] }
    private static var goneMask: DispatchSource.FileSystemEvent { [.delete, .rename, .revoke] }

    /// Watches the Claude Code registry: `SessionRegistryScanner` with the entrypoint filter.
    convenience init(folder: URL, entrypoints: Set<String>?, onScan: @escaping ScanHandler) {
        self.init(folder: folder, label: "registry") {
            let result = SessionRegistryScanner.scan(folder: folder, entrypoints: entrypoints)
            onScan(result)
            return Pass(fileURLs: result.fileURLs, rescanAt: nil)
        }
    }

    /// Watches the external sessions folder: `ExternalSessionScanner`, rescanning once when the next
    /// pid-less record runs out of its TTL.
    static func external(
        folder: URL, ttl: TimeInterval = DataTuning.externalSessionTTL,
        onScan: @escaping @Sendable (ExternalScanResult) -> Void
    ) -> RegistryWatcher {
        RegistryWatcher(folder: folder, label: "external") {
            let result = ExternalSessionScanner.scan(folder: folder, now: Date(), ttl: ttl)
            onScan(result)
            return Pass(fileURLs: result.fileURLs, rescanAt: result.nextExpiry)
        }
    }

    init(folder: URL, label: String, scan: @escaping @Sendable () -> Pass) {
        self.folder = folder
        self.scan = scan
        queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).\(label)", qos: .utility)
    }

    /// Installs the folder source and runs the initial scan.
    func start() {
        queue.async { [self] in
            guard !isStopped else { return }
            watchFolder()
            scanNow()
        }
    }

    /// Cancels every source and pending scan. Safe to call more than once.
    func stop() {
        queue.async { [self] in
            isStopped = true
            pendingScan?.cancel()
            pendingScan = nil
            pendingExpiry?.cancel()
            pendingExpiry = nil
            folderSource?.cancel()
            folderSource = nil
            stopWatchingAncestor()
            fileSources.values.forEach { $0.cancel() }
            fileSources.removeAll()
        }
    }

    // MARK: Queue-confined

    private func watchFolder() {
        folderSource?.cancel()
        folderSource = makeSource(path: folder.path) { [weak self] flags in
            self?.folderDidChange(flags)
        }
        if folderSource == nil {
            DataLog.registry.notice("Registry folder is missing, waiting for it to appear")
            watchAncestor()
        } else {
            stopWatchingAncestor()
        }
    }

    private func folderDidChange(_ flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: Self.goneMask) {
            // The folder itself went away or was swapped: reopen on the path.
            watchFolder()
        }
        scheduleScan()
    }

    /// Watches the folder's nearest existing ancestor (a no-op when that one is watched already).
    private func watchAncestor() {
        let ancestor = Self.nearestExistingAncestor(of: folder)
        guard ancestor != watchedAncestor || ancestorSource == nil else { return }
        ancestorSource?.cancel()
        watchedAncestor = ancestor
        ancestorSource = makeSource(path: ancestor.path) { [weak self] _ in
            self?.ancestorDidChange()
        }
        // A level created between the lookup and the open sent the new source no event: look again.
        if access(folder.path, F_OK) == 0 || Self.nearestExistingAncestor(of: folder) != ancestor {
            ancestorDidChange()
        }
    }

    /// Something changed in the watched ancestor: the folder is back, or a level below appeared (re-arm
    /// there), or the ancestor itself went away (re-arm further up).
    private func ancestorDidChange() {
        guard !isStopped else { return }
        if access(folder.path, F_OK) == 0 {
            watchFolder()
            scheduleScan()
        } else {
            watchAncestor()
        }
    }

    private func stopWatchingAncestor() {
        ancestorSource?.cancel()
        ancestorSource = nil
        watchedAncestor = nil
    }

    /// The closest folder above `url` that exists (the root at the latest).
    static func nearestExistingAncestor(of url: URL) -> URL {
        var ancestor = url.deletingLastPathComponent()
        while access(ancestor.path, F_OK) != 0, ancestor.path != "/" {
            ancestor = ancestor.deletingLastPathComponent()
        }
        return ancestor
    }

    private func fileDidChange(path: String, flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: Self.goneMask) {
            fileSources.removeValue(forKey: path)?.cancel()
        }
        scheduleScan()
    }

    /// Cancel-and-reschedule debounce: the scan runs once the folder has been quiet for the debounce window.
    private func scheduleScan() {
        guard !isStopped else { return }
        pendingScan?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scanNow() }
        pendingScan = item
        queue.asyncAfter(deadline: .now() + DataTuning.scanDebounce, execute: item)
    }

    private func scanNow() {
        guard !isStopped else { return }
        pendingScan = nil
        let pass = scan()
        syncFileSources(with: pass.fileURLs)
        armExpiry(at: pass.rescanAt)
    }

    /// One rescan at `date` (a little after, so the record is past its TTL), replacing the last one.
    /// On the wall clock, so a Mac that slept through the expiry rescans as it wakes.
    private func armExpiry(at date: Date?) {
        pendingExpiry?.cancel()
        pendingExpiry = nil
        guard let date else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingExpiry = nil
            self?.scanNow()
        }
        pendingExpiry = item
        let delay = max(0, date.timeIntervalSinceNow) + DataTuning.expiryRescanSlack
        queue.asyncAfter(wallDeadline: .now() + delay, execute: item)
    }

    /// One vnode source per registry file currently on disk; sources of vanished files are dropped.
    private func syncFileSources(with urls: [URL]) {
        let wanted = Set(urls.map(\.path))
        for path in fileSources.keys where !wanted.contains(path) {
            fileSources.removeValue(forKey: path)?.cancel()
        }
        for path in wanted where fileSources[path] == nil {
            fileSources[path] = makeSource(path: path) { [weak self] flags in
                self?.fileDidChange(path: path, flags: flags)
            }
        }
    }

    private func makeSource(
        path: String,
        handler: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
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
