import Darwin
import Foundation

enum RecoveryPaths {
    // Keep the existing namespace so pending safety recovery records survive the rename.
    static var transientDirectoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.local.lidwake.recovery", isDirectory: true)
    }

    static var durableDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("Lidwake", isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

final class RecoveryFileLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
    }

    static func acquire(at url: URL, nonBlocking: Bool) -> RecoveryFileLockAcquisition {
        do {
            try RecoveryPaths.ensureDirectory(url.deletingLastPathComponent())
        } catch {
            return .failed("create lock directory: \(error.localizedDescription)")
        }

        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return .failed("open lock file: errno \(errno)")
        }
        let operation = LOCK_EX | (nonBlocking ? LOCK_NB : 0)
        guard flock(descriptor, operation) == 0 else {
            let lockError = errno
            _ = close(descriptor)
            if nonBlocking, lockError == EWOULDBLOCK {
                return .busy
            }
            return .failed("flock: errno \(lockError)")
        }
        return .acquired(RecoveryFileLock(descriptor: descriptor))
    }
}

enum RecoveryFileLockAcquisition {
    case acquired(RecoveryFileLock)
    case busy
    case failed(String)
}

enum RecoveryCoordinator {
    static func acquire() -> RecoveryFileLockAcquisition {
        RecoveryFileLock.acquire(
            at: RecoveryPaths.transientDirectoryURL.appendingPathComponent("automatic-recovery.lock"),
            nonBlocking: true
        )
    }
}

enum SupervisorRecoveryState: String, Codable {
    case monitoring
    case recovering
    case delegated
    case succeeded
    case failed
    case stopped
}

struct SupervisorRecoveryRecord: Codable, Equatable {
    var supervisorProcessID: pid_t
    var executablePath: String
    var state: SupervisorRecoveryState
    var sessionID: UUID?
}

enum RecoverySessionState: String, Codable {
    case recovering
    case succeeded
    case failed
}

struct RecoverySessionRecord: Codable, Equatable {
    var id: UUID
    var coordinatorProcessID: pid_t
    var executablePath: String
    var state: RecoverySessionState
}

