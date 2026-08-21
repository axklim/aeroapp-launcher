import Foundation

/// Watches the config file and calls back, debounced, when it changes.
///
/// Two watches are needed. Editors and dotfile managers usually replace the file
/// (write a temp name, rename over it), which a watch on the old inode never sees
/// but the directory does; other tools write in place, which the directory never
/// sees but the inode does. So the directory is watched permanently and the file
/// watch is re-armed on the current inode after every directory event.
final class ConfigWatcher {
    private let file: URL
    private let onChange: () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(file: URL, onChange: @escaping () -> Void) {
        self.file = file
        self.onChange = onChange
    }

    /// Returns false when the directory cannot be opened; the caller decides
    /// whether that deserves a log line.
    @discardableResult
    func start() -> Bool {
        guard let source = makeSource(path: file.deletingLastPathComponent().path, mask: [.write, .rename, .delete]) else {
            return false
        }
        directorySource = source
        watchFile()
        return true
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: file.path, mask: [.write, .extend, .attrib, .delete, .rename])
    }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // The file may be a new inode now (rename over), or newly created.
            self.watchFile()
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
