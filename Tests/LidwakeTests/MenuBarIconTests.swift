import AppKit
import Testing
@testable import Lidwake

struct MenuBarIconTests {
    @Test func missingOrUnrecognizedPreferenceFallsBackToClassic() {
        #expect(MenuBarIconStyle.restored(from: nil) == .classic)
        #expect(MenuBarIconStyle.restored(from: "07-legacy-system-cup") == .nativeCup)
        #expect(MenuBarIconStyle.restored(from: "unknown-future-style") == .classic)
        for style in MenuBarIconStyle.allCases {
            #expect(MenuBarIconStyle.restored(from: style.rawValue) == style)
        }
    }

    @Test func defaultColorUpgradePreservesCustomColors() {
        #expect(Brand.restoredActiveColorHex(from: nil) == "#00A8FF")
        #expect(Brand.restoredActiveColorHex(from: "#8d9d99") == "#00A8FF")
        #expect(Brand.restoredActiveColorHex(from: "#FF8822") == "#FF8822")
    }

    @MainActor
    @Test(arguments: MenuBarIconStyle.allCases)
    func everyStyleRendersDistinctRunningAndStoppedStates(style: MenuBarIconStyle) throws {
        func bitmap(mode: KeepAwakeMode, colored: Bool) throws -> NSBitmapImageRep {
            let image = BrandImages.statusBarCoffeeCupSymbol(
                mode: mode, usesActiveColor: colored, activeColorHex: Brand.defaultActiveColorHex, style: style
            )
            #expect(image.size == NSSize(width: 25, height: 18))
            #expect(image.isTemplate == (mode == .off || !colored))
            let data = try #require(image.tiffRepresentation)
            return try #require(NSBitmapImageRep(data: data))
        }
        let running = try bitmap(mode: .keepDisplayOn, colored: true)
        let stopped = try bitmap(mode: .off, colored: true)
        _ = try bitmap(mode: .keepSystemAwake, colored: false)
        var runningAlpha: CGFloat = 0
        var stoppedAlpha: CGFloat = 0
        for y in 0..<running.pixelsHigh {
            for x in 0..<running.pixelsWide {
                runningAlpha += try #require(running.colorAt(x: x, y: y)).alphaComponent
                stoppedAlpha += try #require(stopped.colorAt(x: x, y: y)).alphaComponent
            }
        }
        #expect(stoppedAlpha > 10, "The outline must be visible")
        #expect(runningAlpha > stoppedAlpha, "The running icon must have a filled body")
    }
}
