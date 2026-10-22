import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let supervisor = AppSupervisorController()
    private var supervisorHeartbeatTimer: Timer?
    private var recoveryReadinessTask: Task<Void, Never>?
    private var recoveryHandshakePending = false
    private var didStartPrimaryInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.write("applicationDidFinishLaunching")
        guard SingleInstanceGuard.activate() else {
            AppLog.write("another instance is active; terminating")
            NSApplication.shared.terminate(nil)
            return
        }
        Storage.migrateLegacyPreferences()
        AppRecoveryHandshake.cleanupOrphanedArtifacts()
        if !CommandLine.arguments.contains(AppSupervisor.recoveredLaunchArgument) {
            CrashRecoveryLimiter.reset()
        }

        var supervisorStarted = false
        do {
            try supervisor.start()
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.supervisor.pulse()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            supervisorHeartbeatTimer = timer
            supervisorStarted = true
        } catch {
            AppLog.write("failed to start app supervisor: \(error.localizedDescription)")
        }

        NSApplication.shared.applicationIconImage = BrandImages.bundledAppIcon()
        let recoveredFromUnexpectedExit = CrashDiagnostics.shared.markLaunch()

        let appState = AppState.shared
        statusBarController = StatusBarController(appState: appState)
        appState.start()
        didStartPrimaryInstance = true
        if recoveredFromUnexpectedExit {
            appState.openSettings()
        }
        if CommandLine.arguments.contains(AppSupervisor.recoveredLaunchArgument) {
            recoveryHandshakePending = true
            if supervisorStarted {
                recoveryReadinessTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    defer { recoveryReadinessTask = nil }
                    guard await appState.waitForRecoveryReadiness() else {
                        AppLog.write("automatic recovery policy did not become ready")
                        return
                    }
                    guard AppRecoveryHandshake.signalReadyIfRequested(
                        arguments: CommandLine.arguments
                    ) else {
                        AppLog.write("automatic recovery failed to signal readiness")
                        return
                    }
                    recoveryHandshakePending = false
                    AppLog.write("automatic recovery application and policy are ready")
                }
            } else {
                AppLog.write("automatic recovery withheld readiness because its supervisor failed")
            }
        }
        AppLog.write("app started")
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard didStartPrimaryInstance else { return false }
        AppState.shared.openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.write("applicationWillTerminate")
        guard didStartPrimaryInstance else { return }
        if recoveryHandshakePending {
            _ = AppRecoveryHandshake.signalCancelledIfRequested(
                arguments: CommandLine.arguments
            )
            recoveryHandshakePending = false
        }
        recoveryReadinessTask?.cancel()
        recoveryReadinessTask = nil
        supervisorHeartbeatTimer?.invalidate()
        supervisorHeartbeatTimer = nil
        supervisor.stop()
        AppState.shared.shutdown()
        CrashDiagnostics.shared.markCleanExit()
    }
}
