import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: 34)
        super.init()
        AppLog.write("status item allocated; button exists: \(statusItem.button != nil)")
        statusItem.isVisible = true
        configureButton()
        bindState()
        refreshIcon()
        AppLog.write("status item configured")
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            AppLog.write("status item button missing in configureButton")
            return
        }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = "\(Brand.appName)：左键暂停/恢复，右键打开菜单"
    }

    private func bindState() {
        appState.$manualMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        appState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        appState.$menuBarIconUsesActiveColor
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        appState.$menuBarIconColorHex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        appState.$systemSleepOverrideActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        guard let button = statusItem.button else {
            AppLog.write("status item button missing in refreshIcon")
            return
        }
        let isActive = appState.status.effectiveMode != .off
        let iconColor: NSColor

        if isActive, appState.menuBarIconUsesActiveColor {
            iconColor = BrandImages.activeStatusColor(hex: appState.menuBarIconColorHex)
        } else {
            iconColor = isActive ? .labelColor : NSColor.secondaryLabelColor.withAlphaComponent(0.45)
        }

        let image = BrandImages.statusBarCoffeeCupSymbol(
            mode: appState.status.effectiveMode,
            usesActiveColor: appState.menuBarIconUsesActiveColor,
            activeColorHex: appState.menuBarIconColorHex
        )

        button.image = image
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = iconColor

        statusItem.length = 29
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            appState.toggleModeFromStatusItem()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let titleText = appState.quickPaused ? "已暂停" : appState.status.effectiveMode.title
        let title = NSMenuItem(title: titleText, action: nil, keyEquivalent: "")
        title.image = BrandImages.statusBarCoffeeCupSymbol(
            mode: appState.status.effectiveMode,
            usesActiveColor: appState.menuBarIconUsesActiveColor,
            activeColorHex: appState.menuBarIconColorHex
        )
        menu.addItem(title)

        let reason = NSMenuItem(title: appState.status.reason, action: nil, keyEquivalent: "")
        reason.isEnabled = false
        menu.addItem(reason)

        let hintTitle = appState.quickPaused
            ? "左键单击：恢复策略评估"
            : "左键单击：暂停当前策略"
        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        let modeItem = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in KeepAwakeMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = appState.manualMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let pauseTitle = appState.quickPaused ? "恢复当前策略" : "暂停当前策略"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let whitelistItem = NSMenuItem(title: "启用 App 白名单", action: #selector(toggleWhitelist), keyEquivalent: "")
        whitelistItem.target = self
        whitelistItem.state = appState.whitelistEnabled ? .on : .off
        menu.addItem(whitelistItem)

        let scheduleItem = NSMenuItem(title: "启用定时规则", action: #selector(toggleSchedule), keyEquivalent: "")
        scheduleItem.target = self
        scheduleItem.state = appState.scheduleEnabled ? .on : .off
        menu.addItem(scheduleItem)

        let forceClosedLidItem = NSMenuItem(title: "强制闭盖后台运行", action: #selector(toggleForceClosedLidWake), keyEquivalent: "")
        forceClosedLidItem.target = self
        forceClosedLidItem.state = appState.forceClosedLidWake ? .on : .off
        menu.addItem(forceClosedLidItem)

        if let error = appState.systemSleepOverrideError {
            let errorItem = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "打开设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let diagnosticsItem = NSMenuItem(title: "导出诊断...", action: #selector(exportDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = KeepAwakeMode(rawValue: rawValue) else {
            return
        }
        appState.manualMode = mode
    }

    @objc private func toggleWhitelist() {
        appState.whitelistEnabled.toggle()
    }

    @objc private func togglePause() {
        appState.toggleModeFromStatusItem()
    }

    @objc private func toggleSchedule() {
        appState.scheduleEnabled.toggle()
    }

    @objc private func toggleForceClosedLidWake() {
        appState.forceClosedLidWake.toggle()
    }

    @objc private func openSettings() {
        appState.openSettings()
    }

    @objc private func exportDiagnostics() {
        appState.exportDiagnostics()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