enum SupervisorRecoveryJournal {
    static func register(
        parentPID: pid_t,
        supervisorProcessID: pid_t,
        executablePath: String,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> Bool {
        write(
            SupervisorRecoveryRecord(
                supervisorProcessID: supervisorProcessID,
                executablePath: executablePath,
                state: .monitoring,
                sessionID: nil
            ),
            to: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func beginSession(
        parentPID: pid_t,
        coordinatorProcessID: pid_t,
        executablePath: String,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> UUID? {
        let sessionID = UUID()
        let session = RecoverySessionRecord(
            id: sessionID,
            coordinatorProcessID: coordinatorProcessID,
            executablePath: executablePath,
            state: .recovering
        )
        guard write(session, to: sessionURL(directoryURL: directoryURL)),
              write(
                  SupervisorRecoveryRecord(
                      supervisorProcessID: coordinatorProcessID,
                      executablePath: executablePath,
                      state: .recovering,
                      sessionID: sessionID
                  ),
                  to: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
              ) else {
            return nil
        }
        return sessionID
    }

    static func delegateToActiveSession(
        parentPID: pid_t,
        supervisorProcessID: pid_t,
        executablePath: String,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> Bool {
        guard let session: RecoverySessionRecord = read(
            from: sessionURL(directoryURL: directoryURL)
        ) else {
            return false
        }
        let state: SupervisorRecoveryState
        switch session.state {
        case .recovering:
            guard ProcessIdentity.matches(
                processID: session.coordinatorProcessID,
                executablePath: session.executablePath
            ) else {
                return false
            }
            state = .delegated
        case .succeeded:
            state = .succeeded
        case .failed:
            state = .failed
        }
        return write(
            SupervisorRecoveryRecord(
                supervisorProcessID: supervisorProcessID,
                executablePath: executablePath,
                state: state,
                sessionID: session.id
            ),
            to: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func finishSession(
        parentPID: pid_t,
        sessionID: UUID,
        coordinatorProcessID: pid_t,
        executablePath: String,
        succeeded: Bool,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) {
        let sessionState: RecoverySessionState = succeeded ? .succeeded : .failed
        let supervisorState: SupervisorRecoveryState = succeeded ? .succeeded : .failed
        _ = write(
            RecoverySessionRecord(
                id: sessionID,
                coordinatorProcessID: coordinatorProcessID,
                executablePath: executablePath,
                state: sessionState
            ),
            to: sessionURL(directoryURL: directoryURL)
        )
        _ = write(
            SupervisorRecoveryRecord(
                supervisorProcessID: coordinatorProcessID,
                executablePath: executablePath,
                state: supervisorState,
                sessionID: sessionID
            ),
            to: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func markFailed(
        parentPID: pid_t,
        supervisorProcessID: pid_t,
        executablePath: String,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) {
        _ = write(
            SupervisorRecoveryRecord(
                supervisorProcessID: supervisorProcessID,
                executablePath: executablePath,
                state: .failed,
                sessionID: nil
            ),
            to: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func markStopped(
        parentPID: pid_t,
        supervisorProcessID: pid_t,
        executablePath: String,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) {
        _ = write(
            SupervisorRecoveryRecord(
                supervisorProcessID: supervisorProcessID,
                executablePath: executablePath,
                state: .stopped,
                sessionID: nil
            ),
            to: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func isStopped(
        parentPID: pid_t,
        supervisorProcessID: pid_t,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> Bool {
        let record: SupervisorRecoveryRecord? = read(
            from: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
        return record?.supervisorProcessID == supervisorProcessID
            && record?.state == .stopped
    }

    static func waitForSuccessfulHandoff(
        parentPID: pid_t,
        timeout: TimeInterval = 3 * 60,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let supervisor: SupervisorRecoveryRecord = read(
                from: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
            ) else {
                return false
            }

            switch supervisor.state {
            case .succeeded:
                return true
            case .failed, .stopped:
                return false
            case .recovering, .delegated:
                guard let sessionID = supervisor.sessionID,
                      let session: RecoverySessionRecord = read(
                          from: sessionURL(directoryURL: directoryURL)
                      ),
                      session.id == sessionID else {
                    return false
                }
                switch session.state {
                case .succeeded:
                    return true
                case .failed:
                    return false
                case .recovering:
                    if !ProcessIdentity.matches(
                        processID: session.coordinatorProcessID,
                        executablePath: session.executablePath
                    ) {
                        let latest: RecoverySessionRecord? = read(
                            from: sessionURL(directoryURL: directoryURL)
                        )
                        return latest?.id == sessionID && latest?.state == .succeeded
                    }
                }
            case .monitoring:
                if !ProcessIdentity.matches(
                    processID: supervisor.supervisorProcessID,
                    executablePath: supervisor.executablePath
                ) {
                    let latest: SupervisorRecoveryRecord? = read(
                        from: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
                    )
                    return latest?.state == .succeeded
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    static func clearSupervisor(
        parentPID: pid_t,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) {
        try? FileManager.default.removeItem(
            at: supervisorURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func currentSessionState(
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> RecoverySessionState? {
        let session: RecoverySessionRecord? = read(
            from: sessionURL(directoryURL: directoryURL)
        )
        return session?.state
    }

    private static func supervisorURL(parentPID: pid_t, directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("app-supervisor-\(parentPID).json")
    }

    private static func sessionURL(directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("automatic-recovery-session.json")
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try RecoveryPaths.ensureDirectory(url.deletingLastPathComponent())
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            AppLog.write("failed to update recovery journal: \(error.localizedDescription)")
            return false
        }
    }

    private static func read<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum AppRecoveryHandshake {
    static let tokenArgument = "--recovery-token"
    private static let artifactExtensions = ["started", "ready", "cancelled"]

    static func token(from arguments: [String]) -> UUID? {
        guard arguments.contains(AppSupervisor.recoveredLaunchArgument),
              let index = arguments.firstIndex(of: tokenArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return UUID(uuidString: arguments[index + 1])
    }

    @discardableResult
    static func signalStartedIfRequested(
        arguments: [String],
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        guard let token = token(from: arguments) else { return false }
        return write(String(processID), to: startedURL(for: token))
    }

    @discardableResult
    static func signalReadyIfRequested(
        arguments: [String],
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        guard let token = token(from: arguments) else { return false }
        return write(String(processID), to: readyURL(for: token))
    }

    static func startedProcessID(for token: UUID) -> pid_t? {
        readProcessID(from: startedURL(for: token))
    }

    static func isReady(token: UUID, processID: pid_t) -> Bool {
        readProcessID(from: readyURL(for: token)) == processID
    }

    @discardableResult
    static func signalCancelledIfRequested(
        arguments: [String],
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        guard let token = token(from: arguments) else { return false }
        return write(String(processID), to: cancelledURL(for: token))
    }

    static func isCancelled(token: UUID, processID: pid_t) -> Bool {
        readProcessID(from: cancelledURL(for: token)) == processID
    }

    static func cleanup(token: UUID) {
        try? FileManager.default.removeItem(at: startedURL(for: token))
        try? FileManager.default.removeItem(at: readyURL(for: token))
        try? FileManager.default.removeItem(at: cancelledURL(for: token))
    }

    static func cleanupOrphanedArtifacts(
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let tokenStrings = Set(fileURLs.compactMap { artifactToken(from: $0.lastPathComponent) })
        for tokenString in tokenStrings {
            let artifactURLs = artifactExtensions.map {
                directoryURL.appendingPathComponent("app-\(tokenString).\($0)")
            }
            let hasLiveOwner = artifactURLs.contains { url in
                guard let processID = readProcessID(from: url) else { return false }
                return ProcessIdentity.isRunning(processID: processID)
            }
            guard !hasLiveOwner else { continue }
            artifactURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private static func artifactToken(from fileName: String) -> String? {
        guard fileName.hasPrefix("app-") else { return nil }
        for artifactExtension in artifactExtensions {
            let suffix = ".\(artifactExtension)"
            guard fileName.hasSuffix(suffix) else { continue }
            let tokenStart = fileName.index(fileName.startIndex, offsetBy: 4)
            let tokenEnd = fileName.index(fileName.endIndex, offsetBy: -suffix.count)
            let tokenString = String(fileName[tokenStart..<tokenEnd])
            guard UUID(uuidString: tokenString) != nil else { return nil }
            return tokenString.lowercased()
        }
        return nil
    }

    private static func startedURL(for token: UUID) -> URL {
        RecoveryPaths.transientDirectoryURL
            .appendingPathComponent("app-\(token.uuidString.lowercased()).started")
    }

    private static func readyURL(for token: UUID) -> URL {
        RecoveryPaths.transientDirectoryURL
            .appendingPathComponent("app-\(token.uuidString.lowercased()).ready")
    }

    private static func cancelledURL(for token: UUID) -> URL {
        RecoveryPaths.transientDirectoryURL
            .appendingPathComponent("app-\(token.uuidString.lowercased()).cancelled")
    }

    private static func write(_ value: String, to url: URL) -> Bool {
        do {
            try RecoveryPaths.ensureDirectory(url.deletingLastPathComponent())
            try Data(value.utf8).write(to: url, options: [.atomic])
            return true
        } catch {
            AppLog.write("failed to write application recovery handshake: \(error.localizedDescription)")
            return false
        }
    }

    private static func readProcessID(from url: URL) -> pid_t? {
        guard let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8),
              let processID = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              processID > 1 else {
            return nil
        }
        return processID
    }
}

enum ProcessIdentity {
    static func executablePath(processID: pid_t) -> String? {
        guard processID > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(processID, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer
            .prefix(Int(length))
            .prefix(while: { $0 != 0 })
            .map(UInt8.init(bitPattern:))
        return String(decoding: bytes, as: UTF8.self)
    }

    static func matches(processID: pid_t, executablePath: String) -> Bool {
        guard let actualPath = self.executablePath(processID: processID) else { return false }
        return URL(fileURLWithPath: actualPath).resolvingSymlinksInPath().standardizedFileURL
            == URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().standardizedFileURL
    }

    static func isRunning(processID: pid_t) -> Bool {
        guard processID > 1 else { return false }
        if kill(processID, 0) == 0 { return true }
        return errno == EPERM
    }

    static func terminateImmediately(processID: pid_t, executablePath: String) {
        guard matches(processID: processID, executablePath: executablePath) else { return }
        _ = kill(processID, SIGKILL)
    }
}

enum ProcessExitWaiter {
    static func wait(processID: pid_t) -> Bool {
        guard processID > 1 else { return true }
        guard ProcessIdentity.isRunning(processID: processID) else { return true }

        let queue = kqueue()
        guard queue >= 0 else { return false }
        defer { _ = close(queue) }

        var change = kevent(
            ident: UInt(processID),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT),
            fflags: UInt32(NOTE_EXIT),
            data: 0,
            udata: nil
        )
        guard kevent(queue, &change, 1, nil, 0, nil) == 0 else {
            return !ProcessIdentity.isRunning(processID: processID)
        }

        var event = kevent()
        while true {
            let result = kevent(queue, nil, 0, &event, 1, nil)
            if result > 0 { return true }
            if result < 0, errno == EINTR { continue }
            return false
        }
    }
}
