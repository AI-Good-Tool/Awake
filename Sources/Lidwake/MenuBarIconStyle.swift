import AppKit

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case classic = "01-classic-no-steam"
    case roundedMug = "02-rounded-mug"
    case wideLatte = "03-wide-latte"
    case espresso = "04-espresso"
    case takeaway = "05-takeaway"
    case mokaPot = "06-moka-pot"
    case nativeCup = "07-native-system-cup"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "经典杯 · 无蒸汽"
        case .roundedMug: "圆角马克杯"
        case .wideLatte: "矮胖拿铁杯"
        case .espresso: "直壁意式杯"
        case .takeaway: "外带纸杯"
        case .mokaPot: "小摩卡壶"
        case .nativeCup: "原生咖啡杯"
        }
    }

    static func restored(from rawValue: String?) -> Self {
        // Keep selections saved by 0.2.2 when renaming the native cup.
        if rawValue == "07-legacy-system-cup" { return .nativeCup }
        return rawValue.flatMap(Self.init(rawValue:)) ?? .classic
    }

    @MainActor
    func draw(in rect: NSRect, filled: Bool, color: NSColor) {
        if self == .nativeCup {
            let symbol = filled ? "cup.and.saucer.fill" : "cup.and.saucer"
            let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: filled ? .semibold : .regular)
                .applying(.init(hierarchicalColor: color))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(configuration) {
                image.isTemplate = false
                image.draw(in: rect)
            }
            return
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // The approved designs use a 25 × 18 canvas with a top-left origin.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / 25, y: -rect.height / 18)
        color.setFill()
        color.setStroke()

        func path(body: Bool = false, width: CGFloat = 1.6, _ build: (NSBezierPath) -> Void) {
            let shape = NSBezierPath()
            build(shape)
            shape.lineWidth = body ? 1.45 : width
            shape.lineCapStyle = .round
            shape.lineJoinStyle = .round
            if body && filled { shape.fill() } else { shape.stroke() }
        }

        switch self {
        case .classic:
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 3, y: 3.5))
                shape.line(to: NSPoint(x: 19, y: 3.5))
                shape.curve(to: NSPoint(x: 16, y: 13), controlPoint1: NSPoint(x: 19, y: 8), controlPoint2: NSPoint(x: 18, y: 11.8))
                shape.curve(to: NSPoint(x: 6, y: 13), controlPoint1: NSPoint(x: 14, y: 14.5), controlPoint2: NSPoint(x: 8, y: 14.5))
                shape.curve(to: NSPoint(x: 3, y: 3.5), controlPoint1: NSPoint(x: 4, y: 11.8), controlPoint2: NSPoint(x: 3, y: 8))
                shape.close()
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 18.8, y: 5.3))
                shape.curve(to: NSPoint(x: 18, y: 11), controlPoint1: NSPoint(x: 25.5, y: 3.8), controlPoint2: NSPoint(x: 25.5, y: 12))
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 2, y: 16.4))
                shape.line(to: NSPoint(x: 21, y: 16.4))
            }
        case .roundedMug:
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 4, y: 2.5))
                shape.line(to: NSPoint(x: 18, y: 2.5))
                shape.line(to: NSPoint(x: 18, y: 11.5))
                shape.curve(to: NSPoint(x: 14, y: 15.5), controlPoint1: NSPoint(x: 18, y: 14.5), controlPoint2: NSPoint(x: 16.5, y: 15.5))
                shape.line(to: NSPoint(x: 8, y: 15.5))
                shape.curve(to: NSPoint(x: 4, y: 11.5), controlPoint1: NSPoint(x: 5.5, y: 15.5), controlPoint2: NSPoint(x: 4, y: 14.5))
                shape.close()
            }
            path(width: 1.8) { shape in
                shape.move(to: NSPoint(x: 18, y: 5))
                shape.line(to: NSPoint(x: 20, y: 5))
                shape.curve(to: NSPoint(x: 20, y: 11.5), controlPoint1: NSPoint(x: 24.5, y: 5), controlPoint2: NSPoint(x: 24.5, y: 11.5))
                shape.line(to: NSPoint(x: 18, y: 11.5))
            }
        case .wideLatte:
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 2.5, y: 4.5))
                shape.line(to: NSPoint(x: 20, y: 4.5))
                shape.curve(to: NSPoint(x: 13.6, y: 14), controlPoint1: NSPoint(x: 19.6, y: 9.5), controlPoint2: NSPoint(x: 17.8, y: 13.4))
                shape.line(to: NSPoint(x: 9, y: 14))
                shape.curve(to: NSPoint(x: 2.5, y: 4.5), controlPoint1: NSPoint(x: 4.7, y: 13.4), controlPoint2: NSPoint(x: 2.9, y: 9.5))
                shape.close()
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 19.6, y: 6.1))
                shape.curve(to: NSPoint(x: 18.2, y: 10.6), controlPoint1: NSPoint(x: 25, y: 4.3), controlPoint2: NSPoint(x: 25, y: 11.6))
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 2, y: 16.4))
                shape.line(to: NSPoint(x: 21, y: 16.4))
            }
        case .espresso:
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 5, y: 3.5))
                shape.line(to: NSPoint(x: 17, y: 3.5))
                shape.line(to: NSPoint(x: 17, y: 10.6))
                shape.curve(to: NSPoint(x: 13.8, y: 14), controlPoint1: NSPoint(x: 17, y: 12.8), controlPoint2: NSPoint(x: 15.8, y: 14))
                shape.line(to: NSPoint(x: 8.2, y: 14))
                shape.curve(to: NSPoint(x: 5, y: 10.6), controlPoint1: NSPoint(x: 6.2, y: 14), controlPoint2: NSPoint(x: 5, y: 12.8))
                shape.close()
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 17, y: 5.2))
                shape.line(to: NSPoint(x: 19.5, y: 5.2))
                shape.curve(to: NSPoint(x: 19.5, y: 11.3), controlPoint1: NSPoint(x: 23.5, y: 5.2), controlPoint2: NSPoint(x: 23.5, y: 11.3))
                shape.line(to: NSPoint(x: 17, y: 11.3))
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 3, y: 16.4))
                shape.line(to: NSPoint(x: 21, y: 16.4))
            }
        case .takeaway:
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 6, y: 6.5))
                shape.line(to: NSPoint(x: 18, y: 6.5))
                shape.line(to: NSPoint(x: 16, y: 16))
                shape.line(to: NSPoint(x: 8, y: 16))
                shape.close()
            }
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 4.5, y: 3.4))
                shape.line(to: NSPoint(x: 6.5, y: 3.4))
                shape.line(to: NSPoint(x: 7.5, y: 1.5))
                shape.line(to: NSPoint(x: 16.5, y: 1.5))
                shape.line(to: NSPoint(x: 17.5, y: 3.4))
                shape.line(to: NSPoint(x: 19.5, y: 3.4))
                shape.line(to: NSPoint(x: 19.5, y: 4.5))
                shape.line(to: NSPoint(x: 4.5, y: 4.5))
                shape.close()
            }
        case .mokaPot:
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 6.5, y: 6.4))
                shape.line(to: NSPoint(x: 18, y: 6.4))
                shape.line(to: NSPoint(x: 16, y: 11.6))
                shape.line(to: NSPoint(x: 18, y: 16.3))
                shape.line(to: NSPoint(x: 6, y: 16.3))
                shape.line(to: NSPoint(x: 8.2, y: 11.6))
                shape.close()
            }
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 6.5, y: 4.6))
                shape.line(to: NSPoint(x: 10, y: 2.8))
                shape.line(to: NSPoint(x: 14.6, y: 2.8))
                shape.line(to: NSPoint(x: 18, y: 4.6))
                shape.close()
            }
            path(body: true) { shape in
                shape.move(to: NSPoint(x: 10.8, y: 0.8))
                shape.line(to: NSPoint(x: 13.8, y: 0.8))
                shape.line(to: NSPoint(x: 13.8, y: 2))
                shape.line(to: NSPoint(x: 10.8, y: 2))
                shape.close()
            }
            path(width: 1.6) { shape in
                shape.move(to: NSPoint(x: 18, y: 7.1))
                shape.line(to: NSPoint(x: 21, y: 6.4))
                shape.curve(to: NSPoint(x: 21, y: 11.4), controlPoint1: NSPoint(x: 24.2, y: 6.1), controlPoint2: NSPoint(x: 24.4, y: 10.8))
                shape.line(to: NSPoint(x: 17, y: 12))
            }
            path(width: 1.4) { shape in
                shape.move(to: NSPoint(x: 6.7, y: 7.7))
                shape.line(to: NSPoint(x: 2.8, y: 5.9))
                shape.line(to: NSPoint(x: 4.6, y: 10.8))
                shape.line(to: NSPoint(x: 7.4, y: 11.7))
            }
        case .nativeCup: break
        }
    }
}
