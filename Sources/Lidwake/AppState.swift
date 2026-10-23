import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var manualMode: KeepAwakeMode {
        didSet { persistAndEvaluate(resumeIfPaused: true) }
    }
    @Published var scheduleEnabled: Bool {
        didSet { persistAndEvaluate() }
    }
    @Published var schedules: [ScheduleRule] {
        didSet { persistAndEvaluate() }
    }
    @Published var whitelistEnabled: Bool {
        didSet { persistAndEvaluate() }
    }
    @Published var whitelistMode: KeepAwakeMode {
        didSet { persistAndEvaluate() }
    }
    @Published var whitelist: [WhitelistedApp] {
        didSet { persistAndEvaluate() }
    }
    @Published var lowBatteryProtection: Bool {
        didSet { persistAndEvaluate() }
    }
    @Published var lowBatteryThreshold: Int {
        didSet { persistAndEvaluate() }
    }
    @Published var thermalProtection: Bool {
        didSet { persistAndEvaluate() }
    }
    @Published var forceClosedLidWake: Bool {
        didSet { persistAndEvaluate(allowSystemSleepPrompt: oldValue != forceClosedLidWake) }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle) }
    }
    @Published var menuBarIconUsesActiveColor: Bool {
        didSet { persistAndEvaluate() }
    }
    @Published var menuBarIconColorHex: String {
        didSet { persistAndEvaluate() }
    }
    @Published var launchAtLogin: Bool {
        didSet { configureLaunchAtLogin() }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }
    @Published private(set) var status = RuntimeStatus()
    @Published private(set) var lastDiagnosticsURL: URL?
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var systemSleepOverrideActive = false
    @Published private(set) var systemSleepOverrideManagedByLidwake = false
    @Published private(set) var systemSleepAuthorizationInstalled = false
    @Published private(set) var systemSleepOverrideError: String?
    @Published private(set) var systemSleepOverridePhase: SystemSleepOverridePhase = .idle
    @Published private(set) var quickPaused: Bool

    private let assertions = PowerAssertionController()
    private let systemSleepOverride = SystemSleepOverrideController()
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var isRestoring = true
    private var lastNonOffManualMode: KeepAwakeMode
    private var sleepOverrideTask: Task<Void, Never>?
    private var pendingSleepOverrideRequest: SleepOverrideRequest?
    private var sleepOverrideWorkerID = 0
    private var lastSleepOverrideTarget: Bool?
    private var lastSleepOverrideSyncDate: Date?
    private var lastExternalActiveApplication: ActiveApplication?

    private var ownBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? Brand.bundleIdentifier
    }

    var statusSymbol: String {
        switch status.effectiveMode {
        case .off:
            "moon.zzz"
        case .keepDisplayOn:
            "display"
        case .keepSystemAwake:
            "bolt.horizontal"
        case .presentation:
            "play.rectangle"
        }
    }

    private init() {
        manualMode = Storage.load(KeepAwakeMode.self, key: Keys.manualMode, fallback: .off)
        scheduleEnabled = UserDefaults.standard.bool(forKey: Keys.scheduleEnabled)
        schedules = Storage.load([ScheduleRule].self, key: Keys.schedules, fallback: [.workdayDefault])
        whitelistEnabled = UserDefaults.standard.bool(forKey: Keys.whitelistEnabled)
        whitelistMode = Storage.load(KeepAwakeMode.self, key: Keys.whitelistMode, fallback: .keepDisplayOn)
        whitelist = Storage.load([WhitelistedApp].self, key: Keys.whitelist, fallback: [])
        lowBatteryProtection = UserDefaults.standard.object(forKey: Keys.lowBatteryProtection) as? Bool ?? true
        lowBatteryThreshold = UserDefaults.standard.object(forKey: Keys.lowBatteryThreshold) as? Int ?? 20
        thermalProtection = UserDefaults.standard.object(forKey: Keys.thermalProtection) as? Bool ?? true
        forceClosedLidWake = UserDefaults.standard.object(forKey: Keys.forceClosedLidWake) as? Bool ?? false
        menuBarIconStyle = .restored(from: UserDefaults.standard.string(forKey: Keys.menuBarIconStyle))
        menuBarIconUsesActiveColor = UserDefaults.standard.object(forKey: Keys.menuBarIconUsesActiveColor) as? Bool ?? true
        menuBarIconColorHex = Brand.restoredActiveColorHex(from: UserDefaults.standard.string(forKey: Keys.menuBarIconColorHex))
        lastNonOffManualMode = Storage.load(KeepAwakeMode.self, key: Keys.lastNonOffManualMode, fallback: .keepDisplayOn)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        quickPaused = UserDefaults.standard.bool(forKey: Keys.quickPaused)
        systemSleepOverrideActive = systemSleepOverride.isApplied
        systemSleepOverrideManagedByLidwake = systemSleepOverride.isManagedByLidwake
        systemSleepAuthorizationInstalled = systemSleepOverride.isAuthorizationRuleInstalled
        systemSleepOverridePhase = systemSleepOverrideManagedByLidwake ? .enabled : .idle
        isRestoring = false
    }

    func start() {
        evaluateNow()
        observeSystemChanges()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateNow()
            }
        }

        if !hasCompletedOnboarding {
            OnboardingWindowPresenter.shared.show()
        }
    }

    func shutdown() {
        timer?.invalidate()
        cancellables.removeAll()
        sleepOverrideTask?.cancel()
        sleepOverrideTask = nil
        pendingSleepOverrideRequest = nil
        sleepOverrideWorkerID += 1
        assertions.releaseAll()
        let result = systemSleepOverride.setEnabledForShutdown(false, allowPrompt: false)
        if let error = result.errorMessage {
            AppLog.write("failed to restore system sleep override on shutdown: \(error)")
        }
    }

    func evaluateNow() {
        evaluateNow(allowSystemSleepPrompt: false)
    }

    func openSettings() {
        SettingsWindowPresenter.shared.show()
    }

    func waitForRecoveryReadiness(timeout: TimeInterval = 25) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if recoveryPolicyIsReady {
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return recoveryPolicyIsReady
    }

    private var recoveryPolicyIsReady: Bool {
        let shouldEnable = SleepOverrideRequestPolicy.target(
            forceClosedLidWake: forceClosedLidWake,
            mode: status.effectiveMode
        )
        return RecoveryReadinessPolicy.isReady(
            workerRunning: sleepOverrideTask != nil,
            requestPending: pendingSleepOverrideRequest != nil,
            shouldEnableOverride: shouldEnable,
            overrideActive: systemSleepOverrideActive,
            managedByLidwake: systemSleepOverrideManagedByLidwake,
            phase: systemSleepOverridePhase
        )
    }

    func toggleModeFromStatusItem() {
        if quickPaused {
            quickPaused = false
            UserDefaults.standard.set(false, forKey: Keys.quickPaused)
            evaluateNow()
        } else if status.effectiveMode == .off {
            manualMode = lastNonOffManualMode == .off ? .keepDisplayOn : lastNonOffManualMode
        } else {
            lastNonOffManualMode = status.effectiveMode
            Storage.save(lastNonOffManualMode, key: Keys.lastNonOffManualMode)
            quickPaused = true
            UserDefaults.standard.set(true, forKey: Keys.quickPaused)
            evaluateNow()
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        OnboardingWindowPresenter.shared.close()
        openSettings()
    }

    func addFrontmostAppToWhitelist() {
        let app = externalApplication(from: NSWorkspace.shared.frontmostApplication)
            ?? validatedLastExternalApplication()
        guard let app else {
            return
        }

        let item = WhitelistedApp(
            displayName: app.displayName,
            bundleIdentifier: app.bundleIdentifier
        )

        guard !whitelist.contains(where: { $0.bundleIdentifier == item.bundleIdentifier }) else {
            return
        }

        whitelist.append(item)
    }

    func addWhitelistApp(displayName: String, bundleIdentifier: String) {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundleID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBundleID.isEmpty else { return }

        let item = WhitelistedApp(
            displayName: cleanName.isEmpty ? cleanBundleID : cleanName,
            bundleIdentifier: cleanBundleID
        )

        guard !whitelist.contains(where: { $0.bundleIdentifier == item.bundleIdentifier }) else {
            return
        }

        whitelist.append(item)
    }

    func removeWhitelistItems(at offsets: IndexSet) {
        whitelist.remove(atOffsets: offsets)
    }

    func removeWhitelistItem(_ item: WhitelistedApp) {
        whitelist.removeAll { $0.id == item.id }
    }

    func addSchedule() {
        schedules.append(
            ScheduleRule(
                name: "新规则",
                days: [2, 3, 4, 5, 6],
                startMinute: 9 * 60,
                endMinute: 18 * 60,
                mode: .keepDisplayOn,
                isEnabled: true
            )
        )
    }

    func removeSchedules(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
    }

    func exportDiagnostics() {
        lastDiagnosticsURL = CrashDiagnostics.shared.export(status: status)
    }

    func clearDiagnostics() {
        CrashDiagnostics.shared.clearRecords()
        lastDiagnosticsURL = nil
    }

    func removeSystemSleepAuthorization() {
        systemSleepOverridePhase = .disabling
        Task { @MainActor in
            let result = await systemSleepOverride.removeAuthorizationRule(allowPrompt: true)
            systemSleepOverrideActive = result.active
            systemSleepOverrideManagedByLidwake = result.managedByLidwake
            systemSleepAuthorizationInstalled = systemSleepOverride.isAuthorizationRuleInstalled
            systemSleepOverrideError = result.errorMessage
            systemSleepOverridePhase = result.errorMessage == nil ? .idle : .failed
            guard result.errorMessage == nil else { return }

            isRestoring = true
            forceClosedLidWake = false
            isRestoring = false
            UserDefaults.standard.set(false, forKey: Keys.forceClosedLidWake)
            evaluateNow()
        }
    }

    func repairSystemSleepAuthorization() {
        Task { @MainActor in
            let result = await systemSleepOverride.repairAuthorizationArtifacts()
            systemSleepAuthorizationInstalled = systemSleepOverride.isAuthorizationRuleInstalled
            systemSleepOverrideError = result.errorMessage
            if result.errorMessage != nil {
                systemSleepOverridePhase = .failed
            } else {
                evaluateNow()
            }
        }
    }

    private func persistAndEvaluate(
        allowSystemSleepPrompt: Bool = false,
        resumeIfPaused: Bool = false
    ) {
        guard !isRestoring else { return }
        if resumeIfPaused {
            quickPaused = false
            UserDefaults.standard.set(false, forKey: Keys.quickPaused)
        }
        if manualMode != .off {
            lastNonOffManualMode = manualMode
            Storage.save(lastNonOffManualMode, key: Keys.lastNonOffManualMode)
        }
        Storage.save(manualMode, key: Keys.manualMode)
        UserDefaults.standard.set(scheduleEnabled, forKey: Keys.scheduleEnabled)
        Storage.save(schedules, key: Keys.schedules)
        UserDefaults.standard.set(whitelistEnabled, forKey: Keys.whitelistEnabled)
        Storage.save(whitelistMode, key: Keys.whitelistMode)
        Storage.save(whitelist, key: Keys.whitelist)
        UserDefaults.standard.set(lowBatteryProtection, forKey: Keys.lowBatteryProtection)
        UserDefaults.standard.set(lowBatteryThreshold, forKey: Keys.lowBatteryThreshold)
        UserDefaults.standard.set(thermalProtection, forKey: Keys.thermalProtection)
        UserDefaults.standard.set(forceClosedLidWake, forKey: Keys.forceClosedLidWake)
        UserDefaults.standard.set(menuBarIconUsesActiveColor, forKey: Keys.menuBarIconUsesActiveColor)
        UserDefaults.standard.set(menuBarIconColorHex, forKey: Keys.menuBarIconColorHex)
        evaluateNow(allowSystemSleepPrompt: allowSystemSleepPrompt)
    }

    private func evaluateNow(
        allowSystemSleepPrompt: Bool,
        forceSystemSleepSync: Bool = false
    ) {
        let context = currentPolicyContext()
        let decision = PolicyEngine.evaluate(
            manualMode: manualMode,
            scheduleEnabled: scheduleEnabled,
            schedules: schedules,
            whitelistEnabled: whitelistEnabled,
            whitelist: whitelist,
            whitelistMode: whitelistMode,
            lowBatteryProtection: lowBatteryProtection,
            lowBatteryThreshold: lowBatteryThreshold,
            thermalProtection: thermalProtection,
            context: context
        )

        if quickPaused {
            let reason = "状态栏已暂停：左键单击可恢复"
            status = RuntimeStatus(
                effectiveMode: .off,
                reason: reason,
                activeAppName: decision.activeAppName,
                activeAppBundleID: decision.activeAppBundleID,
                power: decision.power
            )
            assertions.apply(mode: .off, reason: "\(Brand.executableName): \(reason)")
            applySystemSleepOverride(
                for: .off,
                allowPrompt: allowSystemSleepPrompt,
                baseReason: reason,
                forceSync: forceSystemSleepSync
            )
            return
        }

        let closedLidBackgroundMode = forceClosedLidWake && decision.mode != .off && decision.power.lidClosed
        let runtimeReason = closedLidBackgroundMode
            ? "\(decision.reason)；强制闭盖后台运行：屏幕可熄灭"
            : decision.reason

        status = RuntimeStatus(
            effectiveMode: decision.mode,
            reason: runtimeReason,
            activeAppName: decision.activeAppName,
            activeAppBundleID: decision.activeAppBundleID,
            power: decision.power
        )

        assertions.apply(mode: assertionMode(for: decision.mode, power: decision.power), reason: "\(Brand.executableName): \(runtimeReason)")
        applySystemSleepOverride(
            for: decision.mode,
            allowPrompt: allowSystemSleepPrompt,
            baseReason: runtimeReason,
            forceSync: forceSystemSleepSync
        )
    }

    private func applySystemSleepOverride(
        for mode: KeepAwakeMode,
        allowPrompt: Bool,
        baseReason: String,
        forceSync: Bool = false
    ) {
        let shouldEnable = SleepOverrideRequestPolicy.target(
            forceClosedLidWake: forceClosedLidWake,
            mode: mode
        )
        let now = Date()
        if !forceSync, SleepOverrideRequestPolicy.shouldSkip(
            hasPendingRequest: pendingSleepOverrideRequest != nil,
            lastTarget: lastSleepOverrideTarget,
            newTarget: shouldEnable,
            allowPrompt: allowPrompt,
            lastSyncDate: lastSleepOverrideSyncDate,
            now: now
        ) {
            return
        }

        let existingRequest = pendingSleepOverrideRequest
        let mergedAllowPrompt = SleepOverrideRequestPolicy.mergedAllowPrompt(
            existingTarget: existingRequest?.shouldEnable,
            existingAllowPrompt: existingRequest?.allowPrompt,
            newTarget: shouldEnable,
            newAllowPrompt: allowPrompt
        )
        let shouldRestartWorker = SleepOverrideRequestPolicy.shouldRestartWorker(
            workerExists: sleepOverrideTask != nil,
            existingTarget: existingRequest?.shouldEnable,
            existingAllowPrompt: existingRequest?.allowPrompt,
            newTarget: shouldEnable,
            newAllowPrompt: allowPrompt
        )

        pendingSleepOverrideRequest = SleepOverrideRequest(
            shouldEnable: shouldEnable,
            allowPrompt: mergedAllowPrompt,
            baseReason: baseReason
        )
        if shouldEnable, !(systemSleepOverrideActive && systemSleepOverrideManagedByLidwake) {
            systemSleepOverridePhase = .enabling
        } else if !shouldEnable, systemSleepOverrideActive && systemSleepOverrideManagedByLidwake {
            systemSleepOverridePhase = .disabling
        }
        guard shouldRestartWorker else { return }

        sleepOverrideTask?.cancel()
        sleepOverrideWorkerID += 1
        let workerID = sleepOverrideWorkerID
        sleepOverrideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if shouldEnable {
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return
                }
            }

            guard workerID == sleepOverrideWorkerID,
                  let request = pendingSleepOverrideRequest,
                  request.shouldEnable == shouldEnable else {
                return
            }

            let result = await systemSleepOverride.setEnabled(
                request.shouldEnable,
                allowPrompt: request.allowPrompt
            )
            guard workerID == sleepOverrideWorkerID,
                  let latestRequest = pendingSleepOverrideRequest,
                  latestRequest.shouldEnable == request.shouldEnable else {
                return
            }

            sleepOverrideTask = nil
            pendingSleepOverrideRequest = nil
            lastSleepOverrideTarget = request.shouldEnable
            lastSleepOverrideSyncDate = Date()
            systemSleepOverrideActive = result.active
            systemSleepOverrideManagedByLidwake = result.managedByLidwake
            systemSleepAuthorizationInstalled = systemSleepOverride.isAuthorizationRuleInstalled
            systemSleepOverrideError = result.errorMessage
            systemSleepOverridePhase = result.errorMessage == nil
                ? (result.active && result.managedByLidwake ? .enabled : .idle)
                : .failed
            if request.shouldEnable && result.active && !result.managedByLidwake {
                isRestoring = true
                forceClosedLidWake = false
                UserDefaults.standard.set(false, forKey: Keys.forceClosedLidWake)
                isRestoring = false
            }
            if let error = result.errorMessage {
                status.reason = "\(latestRequest.baseReason)；\(error)"
            }
        }
    }

    private func currentPolicyContext() -> PolicyContext {
        let app = NSWorkspace.shared.frontmostApplication
        let currentExternalApplication = externalApplication(from: app)
        if let currentExternalApplication {
            lastExternalActiveApplication = currentExternalApplication
        }

        let bundleID = app?.bundleIdentifier ?? ""
        let displayName = app?.localizedName ?? (bundleID.isEmpty ? "未知" : bundleID)
        let active = currentExternalApplication
            ?? validatedLastExternalApplication()
            ?? ActiveApplication(
                displayName: displayName,
                bundleIdentifier: bundleID,
                processIdentifier: app?.processIdentifier ?? 0
            )

        return PolicyContext(
            activeAppName: active.displayName,
            activeAppBundleID: active.bundleIdentifier,
            power: PowerMonitor.snapshot()
        )
    }

    private func externalApplication(from app: NSRunningApplication?) -> ActiveApplication? {
        guard let app,
              let bundleID = app.bundleIdentifier,
              !bundleID.isEmpty,
              bundleID != ownBundleIdentifier,
              !app.isTerminated else {
            return nil
        }
        return ActiveApplication(
            displayName: app.localizedName ?? bundleID,
            bundleIdentifier: bundleID,
            processIdentifier: app.processIdentifier
        )
    }

    private func validatedLastExternalApplication() -> ActiveApplication? {
        guard let cached = lastExternalActiveApplication,
              cached.processIdentifier > 0,
              let runningApp = NSRunningApplication(processIdentifier: cached.processIdentifier),
              !runningApp.isTerminated,
              runningApp.bundleIdentifier == cached.bundleIdentifier else {
            lastExternalActiveApplication = nil
            return nil
        }
        return cached
    }

    private func observeSystemChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.screensDidSleepNotification
        ].forEach { name in
            MainQueueNotificationPublisher.publisher(center: workspaceCenter, name: name)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.evaluateNow() }
                }
                .store(in: &cancellables)
        }

        [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ].forEach { name in
            MainQueueNotificationPublisher.publisher(center: workspaceCenter, name: name)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.evaluateNow(
                            allowSystemSleepPrompt: false,
                            forceSystemSleepSync: true
                        )
                    }
                }
                .store(in: &cancellables)
        }

        [
            NSApplication.didChangeScreenParametersNotification,
            ProcessInfo.thermalStateDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange
        ].forEach { name in
            MainQueueNotificationPublisher.publisher(center: .default, name: name)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.evaluateNow() }
                }
                .store(in: &cancellables)
        }
    }

    private func assertionMode(for mode: KeepAwakeMode, power: PowerSnapshot) -> KeepAwakeMode {
        guard forceClosedLidWake, mode != .off, power.lidClosed else { return mode }
        return .keepSystemAwake
    }

    private func configureLaunchAtLogin() {
        guard !isRestoring else { return }

        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "开机启动设置失败：\(error.localizedDescription)"
            isRestoring = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isRestoring = false
        }
    }
}

