import AppKit
import SwiftUI

enum Brand {
    static let appName = "醒咖 Awake"
    static let executableName = "Awake"
    static let bundleIdentifier = "com.local.awake"
    static let legacyBundleIdentifier = "com.local.lidwake"
    static let watchdogExecutableName = "AwakeWatchdog"
    static let tagline = "一杯咖啡的时间，Mac 保持清醒。"
    static let defaultActiveColorHex = "#8D9D99"
    static let repositoryURL = URL(string: "https://github.com/AI-Good-Tool/Awake")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let issuesURL = repositoryURL.appendingPathComponent("issues")
    static let authorURL = URL(string: "https://github.com/vs2pk0")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/AI-Good-Tool/Awake/releases/latest")!

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
        activeColorHex: String
    ) -> NSImage {
        menuBarCoffeeCup(mode: mode, usesActiveColor: usesActiveColor, activeColorHex: activeColorHex)
    }

    static func activeStatusColor(hex: String) -> NSColor {
        NSColor(hex: hex) ?? NSColor(hex: Brand.defaultActiveColorHex) ?? .systemOrange
    }

    static func menuBarCoffeeCup(
        mode: KeepAwakeMode,
        usesActiveColor: Bool,
        activeColorHex: String
    ) -> NSImage {
        let isActive = mode != .off
        let usesColor = isActive && usesActiveColor
        let color = usesColor ? activeStatusColor(hex: activeColorHex) : .black
        // The drawing handler stays resolution-independent on Retina displays.
        let image = NSImage(size: NSSize(width: 25, height: 18), flipped: false) { _ in
            color.setStroke()
            color.setFill()

            let cup = NSBezierPath()
            cup.move(to: NSPoint(x: 3, y: 13))
            cup.line(to: NSPoint(x: 19, y: 13))
            cup.curve(to: NSPoint(x: 16, y: 5),
                      controlPoint1: NSPoint(x: 19, y: 9),
                      controlPoint2: NSPoint(x: 18, y: 6))
            cup.curve(to: NSPoint(x: 6, y: 5),
                      controlPoint1: NSPoint(x: 14, y: 3.5),
                      controlPoint2: NSPoint(x: 8, y: 3.5))
            cup.curve(to: NSPoint(x: 3, y: 13),
                      controlPoint1: NSPoint(x: 4, y: 6),
                      controlPoint2: NSPoint(x: 3, y: 9))
            cup.close()
            if isActive {
                cup.fill()
            } else {
                cup.lineWidth = 1.6
                cup.lineJoinStyle = .round
                cup.stroke()
            }

            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 18.8, y: 11.5))
            handle.curve(to: NSPoint(x: 18, y: 6.5),
                         controlPoint1: NSPoint(x: 25.5, y: 13),
                         controlPoint2: NSPoint(x: 25.5, y: 5.5))
            handle.lineWidth = 1.7
            handle.lineCapStyle = .round
            handle.stroke()

            let saucer = NSBezierPath()
            saucer.move(to: NSPoint(x: 2, y: 1.6))
            saucer.line(to: NSPoint(x: 21, y: 1.6))
            saucer.lineWidth = 1.6
            saucer.lineCapStyle = .round
            saucer.stroke()

            let steam = NSBezierPath()
            steam.move(to: NSPoint(x: 10.5, y: 15))
            steam.curve(to: NSPoint(x: 11.5, y: 17),
                        controlPoint1: NSPoint(x: 9, y: 16),
                        controlPoint2: NSPoint(x: 13, y: 16))
            steam.lineWidth = 1.2
            steam.lineCapStyle = .round
            steam.stroke()
            return true
        }
        image.isTemplate = !usesColor
        image.accessibilityDescription = Brand.appName
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
