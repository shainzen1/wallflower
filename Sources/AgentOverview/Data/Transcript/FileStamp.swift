import Foundation

/// Size and modification time of a file, from one `stat` call. Two equal stamps mean the file
/// has not changed since (appends change both; mtime has nanosecond resolution on APFS).
/// `URL.resourceValues` is avoided because its values can be cached per URL object.
struct FileStamp: Equatable, Sendable {
    var size: Int
    var modified: Date

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        size = Int(info.st_size)
        let seconds = TimeInterval(info.st_mtimespec.tv_sec)
        modified = Date(timeIntervalSince1970: seconds + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }
}