enum MainQueueNotificationPublisher {
    static func publisher(
        center: NotificationCenter,
        name: Notification.Name
    ) -> AnyPublisher<Notification, Never> {
        center.publisher(for: name)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

enum RecoveryReadinessPolicy {
    static func isReady(
        workerRunning: Bool,
        requestPending: Bool,
        shouldEnableOverride: Bool,
        overrideActive: Bool,
        managedByLidwake: Bool,
        phase: SystemSleepOverridePhase
    ) -> Bool {
        guard !workerRunning, !requestPending else { return false }
        if shouldEnableOverride {
            return overrideActive && managedByLidwake && phase == .enabled
        }
        return !managedByLidwake
    }
}

private struct ActiveApplication {
    var displayName: String
    var bundleIdentifier: String
    var processIdentifier: pid_t
}

private struct SleepOverrideRequest {
    var shouldEnable: Bool
    var allowPrompt: Bool
    var baseReason: String
}

private enum Keys {
    static let manualMode = "settings.manualMode"
    static let scheduleEnabled = "settings.scheduleEnabled"
    static let schedules = "settings.schedules"
    static let whitelistEnabled = "settings.whitelistEnabled"
    static let whitelistMode = "settings.whitelistMode"
    static let whitelist = "settings.whitelist"
    static let lowBatteryProtection = "settings.lowBatteryProtection"
    static let lowBatteryThreshold = "settings.lowBatteryThreshold"
    static let thermalProtection = "settings.thermalProtection"
    static let forceClosedLidWake = "settings.forceClosedLidWake"
    static let menuBarIconStyle = "settings.menuBarIconStyle"
    static let menuBarIconUsesActiveColor = "settings.menuBarIconUsesActiveColor"
    static let menuBarIconColorHex = "settings.menuBarIconColorHex"
    static let lastNonOffManualMode = "settings.lastNonOffManualMode"
    static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    static let quickPaused = "runtime.quickPaused"
}
