import Foundation

enum SystemSleepState: Equatable {
    case enabled
    case disabled
    case unknown
}

enum SystemSleepStateParser {
    static func state(globalOutput: String?, customOutput: String?) -> SystemSleepState {
        let globalValue = globalOutput.flatMap { settingValue(named: "SleepDisabled", in: $0) }
        let customValue = customOutput.flatMap { settingValue(named: "disablesleep", in: $0) }

        if globalValue == 1 || customValue == 1 {
            return .enabled
        }
        guard globalOutput != nil, customOutput != nil else { return .unknown }
        if globalValue == 0 || customValue == 0 {
            return .disabled
        }
        return .unknown
    }

    private static func settingValue(named name: Substring, in text: String) -> Int? {
        let values = text.split(separator: "\n").compactMap { line -> Int? in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[0] == name else { return nil }
            return Int(parts[1])
        }
        if values.contains(1) { return 1 }
        if !values.isEmpty, values.allSatisfy({ $0 == 0 }) { return 0 }
        return nil
    }
}

struct SystemSleepOverrideResult {
    var active: Bool
    var managedByLidwake: Bool
    var errorMessage: String?
}

struct SleepOverrideFailureState {
    private(set) var target: Bool?

    mutating func record(_ target: Bool) {
        self.target = target
    }

    mutating func clear() {
        target = nil
    }

    func shouldShortCircuit(target: Bool, allowPrompt: Bool) -> Bool {
        self.target == target && !allowPrompt
    }
}

final class SystemSleepOverrideController: @unchecked Sendable {
    private let appliedKey = "runtime.systemSleepOverrideApplied"
    private let managedKey = "runtime.systemSleepOverrideManaged"
    private let managedVersionKey = "runtime.systemSleepOverrideManagedVersion"
    private let managedVersion = 2
    private let authorizationValidationInterval: TimeInterval = 60 * 60
    private var currentOverrideEnabled: Bool
    private var managedByLidwake: Bool
    private var authorizationRuleInstalled: Bool
    private var lastAuthorizationValidationDate: Date
    private var failureState = SleepOverrideFailureState()
    private var watchdogProcess: Process?
    private let workQueue = DispatchQueue(label: "com.local.lidwake.system-sleep-override")

    var isApplied: Bool {
        workQueue.sync { currentOverrideEnabled }
    }

    var isManagedByLidwake: Bool {
        workQueue.sync { managedByLidwake }
    }

    var isAuthorizationRuleInstalled: Bool {
        workQueue.sync { authorizationRuleInstalled }
    }
    init() {
        let initialState = Self.readSystemDisableSleepState()
        authorizationRuleInstalled = AuthorizationArtifacts.areInstalled()
        lastAuthorizationValidationDate = Date()
        let storedApplied = UserDefaults.standard.bool(forKey: appliedKey)
        let storedManaged = UserDefaults.standard.bool(forKey: managedKey)
            && UserDefaults.standard.integer(forKey: managedVersionKey) == managedVersion

        switch initialState {
        case .enabled:
            currentOverrideEnabled = true
            managedByLidwake = storedManaged
            UserDefaults.standard.set(true, forKey: appliedKey)
        case .disabled:
            currentOverrideEnabled = false
            managedByLidwake = false
            UserDefaults.standard.set(false, forKey: appliedKey)
        case .unknown:
            currentOverrideEnabled = storedApplied
            managedByLidwake = storedApplied && storedManaged
        }
        UserDefaults.standard.set(managedByLidwake, forKey: managedKey)
    }

    func setEnabled(_ enabled: Bool, allowPrompt: Bool) async -> SystemSleepOverrideResult {
        await withCheckedContinuation { continuation in
            workQueue.async {
                continuation.resume(returning: self.setEnabledLocked(enabled, allowPrompt: allowPrompt))
            }
        }
    }

    func setEnabledForShutdown(_ enabled: Bool, allowPrompt: Bool) -> SystemSleepOverrideResult {
        workQueue.sync {
            setEnabledLocked(enabled, allowPrompt: allowPrompt)
        }
    }

