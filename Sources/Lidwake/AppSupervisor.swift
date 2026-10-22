import Darwin
import Foundation

@MainActor
final class AppSupervisorController {
    private var process: Process?
    private var heartbeatHandle: FileHandle?
    private var supervisorExecutablePath: String?

    func start() throws {
        guard process?.isRunning != true else { return }
        let appBundleURL = Bundle.main.bundleURL
        guard appBundleURL.pathExtension == "app",
              let executableURL = helperExecutableURL() else {
            throw AppSupervisorError.helperUnavailable
        }

        let heartbeatPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            AppSupervisor.argument,
            String(ProcessInfo.processInfo.processIdentifier),
            appBundleURL.path
        ]
        process.standardInput = heartbeatPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        guard SupervisorRecoveryJournal.register(
            parentPID: ProcessInfo.processInfo.processIdentifier,
            supervisorProcessID: process.processIdentifier,
            executablePath: executableURL.path
        ) else {
            process.terminate()
            throw AppSupervisorError.recoveryJournalUnavailable
        }

        let handle = heartbeatPipe.fileHandleForWriting
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.process = process
        supervisorExecutablePath = executableURL.path
        heartbeatHandle = handle
        sendHeartbeat()
        AppLog.write("app supervisor started: \(process.processIdentifier)")
    }

    func pulse() {
        guard process?.isRunning == true else {
            do {
                try start()
            } catch {
                AppLog.write("failed to restart app supervisor: \(error.localizedDescription)")
            }
            return
        }
        sendHeartbeat()
    }

    func stop() {
        let process = process
        let heartbeatHandle = heartbeatHandle
        let executablePath = supervisorExecutablePath
        self.process = nil
        self.heartbeatHandle = nil
        supervisorExecutablePath = nil
        if let process, let executablePath {
            SupervisorRecoveryJournal.markStopped(
                parentPID: ProcessInfo.processInfo.processIdentifier,
                supervisorProcessID: process.processIdentifier,
                executablePath: executablePath
            )
        }
        if process?.isRunning == true {
            try? heartbeatHandle?.write(contentsOf: Data([AppSupervisor.shutdownByte]))
        }
        try? heartbeatHandle?.close()
        if let process, process.isRunning {
            waitForExit(process, timeout: 1)
            if process.isRunning {
                process.terminate()
                waitForExit(process, timeout: 1)
            }
        }
        SupervisorRecoveryJournal.clearSupervisor(
            parentPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    private func sendHeartbeat() {
        do {
            try heartbeatHandle?.write(contentsOf: Data([AppSupervisor.heartbeatByte]))
        } catch {
            AppLog.write("app supervisor heartbeat failed: \(error.localizedDescription)")
        }
    }

    private func helperExecutableURL() -> URL? {
        guard let mainExecutableURL = Bundle.main.executableURL else { return nil }
        let helperURL = mainExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent(Brand.watchdogExecutableName)
        if FileManager.default.isExecutableFile(atPath: helperURL.path) {
            return helperURL
        }
        return mainExecutableURL
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}

enum AppSupervisor {
    static let argument = "--app-supervisor"
    static let recoveredLaunchArgument = "--auto-recovered"
    static let heartbeatByte: UInt8 = 0x48
    static let shutdownByte: UInt8 = 0x51
    private static let heartbeatTimeoutMilliseconds: Int32 = 35_000
    private static let wakeGraceMilliseconds: Int32 = 15_000

    private enum ParentState {
        case exited
        case unresponsive
        case cleanShutdown
    }

    private enum HeartbeatEvent {
        case heartbeat
        case shutdown
        case exited
        case timedOut
        case retry
        case failed
    }

    static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.count == 4,
              arguments[1] == argument,
              let parentPID = pid_t(arguments[2]),
              parentPID > 1,
              arguments[3].hasSuffix(".app"),
              Bundle(url: URL(fileURLWithPath: arguments[3]))?.bundleIdentifier == Brand.bundleIdentifier else {
            return false
        }

        let supervisorProcessID = ProcessInfo.processInfo.processIdentifier
        let supervisorExecutablePath = ProcessIdentity.executablePath(
            processID: supervisorProcessID
        ) ?? CommandLine.arguments[0]
        guard SupervisorRecoveryJournal.register(
            parentPID: parentPID,
            supervisorProcessID: supervisorProcessID,
            executablePath: supervisorExecutablePath
        ) else {
            return true
        }

        let state = waitForParent(parentPID)
        if state == .cleanShutdown || SupervisorRecoveryJournal.isStopped(
            parentPID: parentPID,
            supervisorProcessID: supervisorProcessID
        ) {
            SupervisorRecoveryJournal.markStopped(
                parentPID: parentPID,
                supervisorProcessID: supervisorProcessID,
                executablePath: supervisorExecutablePath
            )
            return true
        }
        if state == .unresponsive {
            AppLog.write("app supervisor detected an unresponsive parent: \(parentPID)")
            terminateParent(parentPID)
        } else {
            AppLog.write("app supervisor detected an unexpected parent exit: \(parentPID)")
        }

        switch RecoveryCoordinator.acquire() {
        case .acquired(let recoveryLock):
            performCoordinatedRecovery(
                recoveryLock: recoveryLock,
                parentPID: parentPID,
                supervisorProcessID: supervisorProcessID,
                supervisorExecutablePath: supervisorExecutablePath,
                appPath: arguments[3]
            )
        case .busy:
            if SupervisorRecoveryJournal.delegateToActiveSession(
                parentPID: parentPID,
                supervisorProcessID: supervisorProcessID,
                executablePath: supervisorExecutablePath
            ) {
                AppLog.write("app supervisor delegated recovery to the active coordinator")
                let handoffSucceeded = SupervisorRecoveryJournal.waitForSuccessfulHandoff(
                    parentPID: parentPID
                )
                guard handoffSucceeded else { return true }
                guard !SingleInstanceGuard.isPrimaryInstanceActive() else {
                    AppLog.write("delegated recovery confirmed a live primary instance")
                    return true
                }
                guard let recoveryLock = waitForRecoveryCoordinator(timeout: 5) else {
                    AppLog.write("delegated recovery could not take over after the primary exited")
                    SupervisorRecoveryJournal.markFailed(
                        parentPID: parentPID,
                        supervisorProcessID: supervisorProcessID,
                        executablePath: supervisorExecutablePath
                    )
                    return true
                }
                AppLog.write("delegated recovery took over after the recovered primary exited")
                performCoordinatedRecovery(
                    recoveryLock: recoveryLock,
                    parentPID: parentPID,
                    supervisorProcessID: supervisorProcessID,
                    supervisorExecutablePath: supervisorExecutablePath,
                    appPath: arguments[3]
                )
            } else {
                AppLog.write("app supervisor found a busy recovery lock without a valid coordinator")
                SupervisorRecoveryJournal.markFailed(
                    parentPID: parentPID,
                    supervisorProcessID: supervisorProcessID,
                    executablePath: supervisorExecutablePath
                )
            }
        case .failed(let detail):
            AppLog.write("app supervisor could not acquire recovery coordination: \(detail)")
            SupervisorRecoveryJournal.markFailed(
                parentPID: parentPID,
                supervisorProcessID: supervisorProcessID,
                executablePath: supervisorExecutablePath
            )
        }
        return true
    }

    private static func performCoordinatedRecovery(
        recoveryLock: RecoveryFileLock,
        parentPID: pid_t,
        supervisorProcessID: pid_t,
        supervisorExecutablePath: String,
        appPath: String
    ) {
        withExtendedLifetime(recoveryLock) {
            guard let sessionID = SupervisorRecoveryJournal.beginSession(
                parentPID: parentPID,
                coordinatorProcessID: supervisorProcessID,
                executablePath: supervisorExecutablePath
            ) else {
                SupervisorRecoveryJournal.markFailed(
                    parentPID: parentPID,
                    supervisorProcessID: supervisorProcessID,
                    executablePath: supervisorExecutablePath
                )
                return
            }
            let succeeded = relaunchApplication(atPath: appPath)
            SupervisorRecoveryJournal.finishSession(
                parentPID: parentPID,
                sessionID: sessionID,
                coordinatorProcessID: supervisorProcessID,
                executablePath: supervisorExecutablePath,
                succeeded: succeeded
            )
            if !SleepOverrideWatchdog.hasRecovery(parentPID: parentPID) {
                SupervisorRecoveryJournal.clearSupervisor(parentPID: parentPID)
            }
        }
    }

    private static func waitForRecoveryCoordinator(timeout: TimeInterval) -> RecoveryFileLock? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch RecoveryCoordinator.acquire() {
            case .acquired(let lock):
                return lock
            case .busy:
                Thread.sleep(forTimeInterval: 0.05)
            case .failed(let detail):
                AppLog.write("recovery coordinator takeover failed: \(detail)")
                return nil
            }
        }
        return nil
    }

    private static func waitForParent(_ parentPID: pid_t) -> ParentState {
        while getppid() == parentPID {
            switch nextHeartbeatEvent(timeoutMilliseconds: heartbeatTimeoutMilliseconds) {
            case .heartbeat, .retry:
                continue
            case .shutdown:
                return .cleanShutdown
            case .exited:
                return .exited
            case .failed:
                return .unresponsive
            case .timedOut:
                AppLog.write("app supervisor heartbeat delayed; starting wake grace period")
                switch nextHeartbeatEvent(timeoutMilliseconds: wakeGraceMilliseconds) {
                case .heartbeat, .retry:
                    continue
                case .shutdown:
                    return .cleanShutdown
                case .exited:
                    return .exited
                case .timedOut, .failed:
                    return .unresponsive
                }
            }
        }
        return .exited
    }

    private static func nextHeartbeatEvent(timeoutMilliseconds: Int32) -> HeartbeatEvent {
        var descriptor = pollfd(
            fd: STDIN_FILENO,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )
        let result = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
        if result == 0 { return .timedOut }
        if result < 0 { return errno == EINTR ? .retry : .failed }

        if descriptor.revents & Int16(POLLIN) != 0 {
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(STDIN_FILENO, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                if buffer.prefix(count).contains(shutdownByte) {
                    return .shutdown
                }
                return .heartbeat
            }
            if count == 0 { return .exited }
            return errno == EINTR ? .retry : .failed
        }
        if descriptor.revents & Int16(POLLHUP | POLLERR) != 0 {
            return .exited
        }
        return .retry
    }

    private static func terminateParent(_ parentPID: pid_t) {
        guard getppid() == parentPID else { return }
        _ = kill(parentPID, SIGTERM)
        let deadline = Date().addingTimeInterval(3)
        while getppid() == parentPID, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if getppid() == parentPID {
            _ = kill(parentPID, SIGKILL)
        }
    }

    private static func relaunchApplication(atPath appPath: String) -> Bool {
        guard let expectedExecutablePath = applicationExecutablePath(atPath: appPath) else {
            AppLog.write("app supervisor could not resolve the application executable")
            return false
        }

        for _ in 0..<CrashRecoveryLimiter.maximumAttempts {
            guard CrashRecoveryLimiter.shouldAttemptRestart() else {
                AppLog.write("app supervisor stopped automatic restart after repeated failures")
                return false
            }

            let token = UUID()
            AppRecoveryHandshake.cleanup(token: token)
            do {
                let result = try ProcessRunner.run(
                    executable: "/usr/bin/open",
                    arguments: [
                        "-n",
                        appPath,
                        "--args",
                        recoveredLaunchArgument,
                        AppRecoveryHandshake.tokenArgument,
                        token.uuidString
                    ],
                    timeout: 10
                )
                guard result.terminationStatus == 0 else {
                    AppLog.write("app supervisor relaunch exited with status \(result.terminationStatus)")
                    AppRecoveryHandshake.cleanup(token: token)
                    continue
                }

                guard let processID = waitForRecoveredProcess(
                    token: token,
                    expectedExecutablePath: expectedExecutablePath,
                    timeout: 10
                ) else {
                    AppLog.write("app supervisor did not observe the recovered process start")
                    AppRecoveryHandshake.cleanup(token: token)
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                if waitForRecoveredProcessReady(
                    token: token,
                    processID: processID,
                    expectedExecutablePath: expectedExecutablePath,
                    timeout: 30
                ) {
                    AppLog.write("app supervisor confirmed application recovery: \(processID)")
                    AppRecoveryHandshake.cleanup(token: token)
                    return true
                }

                if AppRecoveryHandshake.isCancelled(token: token, processID: processID) {
                    AppLog.write("app supervisor stopped recovery after a clean recovered-app exit")
                    AppRecoveryHandshake.cleanup(token: token)
                    return false
                }

                AppLog.write("app supervisor recovered process did not become ready: \(processID)")
                ProcessIdentity.terminateImmediately(
                    processID: processID,
                    executablePath: expectedExecutablePath
                )
                AppRecoveryHandshake.cleanup(token: token)
                Thread.sleep(forTimeInterval: 1)
            } catch {
                AppLog.write("app supervisor relaunch failed: \(error.localizedDescription)")
                AppRecoveryHandshake.cleanup(token: token)
            }
        }
        return false
    }

    static func applicationExecutablePath(atPath appPath: String) -> String? {
        guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
              let executableName = bundle.object(
                  forInfoDictionaryKey: kCFBundleExecutableKey as String
              ) as? String,
              !executableName.isEmpty,
              !executableName.contains("/") else {
            return nil
        }
        return bundle.bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
            .path
    }

    private static func waitForRecoveredProcess(
        token: UUID,
        expectedExecutablePath: String,
        timeout: TimeInterval
    ) -> pid_t? {
        let deadline = Date().addingTimeInterval(timeout)
        var rejectedProcessID: pid_t?
        while Date() < deadline {
            if let processID = AppRecoveryHandshake.startedProcessID(for: token) {
                if ProcessIdentity.matches(
                    processID: processID,
                    executablePath: expectedExecutablePath
                ) {
                    return processID
                }
                if rejectedProcessID != processID {
                    rejectedProcessID = processID
                    let actualPath = ProcessIdentity.executablePath(processID: processID) ?? "not running"
                    AppLog.write(
                        "app supervisor rejected recovered process \(processID); expected: \(expectedExecutablePath); actual: \(actualPath)"
                    )
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private static func waitForRecoveredProcessReady(
        token: UUID,
        processID: pid_t,
        expectedExecutablePath: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard ProcessIdentity.matches(
                processID: processID,
                executablePath: expectedExecutablePath
            ) else {
                return false
            }
            if AppRecoveryHandshake.isReady(token: token, processID: processID) {
                return true
            }
            if AppRecoveryHandshake.isCancelled(token: token, processID: processID) {
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}

enum CrashRecoveryLimiter {
    static let maximumAttempts = 3
    static let attemptWindow: TimeInterval = 10 * 60

    static func shouldAttemptRestart(
        now: Date = Date(),
        historyURL: URL = defaultHistoryURL
    ) -> Bool {
        let acquisition = RecoveryFileLock.acquire(
            at: historyURL.appendingPathExtension("lock"),
            nonBlocking: false
        )
        guard case .acquired(let lock) = acquisition else {
            AppLog.write("crash recovery limiter could not acquire its lock")
            return false
        }
        return withExtendedLifetime(lock) {
            var attempts = loadHistory(from: historyURL)
                .filter { now.timeIntervalSince1970 - $0 < attemptWindow }
            guard attempts.count < maximumAttempts else {
                _ = saveHistory(attempts, to: historyURL)
                return false
            }
            attempts.append(now.timeIntervalSince1970)
            return saveHistory(attempts, to: historyURL)
        }
    }

    static func reset(historyURL: URL = defaultHistoryURL) {
        let acquisition = RecoveryFileLock.acquire(
            at: historyURL.appendingPathExtension("lock"),
            nonBlocking: false
        )
        guard case .acquired(let lock) = acquisition else {
            AppLog.write("crash recovery limiter reset could not acquire its lock")
            return
        }
        withExtendedLifetime(lock) {
            try? FileManager.default.removeItem(at: historyURL)
        }
    }

    static var defaultHistoryURL: URL {
        RecoveryPaths.durableDirectoryURL
            .appendingPathComponent("com.local.lidwake.restart-history.json")
    }

    private static func loadHistory(from url: URL) -> [TimeInterval] {
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([TimeInterval].self, from: data) else {
            return []
        }
        return values
    }

    private static func saveHistory(_ attempts: [TimeInterval], to url: URL) -> Bool {
        do {
            try RecoveryPaths.ensureDirectory(url.deletingLastPathComponent())
            let data = try JSONEncoder().encode(attempts)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            AppLog.write("failed to save crash recovery history: \(error.localizedDescription)")
            return false
        }
    }
}

enum AppSupervisorError: LocalizedError {
    case helperUnavailable
    case recoveryJournalUnavailable

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "无法定位 \(Brand.appName) 监督进程。"
        case .recoveryJournalUnavailable:
            "无法创建 \(Brand.appName) 恢复协调状态。"
        }
    }
}
