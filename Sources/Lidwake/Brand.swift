import AppKit
import SwiftUI

enum Brand {
    static let appName = "醒咖"
    static let executableName = "Awake"
    static let bundleIdentifier = "com.local.awake"
    static let legacyBundleIdentifier = "com.local.lidwake"
    static let watchdogExecutableName = "AwakeWatchdog"
    static let tagline = "一杯咖啡的时间，Mac 保持清醒。"
    static let defaultActiveColorHex = "#00A8FF"
    static let repositoryURL = URL(string: "https://github.com/AI-Good-Tool/Awake")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let issuesURL = repositoryURL.appendingPathComponent("issues")
    static let authorURL = URL(string: "https://github.com/vs2pk0")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/AI-Good-Tool/Awake/releases/latest")!

    static func restoredActiveColorHex(from saved: String?) -> String {
        // Upgrade the previous default while keeping custom colors.
        guard let saved, saved.uppercased() != "#8D9D99" else { return defaultActiveColorHex }
        return saved
    }

    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version)（\(build)）"
    }
}

@MainActor
enum BrandImages {
    static func statusBarCoffeeCupSymbol(
        mode: KeepAwakeMode,
        usesActiveColor: Bool,
        activeColorHex: String,
        style: MenuBarIconStyle = .classic
    ) -> NSImage {
        menuBarCoffeeCup(mode: mode, usesActiveColor: usesActiveColor, activeColorHex: activeColorHex, style: style)
    }

    static func activeStatusColor(hex: String) -> NSColor {
        NSColor(hex: hex) ?? NSColor(hex: Brand.defaultActiveColorHex) ?? .systemOrange
    }

    static func menuBarCoffeeCup(
        mode: KeepAwakeMode,
        usesActiveColor: Bool,
        activeColorHex: String,
        style: MenuBarIconStyle = .classic
    ) -> NSImage {
        let isActive = mode != .off
        let usesColor = isActive && usesActiveColor
        let color = usesColor ? activeStatusColor(hex: activeColorHex) : .black
        let image = NSImage(size: NSSize(width: 25, height: 18), flipped: false) { rect in
            style.draw(in: rect, filled: isActive, color: color)
            return true
        }
        image.isTemplate = !usesColor
        image.accessibilityDescription = "\(Brand.appName) · \(style.title) · \(isActive ? "运行" : "关闭")"
        return image
    }

    private static let appIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    static func bundledAppIcon() -> NSImage? { appIcon }
}

struct CoffeeCupLogoView: View {
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let icon = BrandImages.bundledAppIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "cup.and.saucer.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(Color(nsColor: BrandImages.activeStatusColor(hex: Brand.defaultActiveColorHex)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Brand.appName) 应用图标")
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let integer = UInt64(value, radix: 16) else {
            return nil
        }

        self.init(
            calibratedRed: CGFloat((integer & 0xFF0000) >> 16) / 255,
            green: CGFloat((integer & 0x00FF00) >> 8) / 255,
            blue: CGFloat(integer & 0x0000FF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else {
            return Brand.defaultActiveColorHex
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
