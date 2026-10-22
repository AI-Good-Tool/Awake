import Foundation

enum KeepAwakeMode: String, CaseIterable, Codable, Identifiable {
    case off
    case keepDisplayOn
    case keepSystemAwake
    case presentation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "关闭"
        case .keepDisplayOn:
            "屏幕常亮"
        case .keepSystemAwake:
            "后台运行"
        case .presentation:
            "演示模式"
        }
    }

    var description: String {
        switch self {
        case .off:
            "释放所有电源保持策略。"
        case .keepDisplayOn:
            "阻止屏幕自动熄灭，同时尽量阻止系统空闲睡眠。"
        case .keepSystemAwake:
            "允许屏幕按系统设置熄灭，但阻止系统空闲睡眠，适合下载、编译、同步等后台任务。"
        case .presentation:
            "同时保持屏幕常亮和系统唤醒，适合演示、会议、监控面板或不想被打断的长任务。"
        }
    }

    var keepsDisplayAwake: Bool {
        self == .keepDisplayOn || self == .presentation
    }

    var keepsSystemAwake: Bool {
        self == .keepDisplayOn || self == .keepSystemAwake || self == .presentation
    }
}

enum SystemSleepOverridePhase: Equatable {
    case idle
    case enabling
    case enabled
    case disabling
    case failed
}

struct ScheduleRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var days: [Int]
    var startMinute: Int
    var endMinute: Int
    var mode: KeepAwakeMode
    var isEnabled: Bool

    static let workdayDefault = ScheduleRule(
        name: "工作日白天",
        days: [2, 3, 4, 5, 6],
        startMinute: 9 * 60,
        endMinute: 18 * 60,
        mode: .keepDisplayOn,
        isEnabled: false
    )

    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let weekday = calendar.component(.weekday, from: date)
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if startMinute <= endMinute {
            return days.contains(weekday)
                && currentMinute >= startMinute
                && currentMinute <= endMinute
        }

        if currentMinute >= startMinute {
            return days.contains(weekday)
        }

        let previousWeekday = weekday == 1 ? 7 : weekday - 1
        return currentMinute <= endMinute && days.contains(previousWeekday)
    }
}

struct WhitelistedApp: Identifiable, Codable, Hashable {
    var id = UUID()
    var displayName: String
    var bundleIdentifier: String
}

struct PowerSnapshot: Codable, Equatable {
    var batteryPercent: Int?
    var isCharging: Bool
    var isOnACPower: Bool
    var thermalState: String
    var lidClosed: Bool
    var externalDisplayConnected: Bool

    var clamshellReady: Bool {
        lidClosed && externalDisplayConnected && isOnACPower
    }
}

struct RuntimeStatus: Equatable {
    var effectiveMode: KeepAwakeMode = .off
    var reason: String = "未启用"
    var activeAppName: String = "未知"
    var activeAppBundleID: String = ""
    var power = PowerSnapshot(
        batteryPercent: nil,
        isCharging: false,
        isOnACPower: false,
        thermalState: "未知",
        lidClosed: false,
        externalDisplayConnected: false
    )
}

struct CrashRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var detectedAt: Date
    var note: String
}
