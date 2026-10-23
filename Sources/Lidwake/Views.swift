import SwiftUI

struct MenuHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: BrandImages.menuBarCoffeeCup(
                    mode: appState.status.effectiveMode,
                    usesActiveColor: appState.menuBarIconUsesActiveColor,
                    activeColorHex: appState.menuBarIconColorHex,
                    style: appState.menuBarIconStyle
                ))
                .frame(width: 25, height: 18)
                Text(appState.quickPaused ? "已暂停" : appState.status.effectiveMode.title)
                    .font(.headline)
            }
            Text(appState.status.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.status.power.lidClosed {
                Text(closedLidText)
                    .font(.caption)
                    .foregroundStyle(closedLidColor)
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var closedLidText: String {
        if appState.systemSleepOverrideManagedByLidwake {
            return "强制闭盖保护已启用"
        }
        if appState.systemSleepOverrideActive {
            return "系统闭盖不睡眠已由外部开启"
        }
        return appState.status.power.clamshellReady ? "闭盖模式条件已满足" : "已闭盖，但缺少外接显示器或电源"
    }

    private var closedLidColor: Color {
        appState.status.power.clamshellReady || appState.systemSleepOverrideManagedByLidwake ? .green : .orange
    }
}

struct SettingsView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("总览", systemImage: "switch.2") }
                .tag(SettingsTab.general)
            WhitelistSettingsView()
                .tabItem { Label("白名单", systemImage: "app.badge") }
                .tag(SettingsTab.whitelist)
            ScheduleSettingsView()
                .tabItem { Label("定时", systemImage: "calendar") }
                .tag(SettingsTab.schedule)
            DiagnosticsView()
                .tabItem { Label("诊断", systemImage: "waveform.path.ecg") }
                .tag(SettingsTab.diagnostics)
            AboutSettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 760, height: 560)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("当前状态") {
                StatusCard(
                    status: appState.status,
                    isPaused: appState.quickPaused,
                    systemSleepOverrideActive: appState.systemSleepOverrideActive,
                    systemSleepOverrideManagedByLidwake: appState.systemSleepOverrideManagedByLidwake
                )
            }

            Section("手动模式") {
                Picker("默认策略", selection: $appState.manualMode) {
                    ForEach(KeepAwakeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(appState.manualMode.description)
                    .foregroundStyle(.secondary)
            }

            MenuBarIconSettingsSection()

            Section("保护策略") {
                Toggle("低电量保护", isOn: $appState.lowBatteryProtection)
                Stepper("电量低于 \(appState.lowBatteryThreshold)% 时自动释放保持策略", value: $appState.lowBatteryThreshold, in: 5...80, step: 5)
                    .disabled(!appState.lowBatteryProtection)
                Toggle("温度保护", isOn: $appState.thermalProtection)
                Toggle("开机自动启动", isOn: $appState.launchAtLogin)
                if let error = appState.launchAtLoginError {
                    Text(error)
                        .foregroundStyle(.orange)
                }
            }

            Section("闭盖运行") {
                Toggle("强制闭盖后台运行（需要管理员授权）", isOn: $appState.forceClosedLidWake)
                if appState.systemSleepOverridePhase == .enabling {
                    Label("正在准备强制闭盖保护，请暂勿合盖", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                } else if appState.systemSleepOverridePhase == .disabling {
                    Label("正在恢复系统睡眠设置", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                if appState.systemSleepOverrideActive {
                    Label(systemSleepOverrideStatusText, systemImage: appState.systemSleepOverrideManagedByLidwake ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(appState.systemSleepOverrideManagedByLidwake ? .green : .orange)
                }
                if appState.systemSleepAuthorizationInstalled {
                    Label("免密授权与开机恢复保护已安装", systemImage: "key.horizontal")
                        .foregroundStyle(.secondary)
                } else {
                    Label("开机恢复保护尚未安装", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button {
                        appState.repairSystemSleepAuthorization()
                    } label: {
                        Label("安装或修复保护...", systemImage: "wrench.and.screwdriver")
                    }
                }
                if let error = appState.systemSleepOverrideError {
                    Text(error)
                        .foregroundStyle(.orange)
                }
                Text("选择非关闭模式后会预先启用系统级闭盖保护；未闭盖时，屏幕仍按所选的常亮或演示模式运行。")
                    .foregroundStyle(.secondary)
                Text("首次开启会请求管理员权限安装一条仅限 pmset disablesleep 0/1 的本机规则；之后切换不再反复授权。")
                    .foregroundStyle(.secondary)
                Text("适合 Codex、下载、编译等长任务。暂停或选择关闭会恢复系统策略；免密规则会保留，用于下次无弹窗切换。")
                    .foregroundStyle(.secondary)
                Text("移除授权规则需要管理员授权。")
                    .foregroundStyle(.secondary)
                Text("不启用此项时，闭盖运行仍遵循 macOS 官方闭盖显示模式条件，通常需要外接显示器、外接输入设备和电源。")
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    appState.removeSystemSleepAuthorization()
                } label: {
                    Label("移除授权与开机恢复保护...", systemImage: "trash")
                }
            }

        }
        .formStyle(.grouped)
        .padding()
    }

    private var systemSleepOverrideStatusText: String {
        if appState.systemSleepOverrideManagedByLidwake {
            return appState.status.power.lidClosed
                ? "\(Brand.appName) 强制闭盖保护运行中"
                : "\(Brand.appName) 强制闭盖保护已预启用"
        }
        return "系统闭盖不睡眠已由外部开启"
    }
}

struct StatusCard: View {
    var status: RuntimeStatus
    var isPaused: Bool
    var systemSleepOverrideActive: Bool
    var systemSleepOverrideManagedByLidwake: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                Label(isPaused ? "已暂停" : status.effectiveMode.title, systemImage: "power")
                Text(status.reason)
            }
            GridRow {
                Label("当前 App", systemImage: "macwindow")
                Text(status.activeAppName)
            }
            GridRow {
                Label("电源", systemImage: "battery.100")
                Text(powerText)
            }
            GridRow {
                Label("温度", systemImage: "thermometer.medium")
                Text(status.power.thermalState)
            }
            GridRow {
                Label("闭盖", systemImage: "laptopcomputer")
                Text(clamshellText)
                    .foregroundStyle(status.power.clamshellReady || systemSleepOverrideManagedByLidwake ? .green : .secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var powerText: String {
        let battery = status.power.batteryPercent.map { "\($0)%" } ?? "未知"
        let source = status.power.isOnACPower ? "电源适配器" : "电池"
        return "\(battery)，\(source)"
    }

    private var clamshellText: String {
        guard status.power.lidClosed else {
            return systemSleepOverrideManagedByLidwake ? "未闭盖（保护已预启用）" : "未闭盖"
        }
        if systemSleepOverrideManagedByLidwake { return "强制后台运行" }
        if systemSleepOverrideActive { return "外部已开启" }
        return status.power.clamshellReady ? "可继续运行" : "条件不足"
    }
}

struct WhitelistSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var manualDisplayName = ""
    @State private var manualBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Form {
                Toggle("启用 App 白名单策略", isOn: $appState.whitelistEnabled)
                Picker("命中白名单时使用", selection: $appState.whitelistMode) {
                    ForEach(KeepAwakeMode.allCases.filter { $0 != .off }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("白名单 App", systemImage: "app.badge")
                        .font(.headline)
                    Spacer()
                    Text("当前：\(appState.status.activeAppName)")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        appState.addFrontmostAppToWhitelist()
                    } label: {
                        Label("添加当前前台 App", systemImage: "plus")
                    }

                    TextField("显示名称", text: $manualDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)

                    TextField("Bundle ID，例如 com.apple.Safari", text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        appState.addWhitelistApp(displayName: manualDisplayName, bundleIdentifier: manualBundleID)
                        manualDisplayName = ""
                        manualBundleID = ""
                    } label: {
                        Label("手动添加", systemImage: "plus.circle")
                    }
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if appState.whitelist.isEmpty {
                    ContentUnavailableView(
                        "还没有白名单 App",
                        systemImage: "app.dashed",
                        description: Text("添加前台 App，或手动输入 Bundle ID。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    List {
                        ForEach(appState.whitelist) { item in
                            WhitelistRow(item: item) {
                                appState.removeWhitelistItem(item)
                            }
                        }
                        .onDelete(perform: appState.removeWhitelistItems)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
    }
}

struct WhitelistRow: View {
    var item: WhitelistedApp
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.headline)
                Text(item.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.vertical, 6)
    }
}

struct ScheduleSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用定时规则", isOn: $appState.scheduleEnabled)
                .font(.headline)

            List {
                ForEach($appState.schedules) { $rule in
                    ScheduleRuleEditor(rule: $rule)
                }
                .onDelete(perform: appState.removeSchedules)
            }

            HStack {
                Button {
                    appState.addSchedule()
                } label: {
                    Label("新增规则", systemImage: "plus")
                }
                Spacer()
                Text("定时规则优先级高于手动模式和白名单。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct ScheduleRuleEditor: View {
    @Binding var rule: ScheduleRule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()
                TextField("规则名称", text: $rule.name)
                    .font(.headline)
                Picker("模式", selection: $rule.mode) {
                    ForEach(KeepAwakeMode.allCases.filter { $0 != .off }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 150)
            }

            HStack {
                Stepper("开始 \(minuteText(rule.startMinute))", value: $rule.startMinute, in: 0...1439, step: 15)
                Stepper("结束 \(minuteText(rule.endMinute))", value: $rule.endMinute, in: 0...1439, step: 15)
            }

            WeekdayPicker(days: $rule.days)
        }
        .padding(.vertical, 8)
    }
}

struct WeekdayPicker: View {
    @Binding var days: [Int]
    private let titles = [(1, "日"), (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六")]

    var body: some View {
        HStack {
            ForEach(titles, id: \.0) { value, title in
                Button(title) {
                    if days.contains(value) {
                        days.removeAll { $0 == value }
                    } else {
                        days.append(value)
                        days.sort()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(days.contains(value) ? .accentColor : .gray.opacity(0.25))
            }
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    private var records: [CrashRecord] { CrashDiagnostics.shared.records }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("本地诊断")
                .font(.title2.bold())
            Text("无证书本地版本不接入第三方崩溃平台。这里会记录上次未正常退出的痕迹，并可导出运行状态，便于官网分发前排查问题。")
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    appState.exportDiagnostics()
                } label: {
                    Label("导出诊断到桌面", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    appState.clearDiagnostics()
                } label: {
                    Label("清除记录", systemImage: "trash")
                }
                .disabled(records.isEmpty)

                Spacer()

                Text("\(records.count) 条记录")
                    .foregroundStyle(.secondary)
            }

            if let url = appState.lastDiagnosticsURL {
                Text("已导出：\(url.path)")
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                ContentUnavailableView(
                    "没有诊断记录",
                    systemImage: "checkmark.seal",
                    description: Text("异常退出记录会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(records) { record in
                    VStack(alignment: .leading) {
                        Text(record.note)
                        Text(record.detectedAt.formatted(date: .numeric, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                CoffeeCupLogoView(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Brand.appName)
                        .font(.largeTitle.bold())
                    Text(Brand.tagline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("保持屏幕常亮，或在系统允许的闭盖显示模式下让任务继续运行。")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(symbol: "display", title: "屏幕常亮", detail: "适合演示、阅读、监控面板。")
                FeatureRow(symbol: "bolt.horizontal", title: "后台运行", detail: "适合下载、同步、长时间任务。")
                FeatureRow(symbol: "app.badge", title: "App 白名单", detail: "只在指定 App 位于前台时启用策略。")
                FeatureRow(symbol: "battery.100", title: "保护策略", detail: "低电量或热状态异常时自动释放。")
            }

            Text("默认闭盖运行受 macOS 官方闭盖显示模式限制；需要强制合盖不断任务时，可在设置中开启强制闭盖后台运行。")
                .font(.callout)
                .foregroundStyle(.orange)

            HStack {
                Spacer()
                Button("开始使用") {
                    appState.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 560)
    }
}

struct FeatureRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

private func minuteText(_ minute: Int) -> String {
    let hour = minute / 60
    let min = minute % 60
    return String(format: "%02d:%02d", hour, min)
}
