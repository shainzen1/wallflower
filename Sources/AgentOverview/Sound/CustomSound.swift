import AVFoundation
import Foundation

/// The person's own sound: which files are accepted and the copy kept in the sounds folder, so
/// moving or deleting the original never breaks it. The folder holds at most that one file; a new
/// one replaces it.
enum CustomSound {
    /// The file types accepted (by extension, any case).
    static let allowedExtensions: Set<String> = ["aiff", "aif", "wav", "mp3", "m4a", "caf"]
    /// Largest file accepted: 5 MB.
    static let maxBytes = 5 * 1024 * 1024
    /// Longest sound accepted, in seconds. Longer ones are refused rather than cut.
    static let maxDuration: TimeInterval = 5

    /// Why a file was refused, with the sentence Settings shows.
    enum Problem: Error, Equatable {
        case unsupportedType(name: String)
        case tooLarge(name: String, bytes: Int)
        case tooLong(name: String, seconds: TimeInterval)
        case unreadable(name: String)
        case copyFailed(name: String)

        var message: String {
            switch self {
            case .unsupportedType(let name):
                "\u{201C}\(name)\u{201D} isn't a sound file \(AppInfo.name) can play. Choose an AIFF, WAV, MP3, M4A or CAF file."
            case .tooLarge(let name, let bytes):
                "\u{201C}\(name)\u{201D} is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)). Choose a file of 5 MB or less."
            case .tooLong(let name, let seconds):
                "\u{201C}\(name)\u{201D} is \(String(format: "%.1f", seconds)) seconds long. Choose a sound of 5 seconds or less."
            case .unreadable(let name):
                "\u{201C}\(name)\u{201D} couldn't be read as a sound."
            case .copyFailed(let name):
                "\u{201C}\(name)\u{201D} couldn't be copied into \(AppInfo.name)'s folder."
            }
        }
    }

    /// The rules on what is known about a file: its extension, size and duration (nil when it could
    /// not be decoded). Checked in that order, so a file of the wrong type or size is never opened.
    static func check(name: String, fileExtension: String, byteCount: Int, duration: TimeInterval?) -> Problem? {
        guard allowedExtensions.contains(fileExtension.lowercased()) else { return .unsupportedType(name: name) }
        guard byteCount <= maxBytes else { return .tooLarge(name: name, bytes: byteCount) }
        guard let duration, duration > 0 else { return .unreadable(name: name) }
        guard duration <= maxDuration else { return .tooLong(name: name, seconds: duration) }
        return nil
    }

    /// Checks the file at `url`: type and size from the file system, then its duration by opening it.
    static func validate(_ url: URL) -> Problem? {
        let name = url.lastPathComponent
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return .unsupportedType(name: name) }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard let bytes = values?.fileSize, values?.isRegularFile == true else { return .unreadable(name: name) }
        if bytes > maxBytes { return .tooLarge(name: name, bytes: bytes) }
        return check(name: name, fileExtension: url.pathExtension, byteCount: bytes, duration: duration(of: url))
    }

    /// The sound's length in seconds, nil when it cannot be decoded.
    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }

    /// Validates `source` and copies it into `folder` under its own name, replacing whatever was
    /// there. Returns the stored file name.
    static func install(_ source: URL, into folder: URL) throws(Problem) -> String {
        if let problem = validate(source) { throw problem }
        let name = source.lastPathComponent
        let manager = FileManager.default
        let destination = folder.appending(path: name)
        // Choosing the copy itself again: keep it, drop anything else.
        if source.standardizedFileURL.resolvingSymlinksInPath() == destination.standardizedFileURL.resolvingSymlinksInPath() {
            removeEverything(in: folder, except: name)
            return name
        }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            // Copied next to its final place first, so a failed copy leaves the old sound in place.
            let incoming = folder.appending(path: ".incoming-\(UUID().uuidString).\(source.pathExtension)")
            try manager.copyItem(at: source, to: incoming)
            removeEverything(in: folder, except: incoming.lastPathComponent)
            try manager.moveItem(at: incoming, to: destination)
        } catch {
            throw .copyFailed(name: name)
        }
        return name
    }

    /// The stored copy named `name`, nil when it is gone.
    static func installedURL(named name: String, in folder: URL) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        let url = folder.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func removeEverything(in folder: URL, except keep: String) {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent != keep {
            try? manager.removeItem(at: entry)
        }
    }
}
