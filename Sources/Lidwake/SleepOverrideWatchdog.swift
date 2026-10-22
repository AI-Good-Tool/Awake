import Darwin
import Foundation

enum SleepOverrideWatchdog {
    static let argument = "--sleep-override-watchdog"
    private static let maximumRestoreAttempts = 5

    enum RecoveryState: String, Codable {
        case pending
        case running
    }

    struct RecoveryRecord: Codable, Equatable {
        var state: RecoveryState
        var watchdogProcessID: pid_t?
        var executablePath: String
    }

    static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.count == 3,
              arguments[1] == argument,
              let parentPID = pid_t(arguments[2]),
              parentPID > 1 else {
            return false
        }

        markRecoveryRunning(
            parentPID: parentPID,
            watchdogProcessID: ProcessInfo.processInfo.processIdentifier,
            executablePath: ProcessIdentity.executablePath(
                processID: ProcessInfo.processInfo.processIdentifier
            )
        )
        waitForParentExit(parentPID)
        if SupervisorRecoveryJournal.waitForSuccessfulHandoff(parentPID: parentPID),
           waitForStablePrimaryInstance() {
            AppLog.write("system sleep watchdog confirmed policy handoff to recovered application")
        } else {
            _ = restoreSystemSleep()
        }
        clearRecovery(parentPID: parentPID)
        SupervisorRecoveryJournal.clearSupervisor(parentPID: parentPID)
        return true
    }

    static func prepareRecovery(
        parentPID: pid_t,
        executablePath: String,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) throws {
        try RecoveryPaths.ensureDirectory(directoryURL)
        let record = RecoveryRecord(
            state: .pending,
            watchdogProcessID: nil,
            executablePath: executablePath
        )
        try writeRecoveryRecord(record, parentPID: parentPID, directoryURL: directoryURL)
    }

    static func clearRecovery(
        parentPID: pid_t,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) {
        try? FileManager.default.removeItem(
            at: recoveryURL(parentPID: parentPID, directoryURL: directoryURL)
        )
    }

    static func hasRecovery(
        parentPID: pid_t,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> Bool {
        FileManager.default.fileExists(
            atPath: recoveryURL(parentPID: parentPID, directoryURL: directoryURL).path
        )
    }

    private static func waitForParentExit(_ parentPID: pid_t) {
        guard getppid() == parentPID,
              ProcessIdentity.isRunning(processID: parentPID) else {
            return
        }
        if !ProcessExitWaiter.wait(processID: parentPID) {
            waitForParentExitByPolling(parentPID)
        }
    }

    private static func waitForParentExitByPolling(_ parentPID: pid_t) {
        while getppid() == parentPID,
              ProcessIdentity.isRunning(processID: parentPID) {
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private static func waitForStablePrimaryInstance(timeout: TimeInterval = 3 * 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var terminalWithoutPrimarySince: Date?
        while Date() < deadline {
            let sessionState = SupervisorRecoveryJournal.currentSessionState()
            let primaryActive = SingleInstanceGuard.isPrimaryInstanceActive()
            if primaryActive, sessionState != .recovering {
                return true
            }
            if sessionState == .failed, !primaryActive {
                return false
            }
            if sessionState == .succeeded, !primaryActive {
                if let terminalWithoutPrimarySince,
                   Date().timeIntervalSince(terminalWithoutPrimarySince) >= 10 {
                    return false
                }
                terminalWithoutPrimarySince = terminalWithoutPrimarySince ?? Date()
            } else {
                terminalWithoutPrimarySince = nil
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    @discardableResult
    static func restoreSystemSleep() -> Bool {
        for attempt in 1...maximumRestoreAttempts {
            let exitStatus = restoreSystemSleepOnce()
            let state = SystemSleepOverrideController.readSystemDisableSleepState()
            if exitStatus == 0, state == .disabled {
                AppLog.write("system sleep watchdog restore succeeded on attempt \(attempt)")
                return true
            }

            AppLog.write(
                "system sleep watchdog restore attempt \(attempt) failed; exit: \(exitStatus.map(String.init) ?? "not started"); state: \(state)"
            )
            if attempt < maximumRestoreAttempts {
                Thread.sleep(forTimeInterval: retryDelay(after: attempt))
            }
        }

        AppLog.write("CRITICAL: system sleep watchdog exhausted restore attempts")
        return false
    }

    static func retryDelay(after attempt: Int) -> TimeInterval {
        min(pow(2, Double(max(0, attempt - 1))), 8)
    }

    private static func restoreSystemSleepOnce() -> Int32? {
        do {
            let result = try ProcessRunner.run(
                executable: "/usr/bin/sudo",
                arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"],
                timeout: 10
            )
            return result.terminationStatus
        } catch {
            AppLog.write("system sleep watchdog restore failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func markRecoveryRunning(
        parentPID: pid_t,
        watchdogProcessID: pid_t,
        executablePath: String?
    ) {
        let existingRecord = readRecoveryRecord(parentPID: parentPID)
        let record = RecoveryRecord(
            state: .running,
            watchdogProcessID: watchdogProcessID,
            executablePath: existingRecord?.executablePath ?? executablePath ?? ""
        )
        try? writeRecoveryRecord(record, parentPID: parentPID)
    }

    private static func recoveryURL(parentPID: pid_t, directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("sleep-watchdog-\(parentPID).json")
    }

    private static func readRecoveryRecord(
        parentPID: pid_t,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) -> RecoveryRecord? {
        let url = recoveryURL(parentPID: parentPID, directoryURL: directoryURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecoveryRecord.self, from: data)
    }

    private static func writeRecoveryRecord(
        _ record: RecoveryRecord,
        parentPID: pid_t,
        directoryURL: URL = RecoveryPaths.transientDirectoryURL
    ) throws {
        try RecoveryPaths.ensureDirectory(directoryURL)
        let data = try JSONEncoder().encode(record)
        try data.write(
            to: recoveryURL(parentPID: parentPID, directoryURL: directoryURL),
            options: [.atomic]
        )
    }
}
