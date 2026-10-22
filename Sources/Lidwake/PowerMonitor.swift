import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps

enum PowerMonitor {
    static func snapshot() -> PowerSnapshot {
        let battery = batteryState()
        let thermal = thermalStateName(ProcessInfo.processInfo.thermalState)

        return PowerSnapshot(
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            isOnACPower: battery.isOnACPower,
            thermalState: thermal,
            lidClosed: isLidClosed(),
            externalDisplayConnected: hasExternalDisplay()
        )
    }

    private static func batteryState() -> (percent: Int?, isCharging: Bool, isOnACPower: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return (nil, false, true)
        }

        let percent = description[kIOPSCurrentCapacityKey] as? Int
        let state = description[kIOPSPowerSourceStateKey] as? String
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isOnAC = state == kIOPSACPowerValue

        return (percent, charging, isOnAC)
    }

    private static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return false
        }

        return value
    }

    private static func hasExternalDisplay() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return false
        }

        var displays = Array(repeating: CGDirectDisplayID(0), count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return false
        }

        return displays.prefix(Int(displayCount)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            "正常"
        case .fair:
            "偏热"
        case .serious:
            "严重"
        case .critical:
            "危险"
        @unknown default:
            "未知"
        }
    }
}