    private func setEnabledLocked(_ enabled: Bool, allowPrompt: Bool) -> SystemSleepOverrideResult {
        let observedState = syncSystemState()
        refreshAuthorizationStatusIfNeeded()

        if AuthorizationArtifacts.requiresInstallation(
            toEnable: enabled,
            artifactsInstalled: authorizationRuleInstalled
        ) {
            guard allowPrompt else {
                failureState.record(enabled)
                return SystemSleepOverrideResult(
                    active: currentOverrideEnabled,
                    managedByLidwake: managedByLidwake,
                    errorMessage: "强制闭盖保护未启用：免密授权或开机恢复保护不完整，请先在设置中安装或修复。"
                )
            }
            do {
                try installAuthorizationArtifacts()
            } catch {
                failureState.record(enabled)
                AppLog.write("authorization protection installation failed: \(error.localizedDescription)")
                return SystemSleepOverrideResult(
                    active: currentOverrideEnabled,
                    managedByLidwake: managedByLidwake,
                    errorMessage: error.localizedDescription
                )
            }
        }

        if observedState != .unknown, currentOverrideEnabled == enabled {
            failureState.clear()
            if enabled && !managedByLidwake {
                guard allowPrompt else {
                    return SystemSleepOverrideResult(
                        active: currentOverrideEnabled,
                        managedByLidwake: managedByLidwake,
                        errorMessage: "系统已由外部开启闭盖不睡眠，\(Brand.appName) 不会接管或自动关闭。"
                    )
                }

                do {
                    try ensurePasswordlessPMSetRuleForCurrentState()
                    try startWatchdogIfNeeded()
                    markSystemOverride(true)
                    AppLog.write("adopted existing system sleep override")
                    return SystemSleepOverrideResult(
                        active: currentOverrideEnabled,
                        managedByLidwake: managedByLidwake,
                        errorMessage: nil
                    )
                } catch {
                    failureState.record(enabled)
                    AppLog.write("adopting existing system sleep override failed: \(error.localizedDescription)")
                    return SystemSleepOverrideResult(
                        active: currentOverrideEnabled,
                        managedByLidwake: managedByLidwake,
                        errorMessage: error.localizedDescription
                    )
                }
            }
            if enabled && managedByLidwake {
                do {
                    try startWatchdogIfNeeded()
                } catch {
                    return SystemSleepOverrideResult(
                        active: currentOverrideEnabled,
                        managedByLidwake: managedByLidwake,
                        errorMessage: error.localizedDescription
                    )
                }
            }
            return SystemSleepOverrideResult(active: currentOverrideEnabled, managedByLidwake: managedByLidwake, errorMessage: nil)
        }

        if observedState == .enabled, !enabled && !managedByLidwake {
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: "系统闭盖不睡眠由外部开启，\(Brand.appName) 未自动关闭。"
            )
        }

