import AppKit
import Foundation

struct PolicyDecision {
    var mode: KeepAwakeMode
    var reason: String
    var activeAppName: String
    var activeAppBundleID: String
    var power: PowerSnapshot
}

struct PolicyContext {
    var activeAppName: String
    var activeAppBundleID: String
    var power: PowerSnapshot
    var now: Date = Date()
    var calendar: Calendar = .current
}

enum PolicyEngine {
    static func evaluate(
        manualMode: KeepAwakeMode,
        scheduleEnabled: Bool,
        schedules: [ScheduleRule],
        whitelistEnabled: Bool,
        whitelist: [WhitelistedApp],
        whitelistMode: KeepAwakeMode,
        lowBatteryProtection: Bool,
        lowBatteryThreshold: Int,
        thermalProtection: Bool
    ) -> PolicyDecision {
        let app = NSWorkspace.shared.frontmostApplication
        let activeName = app?.localizedName ?? "未知"
        let activeBundleID = app?.bundleIdentifier ?? ""
        let power = PowerMonitor.snapshot()

        return evaluate(
            manualMode: manualMode,
            scheduleEnabled: scheduleEnabled,
            schedules: schedules,
            whitelistEnabled: whitelistEnabled,
            whitelist: whitelist,
            whitelistMode: whitelistMode,
            lowBatteryProtection: lowBatteryProtection,
            lowBatteryThreshold: lowBatteryThreshold,
            thermalProtection: thermalProtection,
            context: PolicyContext(
                activeAppName: activeName,
                activeAppBundleID: activeBundleID,
                power: power
            )
        )
    }

    static func evaluate(
        manualMode: KeepAwakeMode,
        scheduleEnabled: Bool,
        schedules: [ScheduleRule],
        whitelistEnabled: Bool,
        whitelist: [WhitelistedApp],
        whitelistMode: KeepAwakeMode,
        lowBatteryProtection: Bool,
        lowBatteryThreshold: Int,
        thermalProtection: Bool,
        context: PolicyContext
    ) -> PolicyDecision {
        let activeName = context.activeAppName
        let activeBundleID = context.activeAppBundleID
        let power = context.power

        if lowBatteryProtection,
           let percent = power.batteryPercent,
           !power.isOnACPower,
           !power.isCharging,
           percent <= lowBatteryThreshold {
            return PolicyDecision(
                mode: .off,
                reason: "低电量保护已触发（\(percent)%）",
                activeAppName: activeName,
                activeAppBundleID: activeBundleID,
                power: power
            )
        }

        if thermalProtection, power.thermalState == "严重" || power.thermalState == "危险" {
            return PolicyDecision(
                mode: .off,
                reason: "温度保护已触发（\(power.thermalState)）",
                activeAppName: activeName,
                activeAppBundleID: activeBundleID,
                power: power
            )
        }

        if scheduleEnabled,
           let rule = schedules.first(where: { $0.isActive(at: context.now, calendar: context.calendar) }) {
            return PolicyDecision(
                mode: rule.mode,
                reason: "定时规则：\(rule.name)",
                activeAppName: activeName,
                activeAppBundleID: activeBundleID,
                power: power
            )
        }

        if whitelistEnabled {
            let matched = whitelist.contains { item in
                item.bundleIdentifier == activeBundleID
            }

            return PolicyDecision(
                mode: matched ? whitelistMode : .off,
                reason: matched ? "白名单 App：\(activeName)" : "当前 App 不在白名单",
                activeAppName: activeName,
                activeAppBundleID: activeBundleID,
                power: power
            )
        }

        return PolicyDecision(
            mode: manualMode,
            reason: manualMode == .off ? "手动关闭" : "手动模式：\(manualMode.title)",
            activeAppName: activeName,
            activeAppBundleID: activeBundleID,
            power: power
        )
    }
}
