import Foundation
import Testing
@testable import Lidwake

struct PolicyEngineTests {
    @Test func lowBatteryProtectionOverridesActiveModes() {
        let decision = evaluate(
            manualMode: .presentation,
            lowBatteryProtection: true,
            context: context(power: power(batteryPercent: 10, isOnACPower: false))
        )

        #expect(decision.mode == .off)
        #expect(decision.reason.contains("低电量保护"))
    }

    @Test func scheduleTakesPriorityOverWhitelistAndManualMode() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 6,
            hour: 10
        ))!
        let schedule = ScheduleRule(
            name: "工作时间",
            days: [2],
            startMinute: 9 * 60,
            endMinute: 18 * 60,
            mode: .keepSystemAwake,
            isEnabled: true
        )

        let decision = PolicyEngine.evaluate(
            manualMode: .keepDisplayOn,
            scheduleEnabled: true,
            schedules: [schedule],
            whitelistEnabled: true,
            whitelist: [],
            whitelistMode: .presentation,
            lowBatteryProtection: false,
            lowBatteryThreshold: 20,
            thermalProtection: false,
            context: context(now: now, calendar: calendar)
        )

        #expect(decision.mode == .keepSystemAwake)
        #expect(decision.reason == "定时规则：工作时间")
    }

    @Test func whitelistDisablesPolicyWhenFrontmostAppDoesNotMatch() {
        let decision = PolicyEngine.evaluate(
            manualMode: .presentation,
            scheduleEnabled: false,
            schedules: [],
            whitelistEnabled: true,
            whitelist: [WhitelistedApp(displayName: "Safari", bundleIdentifier: "com.apple.Safari")],
            whitelistMode: .keepDisplayOn,
            lowBatteryProtection: false,
            lowBatteryThreshold: 20,
            thermalProtection: false,
            context: context(bundleID: "com.apple.TextEdit")
        )

        #expect(decision.mode == .off)
        #expect(decision.reason == "当前 App 不在白名单")
    }

    @Test func displayAndPresentationModesKeepTheDisplayAwake() {
        #expect(KeepAwakeMode.keepDisplayOn.keepsDisplayAwake)
        #expect(KeepAwakeMode.presentation.keepsDisplayAwake)
        #expect(!KeepAwakeMode.keepSystemAwake.keepsDisplayAwake)
    }

    @Test func overnightScheduleUsesTheDayOnWhichItStarts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rule = ScheduleRule(
            name: "周一夜间",
            days: [2],
            startMinute: 22 * 60,
            endMinute: 2 * 60,
            mode: .keepSystemAwake,
            isEnabled: true
        )

        let mondayNight = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 6,
            hour: 23
        ))!
        let tuesdayEarlyMorning = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 7,
            hour: 1
        ))!
        let tuesdayAfterRule = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 7,
            hour: 3
        ))!

        #expect(rule.isActive(at: mondayNight, calendar: calendar))
        #expect(rule.isActive(at: tuesdayEarlyMorning, calendar: calendar))
        #expect(!rule.isActive(at: tuesdayAfterRule, calendar: calendar))
    }

    @Test func overnightScheduleDoesNotStartOnAnUnselectedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rule = ScheduleRule(
            name: "周一夜间",
            days: [2],
            startMinute: 22 * 60,
            endMinute: 2 * 60,
            mode: .keepSystemAwake,
            isEnabled: true
        )
        let tuesdayNight = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 7,
            hour: 23
        ))!

        #expect(!rule.isActive(at: tuesdayNight, calendar: calendar))
    }

    private func evaluate(
        manualMode: KeepAwakeMode,
        lowBatteryProtection: Bool,
        context: PolicyContext
    ) -> PolicyDecision {
        PolicyEngine.evaluate(
            manualMode: manualMode,
            scheduleEnabled: false,
            schedules: [],
            whitelistEnabled: false,
            whitelist: [],
            whitelistMode: .keepDisplayOn,
            lowBatteryProtection: lowBatteryProtection,
            lowBatteryThreshold: 20,
            thermalProtection: false,
            context: context
        )
    }

    private func context(
        bundleID: String = "com.apple.Safari",
        power snapshot: PowerSnapshot? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PolicyContext {
        PolicyContext(
            activeAppName: "Safari",
            activeAppBundleID: bundleID,
            power: snapshot ?? power(),
            now: now,
            calendar: calendar
        )
    }

    private func power(
        batteryPercent: Int? = 80,
        isOnACPower: Bool = true
    ) -> PowerSnapshot {
        PowerSnapshot(
            batteryPercent: batteryPercent,
            isCharging: isOnACPower,
            isOnACPower: isOnACPower,
            thermalState: "正常",
            lidClosed: false,
            externalDisplayConnected: false
        )
    }
}