        if observedState == .unknown, !enabled, !managedByLidwake {
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: "无法确认系统闭盖睡眠状态；为避免关闭外部设置，\(Brand.appName) 未执行修改。"
            )
        }

        if failureState.shouldShortCircuit(target: enabled, allowPrompt: allowPrompt) {
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: enabled ? "强制闭盖保护未启用：需要管理员授权。" : "强制闭盖保护未恢复：需要管理员授权。"
            )
        }

        do {
            if enabled {
                try startWatchdogIfNeeded()
            }
            do {
                try runPasswordlessPMSet(disableSleep: enabled)
            } catch {
                if enabled { stopWatchdog() }
                throw error
            }
            markSystemOverride(enabled)
            if !enabled {
                stopWatchdog()
            }
            AppLog.write("system sleep override set to \(enabled) without prompt")
            return SystemSleepOverrideResult(active: currentOverrideEnabled, managedByLidwake: managedByLidwake, errorMessage: nil)
        } catch {
            refreshAuthorizationStatusIfNeeded(force: true)
            AppLog.write("passwordless pmset unavailable: \(error.localizedDescription)")
        }

        guard allowPrompt else {
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: enabled ? "强制闭盖后台运行需要重新授权。" : "强制闭盖后台运行需要重新授权才能恢复系统策略。"
            )
        }

        do {
            try installAuthorizationArtifacts()
            if enabled {
                try startWatchdogIfNeeded()
            }
            do {
                try runPasswordlessPMSet(disableSleep: enabled)
            } catch {
                if enabled { stopWatchdog() }
                throw error
            }
            markSystemOverride(enabled)
            if !enabled {
                stopWatchdog()
            }
            AppLog.write("system sleep override set to \(enabled)")
            return SystemSleepOverrideResult(active: currentOverrideEnabled, managedByLidwake: managedByLidwake, errorMessage: nil)
        } catch {
            refreshAuthorizationStatusIfNeeded(force: true)
            failureState.record(enabled)
            AppLog.write("system sleep override failed: \(error.localizedDescription)")
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: error.localizedDescription
            )
        }
    }

    @discardableResult
    private func syncSystemState() -> SystemSleepState {
        let state = Self.readSystemDisableSleepState()
        switch state {
        case .enabled:
            currentOverrideEnabled = true
            UserDefaults.standard.set(true, forKey: appliedKey)
        case .disabled:
            currentOverrideEnabled = false
            UserDefaults.standard.set(false, forKey: appliedKey)
            managedByLidwake = false
            stopWatchdog()
            UserDefaults.standard.set(false, forKey: managedKey)
            UserDefaults.standard.removeObject(forKey: managedVersionKey)
        case .unknown:
            AppLog.write("unable to determine system disablesleep state; preserving last known ownership")
        }
        return state
    }

    private func markSystemOverride(_ enabled: Bool) {
        currentOverrideEnabled = enabled
        managedByLidwake = enabled
        failureState.clear()
        UserDefaults.standard.set(enabled, forKey: appliedKey)
        UserDefaults.standard.set(enabled, forKey: managedKey)
        if enabled {
            UserDefaults.standard.set(managedVersion, forKey: managedVersionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: managedVersionKey)
        }
    }

    func removeAuthorizationRule(allowPrompt: Bool) async -> SystemSleepOverrideResult {
        await withCheckedContinuation { continuation in
            workQueue.async {
                continuation.resume(returning: self.removeAuthorizationRuleLocked(allowPrompt: allowPrompt))
            }
        }
    }

    func repairAuthorizationArtifacts() async -> SystemSleepOverrideResult {
        await withCheckedContinuation { continuation in
            workQueue.async {
                do {
                    try self.installAuthorizationArtifacts()
                    self.failureState.clear()
                    continuation.resume(returning: SystemSleepOverrideResult(
                        active: self.currentOverrideEnabled,
                        managedByLidwake: self.managedByLidwake,
                        errorMessage: nil
                    ))
                } catch {
                    AppLog.write("authorization protection repair failed: \(error.localizedDescription)")
                    continuation.resume(returning: SystemSleepOverrideResult(
                        active: self.currentOverrideEnabled,
                        managedByLidwake: self.managedByLidwake,
                        errorMessage: error.localizedDescription
                    ))
                }
            }
        }
    }

    private func removeAuthorizationRuleLocked(allowPrompt: Bool) -> SystemSleepOverrideResult {
        syncSystemState()
        if currentOverrideEnabled && managedByLidwake {
            let disableResult = setEnabledLocked(false, allowPrompt: allowPrompt)
            if disableResult.active && disableResult.managedByLidwake {
                return disableResult
            }
        }

        guard allowPrompt else {
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: "移除授权规则需要管理员授权。"
            )
        }

        do {
            try removeAuthorizationArtifactsWithPrompt()
        } catch {
            AppLog.write("sudoers removal failed: \(error.localizedDescription)")
            return SystemSleepOverrideResult(
                active: currentOverrideEnabled,
                managedByLidwake: managedByLidwake,
                errorMessage: error.localizedDescription
            )
        }

        managedByLidwake = false
        authorizationRuleInstalled = false
        lastAuthorizationValidationDate = Date()
        UserDefaults.standard.set(false, forKey: managedKey)
        UserDefaults.standard.removeObject(forKey: managedVersionKey)
        syncSystemState()
        return SystemSleepOverrideResult(active: currentOverrideEnabled, managedByLidwake: managedByLidwake, errorMessage: nil)
    }

    static func readSystemDisableSleepState() -> SystemSleepState {
        let globalOutput = runPMSetRead(arguments: ["-g"])
        let customOutput = runPMSetRead(arguments: ["-g", "custom"])
        return SystemSleepStateParser.state(globalOutput: globalOutput, customOutput: customOutput)
    }

    private static func runPMSetRead(arguments: [String]) -> String? {
        do {
            let result = try ProcessRunner.run(
                executable: "/usr/bin/pmset",
                arguments: arguments,
                timeout: 5
            )
            guard result.terminationStatus == 0 else {
                AppLog.write("pmset read exited with status \(result.terminationStatus)")
                return nil
            }
            return result.output
        } catch {
            AppLog.write("failed to read disablesleep state: \(error.localizedDescription)")
            return nil
        }
    }

    private func runPasswordlessPMSet(disableSleep: Bool) throws {
        let value = disableSleep ? "1" : "0"
        try runProcess(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", value],
            timeout: 10
        )
    }

    private func startWatchdogIfNeeded() throws {
        if let watchdogProcess, watchdogProcess.isRunning {
            return
        }

        guard let executableURL = watchdogExecutableURL() else {
            throw SystemSleepOverrideError.commandFailed("无法定位 \(Brand.appName) 可执行文件，安全看门进程未启动。")
        }

        let process = Process()
        process.executableURL = executableURL
        let parentPID = ProcessInfo.processInfo.processIdentifier
        process.arguments = [SleepOverrideWatchdog.argument, String(parentPID)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try SleepOverrideWatchdog.prepareRecovery(
            parentPID: parentPID,
            executablePath: executableURL.path
        )
        do {
            try process.run()
        } catch {
            SleepOverrideWatchdog.clearRecovery(parentPID: parentPID)
            throw error
        }
        SleepOverrideWatchdog.markRecoveryRunning(
            parentPID: parentPID,
            watchdogProcessID: process.processIdentifier,
            executablePath: executableURL.path
        )
        watchdogProcess = process
        AppLog.write("system sleep watchdog started: \(process.processIdentifier)")
    }

    private func watchdogExecutableURL() -> URL? {
        guard let mainExecutableURL = Bundle.main.executableURL else { return nil }
        let bundledWatchdogURL = mainExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent(Brand.watchdogExecutableName)
        if FileManager.default.isExecutableFile(atPath: bundledWatchdogURL.path) {
            return bundledWatchdogURL
        }
        return mainExecutableURL
    }

    private func stopWatchdog() {
        let parentPID = ProcessInfo.processInfo.processIdentifier
        if let watchdogProcess, watchdogProcess.isRunning {
            watchdogProcess.terminate()
        }
        self.watchdogProcess = nil
        SleepOverrideWatchdog.clearRecovery(parentPID: parentPID)
    }

    private func ensurePasswordlessPMSetRuleForCurrentState() throws {
        do {
            try runPasswordlessPMSet(disableSleep: currentOverrideEnabled)
        } catch {
            AppLog.write("passwordless pmset unavailable during adoption: \(error.localizedDescription)")
            try installAuthorizationArtifacts()
            try runPasswordlessPMSet(disableSleep: currentOverrideEnabled)
        }
    }

    private func installAuthorizationArtifacts() throws {
        let username = NSUserName()
        guard username.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw SystemSleepOverrideError.commandFailed("当前用户名包含 sudoers 不支持的字符：\(username)")
        }

        let sudoersComment = "# Awake: allow closed-lid background mode toggle."
        let sudoersLine = "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let command = [
            "set -e",
            "sudoers_tmp=$(/usr/bin/mktemp /tmp/lidwake-sudoers.XXXXXX)",
            "daemon_tmp=$(/usr/bin/mktemp /tmp/lidwake-daemon.XXXXXX)",
            "trap '/bin/rm -f \"$sudoers_tmp\" \"$daemon_tmp\"' EXIT",
            "/usr/bin/printf '%s\\n' \(shellSingleQuoted(sudoersComment)) \(shellSingleQuoted(sudoersLine)) > \"$sudoers_tmp\"",
            "/usr/bin/printf '%s\\n' \(shellSingleQuoted(AuthorizationArtifacts.bootResetPlist)) > \"$daemon_tmp\"",
            "/usr/sbin/chown root:wheel \"$sudoers_tmp\" \"$daemon_tmp\"",
            "/bin/chmod 0440 \"$sudoers_tmp\"",
            "/bin/chmod 0644 \"$daemon_tmp\"",
            "/usr/sbin/visudo -cf \"$sudoers_tmp\" >/dev/null",
            "/usr/bin/plutil -lint \"$daemon_tmp\" >/dev/null",
        ] + AuthorizationArtifacts.safeInstallationMoveCommands
        let commandText = command.joined(separator: "; ")

        let escapedCommand = commandText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedCommand)\" with administrator privileges"

        try runProcess(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 120)
        guard AuthorizationArtifacts.areInstalled() else {
            authorizationRuleInstalled = false
            throw SystemSleepOverrideError.commandFailed("授权文件已写入，但完整性或免密权限验证失败。")
        }
        authorizationRuleInstalled = true
        lastAuthorizationValidationDate = Date()
    }

    private func removeAuthorizationArtifactsWithPrompt() throws {
        let command = [
            "/bin/launchctl bootout system/\(AuthorizationArtifacts.bootResetLabel) >/dev/null 2>&1 || true",
            "/bin/rm -f \(shellSingleQuoted(AuthorizationArtifacts.sudoersPath)) \(shellSingleQuoted(AuthorizationArtifacts.bootResetPlistPath))"
        ].joined(separator: "; ")
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedCommand)\" with administrator privileges"
        try runProcess(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 120)
        authorizationRuleInstalled = false
        lastAuthorizationValidationDate = Date()
    }

    private func refreshAuthorizationStatusIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastAuthorizationValidationDate) >= authorizationValidationInterval else {
            return
        }
        authorizationRuleInstalled = AuthorizationArtifacts.areInstalled()
        lastAuthorizationValidationDate = now
    }

    private func runProcess(executable: String, arguments: [String], timeout: TimeInterval) throws {
        let result = try ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: timeout
        )
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.terminationStatus == 0 else {
            let detail = message.isEmpty ? "\(executable) 退出码 \(result.terminationStatus)" : message
            throw SystemSleepOverrideError.commandFailed(detail)
        }
    }

    private func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum SystemSleepOverrideError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            "强制闭盖保护失败：\(detail)"
        }
    }
}
