import Combine
import Foundation
import Testing
@testable import Lidwake

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

struct InfrastructureTests {
    @Test func processRunnerCapturesOutput() throws {
        let result = try ProcessRunner.run(
            executable: "/bin/echo",
            arguments: ["lidwake"],
            timeout: 2
        )

        #expect(result.terminationStatus == 0)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "lidwake")
    }

    @Test func processRunnerTimesOutAndTerminatesCommand() {
        do {
            _ = try ProcessRunner.run(
                executable: "/bin/sleep",
                arguments: ["2"],
                timeout: 0.1
            )
            Issue.record("预期命令超时，但命令成功返回。")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else {
                Issue.record("预期 timedOut，实际为 \(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("预期 ProcessRunnerError，实际为 \(error)")
        }
    }

    @Test func processExitWaiterUsesProcessExitEvent() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.05"]
        try process.run()

        #expect(ProcessExitWaiter.wait(processID: process.processIdentifier))
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func recoveryFileLockDistinguishesBusyFromFailure() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-lock-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let lockURL = directoryURL.appendingPathComponent("recovery.lock")

        guard case .acquired(let firstLock) = RecoveryFileLock.acquire(
            at: lockURL,
            nonBlocking: true
        ) else {
            Issue.record("无法取得首个测试文件锁。")
            return
        }
        withExtendedLifetime(firstLock) {
            guard case .busy = RecoveryFileLock.acquire(at: lockURL, nonBlocking: true) else {
                Issue.record("第二次非阻塞加锁应返回 busy。")
                return
            }
        }

        let fileInsteadOfDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-lock-file-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fileInsteadOfDirectory) }
        try Data("not a directory".utf8).write(to: fileInsteadOfDirectory)
        guard case .failed = RecoveryFileLock.acquire(
            at: fileInsteadOfDirectory.appendingPathComponent("recovery.lock"),
            nonBlocking: true
        ) else {
            Issue.record("目录创建错误应返回 failed。")
            return
        }
    }

    @Test func singleInstanceProbeRecognizesHeldLock() {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-single-instance-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: lockURL) }

        #expect(!SingleInstanceGuard.isPrimaryInstanceActive(lockURL: lockURL))
        guard case .acquired(let lock) = RecoveryFileLock.acquire(
            at: lockURL,
            nonBlocking: true
        ) else {
            Issue.record("无法取得单实例测试锁。")
            return
        }
        withExtendedLifetime(lock) {
            #expect(SingleInstanceGuard.isPrimaryInstanceActive(lockURL: lockURL))
        }
    }

    @Test func bootResetPlistMatchesExpectedCommand() {
        let data = Data(AuthorizationArtifacts.bootResetPlist.utf8)
        #expect(AuthorizationArtifacts.bootResetPlistIsValid(data))
    }

    @Test func bootResetPlistRejectsUnexpectedCommand() {
        let invalid = AuthorizationArtifacts.bootResetPlist
            .replacingOccurrences(of: "<string>0</string>", with: "<string>1</string>")
        #expect(!AuthorizationArtifacts.bootResetPlistIsValid(Data(invalid.utf8)))
    }

    @Test func enablingRequiresCompleteAuthorizationProtection() {
        #expect(AuthorizationArtifacts.requiresInstallation(
            toEnable: true,
            artifactsInstalled: false
        ))
        #expect(!AuthorizationArtifacts.requiresInstallation(
            toEnable: false,
            artifactsInstalled: false
        ))
        #expect(!AuthorizationArtifacts.requiresInstallation(
            toEnable: true,
            artifactsInstalled: true
        ))
    }

    @Test func successfulRepairClearsFailedTarget() {
        var state = SleepOverrideFailureState()
        state.record(true)
        #expect(state.shouldShortCircuit(target: true, allowPrompt: false))

        state.clear()
        #expect(!state.shouldShortCircuit(target: true, allowPrompt: false))
    }

    @Test func authorizationValidationRequiresExpectedSourceAndNoAuthentication() {
        let valid = """
        Sudoers entry: /private/etc/sudoers.d/lidwake
            RunAsUsers: root
            Options: !authenticate
            Commands:
                /usr/bin/pmset -a disablesleep 0
            Matched: /usr/bin/pmset -a disablesleep 0
        """
        let wrongSource = """
        Sudoers entry: /etc/sudoers
            RunAsUsers: root
            Options: !authenticate
            Matched: /usr/bin/pmset -a disablesleep 0
        """
        let passwordRequired = """
        Sudoers entry: /private/etc/sudoers.d/lidwake
            RunAsUsers: root
            Matched: /usr/bin/pmset -a disablesleep 0
        """

        let command = "/usr/bin/pmset -a disablesleep 0"
        #expect(AuthorizationArtifacts.sudoLongListConfirmsExpectedRule(valid, command: command))
        #expect(!AuthorizationArtifacts.sudoLongListConfirmsExpectedRule(wrongSource, command: command))
        #expect(!AuthorizationArtifacts.sudoLongListConfirmsExpectedRule(passwordRequired, command: command))
    }

    @Test func privilegedRuleIsInstalledAfterBootRecoveryArtifact() {
        let commands = AuthorizationArtifacts.safeInstallationMoveCommands
        #expect(commands.count == 2)
        #expect(commands[0].contains(AuthorizationArtifacts.bootResetPlistPath))
        #expect(commands[1].contains(AuthorizationArtifacts.sudoersPath))
    }

    @Test func crashRecoveryLimiterStopsRestartLoops() {
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-restart-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(CrashRecoveryLimiter.shouldAttemptRestart(now: now, historyURL: historyURL))
        #expect(CrashRecoveryLimiter.shouldAttemptRestart(now: now, historyURL: historyURL))
        #expect(CrashRecoveryLimiter.shouldAttemptRestart(now: now, historyURL: historyURL))
        #expect(!CrashRecoveryLimiter.shouldAttemptRestart(now: now, historyURL: historyURL))
        #expect(CrashRecoveryLimiter.shouldAttemptRestart(
            now: now.addingTimeInterval(CrashRecoveryLimiter.attemptWindow + 1),
            historyURL: historyURL
        ))
    }

    @Test func crashRecoveryLimiterSerializesConcurrentAttempts() {
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-restart-concurrency-test-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.removeItem(at: historyURL.appendingPathExtension("lock"))
        }
        let successfulAttempts = ThreadSafeCounter()
        let now = Date(timeIntervalSince1970: 2_000)

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            if CrashRecoveryLimiter.shouldAttemptRestart(now: now, historyURL: historyURL) {
                successfulAttempts.increment()
            }
        }

        #expect(successfulAttempts.value == CrashRecoveryLimiter.maximumAttempts)
    }

    @Test func applicationRecoveryHandshakeRequiresTokenAndTracksReadiness() {
        let token = UUID()
        let arguments = [
            "Lidwake",
            AppSupervisor.recoveredLaunchArgument,
            AppRecoveryHandshake.tokenArgument,
            token.uuidString
        ]
        defer { AppRecoveryHandshake.cleanup(token: token) }

        #expect(AppRecoveryHandshake.token(from: ["Lidwake"]) == nil)
        #expect(AppRecoveryHandshake.signalStartedIfRequested(
            arguments: arguments,
            processID: 42_001
        ))
        #expect(AppRecoveryHandshake.startedProcessID(for: token) == 42_001)
        #expect(!AppRecoveryHandshake.isReady(token: token, processID: 42_001))
        #expect(AppRecoveryHandshake.signalReadyIfRequested(
            arguments: arguments,
            processID: 42_001
        ))
        #expect(AppRecoveryHandshake.isReady(token: token, processID: 42_001))
        #expect(AppRecoveryHandshake.signalCancelledIfRequested(
            arguments: arguments,
            processID: 42_001
        ))
        #expect(AppRecoveryHandshake.isCancelled(token: token, processID: 42_001))
    }

    @Test func applicationRecoveryHandshakeRemovesOnlyOrphanedArtifacts() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-handshake-cleanup-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try RecoveryPaths.ensureDirectory(directoryURL)

        let orphanedToken = UUID().uuidString.lowercased()
        let liveToken = UUID().uuidString.lowercased()
        let unrelatedURL = directoryURL.appendingPathComponent("app-not-a-token.cancelled")
        try Data(String(Int32.max).utf8).write(
            to: directoryURL.appendingPathComponent("app-\(orphanedToken).cancelled")
        )
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(
            to: directoryURL.appendingPathComponent("app-\(liveToken).started")
        )
        try Data("keep".utf8).write(to: unrelatedURL)

        AppRecoveryHandshake.cleanupOrphanedArtifacts(directoryURL: directoryURL)

        #expect(!FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("app-\(orphanedToken).cancelled").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("app-\(liveToken).started").path
        ))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    @Test func processIdentityMatchesCurrentExecutable() throws {
        let processID = ProcessInfo.processInfo.processIdentifier
        let executablePath = try #require(ProcessIdentity.executablePath(processID: processID))

        #expect(!executablePath.contains("\0"))
        #expect(ProcessIdentity.matches(
            processID: processID,
            executablePath: executablePath
        ))
    }

    @Test func supervisorRecoveryJournalCompletesSuccessfulHandoff() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-recovery-journal-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let parentPID: pid_t = 42_002
        let processID = ProcessInfo.processInfo.processIdentifier
        let executablePath = try #require(ProcessIdentity.executablePath(processID: processID))

        #expect(SupervisorRecoveryJournal.register(
            parentPID: parentPID,
            supervisorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        ))
        let sessionID = try #require(SupervisorRecoveryJournal.beginSession(
            parentPID: parentPID,
            coordinatorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        ))
        #expect(SupervisorRecoveryJournal.currentSessionState(
            directoryURL: directoryURL
        ) == .recovering)
        SupervisorRecoveryJournal.finishSession(
            parentPID: parentPID,
            sessionID: sessionID,
            coordinatorProcessID: processID,
            executablePath: executablePath,
            succeeded: true,
            directoryURL: directoryURL
        )
        #expect(SupervisorRecoveryJournal.currentSessionState(
            directoryURL: directoryURL
        ) == .succeeded)

        #expect(SupervisorRecoveryJournal.waitForSuccessfulHandoff(
            parentPID: parentPID,
            timeout: 0.1,
            directoryURL: directoryURL
        ))
    }

    @Test func supervisorRecoveryJournalRejectsFailedHandoff() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-recovery-failure-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let parentPID: pid_t = 42_003
        let processID = ProcessInfo.processInfo.processIdentifier
        let executablePath = try #require(ProcessIdentity.executablePath(processID: processID))
        let sessionID = try #require(SupervisorRecoveryJournal.beginSession(
            parentPID: parentPID,
            coordinatorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        ))
        SupervisorRecoveryJournal.finishSession(
            parentPID: parentPID,
            sessionID: sessionID,
            coordinatorProcessID: processID,
            executablePath: executablePath,
            succeeded: false,
            directoryURL: directoryURL
        )

        #expect(!SupervisorRecoveryJournal.waitForSuccessfulHandoff(
            parentPID: parentPID,
            timeout: 0.1,
            directoryURL: directoryURL
        ))
    }

    @Test func supervisorRecoveryJournalPersistsCleanShutdownIntent() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-recovery-stop-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let parentPID: pid_t = 42_006
        let processID = ProcessInfo.processInfo.processIdentifier
        let executablePath = try #require(ProcessIdentity.executablePath(processID: processID))

        SupervisorRecoveryJournal.markStopped(
            parentPID: parentPID,
            supervisorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        )
        #expect(SupervisorRecoveryJournal.isStopped(
            parentPID: parentPID,
            supervisorProcessID: processID,
            directoryURL: directoryURL
        ))
        #expect(!SupervisorRecoveryJournal.isStopped(
            parentPID: parentPID,
            supervisorProcessID: processID + 1,
            directoryURL: directoryURL
        ))
    }

    @Test func supervisorRecoveryJournalDelegatesIntermediateCrash() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-recovery-delegation-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let originalParentPID: pid_t = 42_004
        let intermediateParentPID: pid_t = 42_005
        let terminalRaceParentPID: pid_t = 42_007
        let processID = ProcessInfo.processInfo.processIdentifier
        let executablePath = try #require(ProcessIdentity.executablePath(processID: processID))
        let sessionID = try #require(SupervisorRecoveryJournal.beginSession(
            parentPID: originalParentPID,
            coordinatorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        ))
        #expect(SupervisorRecoveryJournal.delegateToActiveSession(
            parentPID: intermediateParentPID,
            supervisorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        ))
        SupervisorRecoveryJournal.finishSession(
            parentPID: originalParentPID,
            sessionID: sessionID,
            coordinatorProcessID: processID,
            executablePath: executablePath,
            succeeded: true,
            directoryURL: directoryURL
        )
        #expect(SupervisorRecoveryJournal.delegateToActiveSession(
            parentPID: terminalRaceParentPID,
            supervisorProcessID: processID,
            executablePath: executablePath,
            directoryURL: directoryURL
        ))

        #expect(SupervisorRecoveryJournal.waitForSuccessfulHandoff(
            parentPID: intermediateParentPID,
            timeout: 0.1,
            directoryURL: directoryURL
        ))
        #expect(SupervisorRecoveryJournal.waitForSuccessfulHandoff(
            parentPID: terminalRaceParentPID,
            timeout: 0.1,
            directoryURL: directoryURL
        ))
    }

    @Test func recoveryReadinessRequiresPolicyAndSupervisorWorkToFinish() {
        #expect(!RecoveryReadinessPolicy.isReady(
            workerRunning: true,
            requestPending: true,
            shouldEnableOverride: true,
            overrideActive: true,
            managedByLidwake: true,
            phase: .enabled
        ))
        #expect(!RecoveryReadinessPolicy.isReady(
            workerRunning: false,
            requestPending: false,
            shouldEnableOverride: true,
            overrideActive: true,
            managedByLidwake: false,
            phase: .failed
        ))
        #expect(RecoveryReadinessPolicy.isReady(
            workerRunning: false,
            requestPending: false,
            shouldEnableOverride: true,
            overrideActive: true,
            managedByLidwake: true,
            phase: .enabled
        ))
        #expect(RecoveryReadinessPolicy.isReady(
            workerRunning: false,
            requestPending: false,
            shouldEnableOverride: false,
            overrideActive: false,
            managedByLidwake: false,
            phase: .idle
        ))
    }

    @Test @MainActor func backgroundNotificationsAreDeliveredOnMainQueue() async {
        let center = NotificationCenter()
        let name = Notification.Name("lidwake-main-queue-test-\(UUID().uuidString)")
        var cancellable: AnyCancellable?

        await confirmation("通知已切换到主队列") { confirm in
            cancellable = MainQueueNotificationPublisher.publisher(center: center, name: name)
                .sink { _ in
                    #expect(Thread.isMainThread)
                    confirm()
                }
            await Task.detached {
                center.post(name: name, object: nil)
            }.value
            try? await Task.sleep(for: .milliseconds(100))
        }
        withExtendedLifetime(cancellable) {}
    }

    @Test func supervisorRejectsMalformedLaunchArguments() {
        #expect(!AppSupervisor.runIfRequested(arguments: ["AwakeWatchdog"]))
        #expect(!AppSupervisor.runIfRequested(arguments: [
            "AwakeWatchdog",
            AppSupervisor.argument,
            "1",
            "/Applications/醒咖 Awake.app"
        ]))
    }

    @Test func supervisorResolvesTheInfoPlistMainExecutable() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-bundle-test-\(UUID().uuidString).app")
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let executableURL = contentsURL
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Awake")
        defer { try? FileManager.default.removeItem(at: appURL) }
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.local.awake.bundle-test",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Awake"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))

        #expect(AppSupervisor.applicationExecutablePath(atPath: appURL.path) == executableURL.path)
    }

    @Test func repeatedRequestReusesExistingWorker() {
        #expect(!SleepOverrideRequestPolicy.shouldRestartWorker(
            workerExists: true,
            existingTarget: true,
            existingAllowPrompt: false,
            newTarget: true,
            newAllowPrompt: false
        ))
    }

    @Test func disablingForcedClosedLidModeWinsOverPresentationMode() {
        #expect(SleepOverrideRequestPolicy.target(
            forceClosedLidWake: true,
            mode: .presentation
        ))
        #expect(!SleepOverrideRequestPolicy.target(
            forceClosedLidWake: false,
            mode: .presentation
        ))
        #expect(!SleepOverrideRequestPolicy.target(
            forceClosedLidWake: true,
            mode: .off
        ))
    }

    @Test func changedTargetRestartsWorker() {
        #expect(SleepOverrideRequestPolicy.shouldRestartWorker(
            workerExists: true,
            existingTarget: true,
            existingAllowPrompt: false,
            newTarget: false,
            newAllowPrompt: false
        ))
    }

    @Test func promptEscalationRestartsWorkerAndIsPreserved() {
        #expect(SleepOverrideRequestPolicy.shouldRestartWorker(
            workerExists: true,
            existingTarget: true,
            existingAllowPrompt: false,
            newTarget: true,
            newAllowPrompt: true
        ))
        #expect(SleepOverrideRequestPolicy.mergedAllowPrompt(
            existingTarget: true,
            existingAllowPrompt: true,
            newTarget: true,
            newAllowPrompt: false
        ))
    }

    @Test func cooldownOnlySkipsMatchingNonInteractiveRequest() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let recently = now.addingTimeInterval(-0.5)

        #expect(SleepOverrideRequestPolicy.shouldSkip(
            hasPendingRequest: false,
            lastTarget: true,
            newTarget: true,
            allowPrompt: false,
            lastSyncDate: recently,
            now: now
        ))
        #expect(!SleepOverrideRequestPolicy.shouldSkip(
            hasPendingRequest: false,
            lastTarget: true,
            newTarget: false,
            allowPrompt: false,
            lastSyncDate: recently,
            now: now
        ))
        #expect(!SleepOverrideRequestPolicy.shouldSkip(
            hasPendingRequest: false,
            lastTarget: true,
            newTarget: true,
            allowPrompt: true,
            lastSyncDate: recently,
            now: now
        ))
        #expect(!SleepOverrideRequestPolicy.shouldSkip(
            hasPendingRequest: false,
            lastTarget: true,
            newTarget: true,
            allowPrompt: false,
            lastSyncDate: now.addingTimeInterval(
                -SleepOverrideRequestPolicy.minimumResyncInterval - 1
            ),
            now: now
        ))
    }
}
