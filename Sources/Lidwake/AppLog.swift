import Darwin
import Foundation

enum AppLog {
    private static let maximumLogSize: UInt64 = 1_000_000
    private static let lock = NSLock()

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("\(Brand.executableName).log")

        if !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let fileLockURL = url.appendingPathExtension("lock")
        let fileLockDescriptor = open(
            fileLockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard fileLockDescriptor >= 0 else { return }
        defer {
            _ = flock(fileLockDescriptor, LOCK_UN)
            _ = close(fileLockDescriptor)
        }
        while flock(fileLockDescriptor, LOCK_EX) != 0 {
            if errno != EINTR { return }
        }

        rotateIfNeeded(url)
        guard let data = line.data(using: .utf8) else { return }
        append(data, to: url)
    }

    private static func rotateIfNeeded(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value >= maximumLogSize else {
            return
        }

        let backupURL = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
    }

    private static func append(_ data: Data, to url: URL) {
        let descriptor = open(
            url.path,
            O_CREAT | O_WRONLY | O_APPEND,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { return }
        defer { _ = close(descriptor) }

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}
