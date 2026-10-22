import AppKit
import Foundation

enum SingleInstanceGuard {
    // Share this lock with Lidwake to prevent both brands controlling system sleep at once.
    private static let lockFileDescriptorKey = "com.local.lidwake.lockfd"

    private static var defaultLockURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("com.local.lidwake.lock")
    }

    static func activate() -> Bool {
        let fd = open(defaultLockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }

        UserDefaults.standard.set(fd, forKey: lockFileDescriptorKey)
        return true
    }

    static func isPrimaryInstanceActive(lockURL: URL? = nil) -> Bool {
        let lockURL = lockURL ?? defaultLockURL
        switch RecoveryFileLock.acquire(at: lockURL, nonBlocking: true) {
        case .busy:
            return true
        case .acquired(let lock):
            withExtendedLifetime(lock) {}
            return false
        case .failed:
            return false
        }
    }
}
