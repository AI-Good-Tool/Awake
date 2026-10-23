import AppKit
import Foundation

// One set of vector paths drives both SVG exports and the native-size comparison sheet.
struct Stroke {
    let path: String
    var width: CGFloat = 1.6
}

struct Design {
    let id: String
    let title: String
    let note: String
    let bodies: [String]
    let strokes: [Stroke]
    var nativeSymbol: String? = nil
}

let designs: [Design] = [
    Design(id: "01-classic-no-steam", title: "01  经典杯 · 无蒸汽", note: "沿用现在的宽杯身与杯碟，去掉上方蒸汽。",
           bodies: ["M 3 3.5 L 19 3.5 C 19 8 18 11.8 16 13 C 14 14.5 8 14.5 6 13 C 4 11.8 3 8 3 3.5 Z"],
           strokes: [Stroke(path: "M 18.8 5.3 C 25.5 3.8 25.5 12 18 11"), Stroke(path: "M 2 16.4 L 21 16.4")]),
    Design(id: "02-rounded-mug", title: "02  圆角马克杯", note: "杯身更高、更饱满，没有杯碟，轮廓更利落。",
           bodies: ["M 4 2.5 L 18 2.5 L 18 11.5 C 18 14.5 16.5 15.5 14 15.5 L 8 15.5 C 5.5 15.5 4 14.5 4 11.5 Z"],
           strokes: [Stroke(path: "M 18 5 L 20 5 C 24.5 5 24.5 11.5 20 11.5 L 18 11.5", width: 1.8)]),
    Design(id: "03-wide-latte", title: "03  矮胖拿铁杯", note: "宽口、低重心，小尺寸下也有柔和的分量感。",
           bodies: ["M 2.5 4.5 L 20 4.5 C 19.6 9.5 17.8 13.4 13.6 14 L 9 14 C 4.7 13.4 2.9 9.5 2.5 4.5 Z"],
           strokes: [Stroke(path: "M 19.6 6.1 C 25 4.3 25 11.6 18.2 10.6"), Stroke(path: "M 2 16.4 L 21 16.4")]),
    Design(id: "04-espresso", title: "04  直壁意式杯", note: "短直杯身配小把手，更像一枚克制的系统符号。",
           bodies: ["M 5 3.5 L 17 3.5 L 17 10.6 C 17 12.8 15.8 14 13.8 14 L 8.2 14 C 6.2 14 5 12.8 5 10.6 Z"],
           strokes: [Stroke(path: "M 17 5.2 L 19.5 5.2 C 23.5 5.2 23.5 11.3 19.5 11.3 L 17 11.3"), Stroke(path: "M 3 16.4 L 21 16.4")]),
    Design(id: "05-takeaway", title: "05  外带纸杯", note: "纵向收口与杯盖，换一种更轻快的咖啡形象。",
           bodies: ["M 6 6.5 L 18 6.5 L 16 16 L 8 16 Z", "M 4.5 3.4 L 6.5 3.4 L 7.5 1.5 L 16.5 1.5 L 17.5 3.4 L 19.5 3.4 L 19.5 4.5 L 4.5 4.5 Z"],
           strokes: []),
    Design(id: "06-moka-pot", title: "06  小摩卡壶", note: "有棱角的壶身与侧把手，辨识度更强的方向。",
           bodies: ["M 6.5 6.4 L 18 6.4 L 16 11.6 L 18 16.3 L 6 16.3 L 8.2 11.6 Z", "M 6.5 4.6 L 10 2.8 L 14.6 2.8 L 18 4.6 Z", "M 10.8 0.8 L 13.8 0.8 L 13.8 2 L 10.8 2 Z"],
           strokes: [Stroke(path: "M 18 7.1 L 21 6.4 C 24.2 6.1 24.4 10.8 21 11.4 L 17 12", width: 1.6), Stroke(path: "M 6.7 7.7 L 2.8 5.9 L 4.6 10.8 L 7.4 11.7", width: 1.4)]),
    Design(id: "07-native-system-cup", title: "07  原生咖啡杯", note: "原生系统符号：椭圆杯口、圆润杯身与完整杯碟。",
           bodies: [], strokes: [], nativeSymbol: "cup.and.saucer")
]

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Design/MenuBarIcons")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let ink = NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.29, alpha: 1)
let blue = NSColor(srgbRed: 0, green: 168.0 / 255, blue: 1, alpha: 1)
let green = NSColor(calibratedRed: 0.02, green: 0.35, blue: 0.27, alpha: 1)

func bezier(_ data: String) -> NSBezierPath {
    let tokens = data.split(separator: " ").map(String.init)
    let result = NSBezierPath()
    var index = 0
    func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
    }
    while index < tokens.count {
        let operation = tokens[index]
        index += 1
        switch operation {
        case "M": result.move(to: NSPoint(x: number(), y: number()))
        case "L": result.line(to: NSPoint(x: number(), y: number()))
        case "C":
            let first = NSPoint(x: number(), y: number())
            let second = NSPoint(x: number(), y: number())
            let end = NSPoint(x: number(), y: number())
            result.curve(to: end, controlPoint1: first, controlPoint2: second)
        case "Z": result.close()
        default: fatalError("Unsupported path operation: \(operation)")
        }
    }
    return result
}

func draw(_ design: Design, in rect: NSRect, filled: Bool, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    if let symbol = design.nativeSymbol {
        let name = filled ? "\(symbol).fill" : symbol
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: filled ? .semibold : .regular)
            .applying(.init(hierarchicalColor: color))
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: design.title),
              let image = base.withSymbolConfiguration(configuration) else {
            fatalError("System symbol unavailable: \(name)")
        }
        image.isTemplate = false
        image.draw(in: rect)
        return
    }
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 25, y: -rect.height / 18)
    color.setFill()
    color.setStroke()
    for data in design.bodies {
        let path = bezier(data)
        path.lineWidth = 1.45
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if filled { path.fill() } else { path.stroke() }
    }
    for stroke in design.strokes {
        let path = bezier(stroke.path)
        path.lineWidth = stroke.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

func render(width: Int, height: Int, drawing: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for design in designs {
    for filled in [true, false] {
        let state = filled ? "filled" : "outline"
        let bodyAttributes = filled ? "fill=\"currentColor\"" : "fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.45\""
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"25\" height=\"18\" viewBox=\"0 0 25 18\" color=\"#404D4A\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><title>\(design.title) · \(state)</title>\n"
        for path in design.bodies { svg += "<path d=\"\(path)\" \(bodyAttributes)/>\n" }
        for stroke in design.strokes { svg += "<path d=\"\(stroke.path)\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"\(stroke.width)\"/>\n" }
        svg += "</svg>\n"
        // SF Symbols stay native; do not substitute an approximate editable SVG.
        if design.nativeSymbol == nil {
            try svg.write(to: root.appendingPathComponent("\(design.id)-\(state).svg"), atomically: true, encoding: .utf8)
        }
        for scale in [2, 8] {
            let data = render(width: 25 * scale, height: 18 * scale) {
                draw(design, in: NSRect(x: 0, y: 0, width: 25 * scale, height: 18 * scale), filled: filled, color: ink)
            }
            let suffix = scale == 2 ? "@2x" : "@8x"
            try data.write(to: root.appendingPathComponent("\(design.id)-\(state)\(suffix).png"))
        }
    }
}

let width = 1200
let height = 1304
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: CGFloat(height) - y - h, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 14, weight: NSFont.Weight = .regular, color: NSColor = .secondaryLabelColor) {
    text.draw(at: NSPoint(x: x, y: CGFloat(height) - y - size * 1.4), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
}
func icon(_ design: Design, _ x: CGFloat, _ y: CGFloat, scale: CGFloat, filled: Bool, color: NSColor) {
    draw(design, in: NSRect(x: x, y: CGFloat(height) - y - 18 * scale, width: 25 * scale, height: 18 * scale), filled: filled, color: color)
}

let sheet = render(width: width, height: height) {
    box(0, 0, CGFloat(width), CGFloat(height), NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.94, alpha: 1))
    label("醒咖 · 菜单栏图标探索", 32, 22, size: 28, weight: .semibold, color: ink)
    label("7 款无蒸汽方案 · 放大轮廓 + 25 × 18 实际尺寸 · 实心运行 / 空心关闭", 32, 68, size: 15)
    for (index, design) in designs.enumerated() {
        let x = CGFloat(index % 2) * 584 + 24
        let y = CGFloat(index / 2) * 284 + 114
        box(x, y, 568, 268, .white, radius: 20)
        label(design.title, x + 22, y + 16, size: 21, weight: .semibold, color: ink)
        label(design.note, x + 22, y + 51, size: 13)

        box(x + 22, y + 87, 166, 144, green, radius: 16)
        icon(design, x + 44, y + 113, scale: 5, filled: true, color: blue)

        label("菜单栏实际尺寸（1×）", x + 214, y + 84, size: 12, weight: .medium)
        box(x + 214, y + 111, 330, 36, green, radius: 9)
        icon(design, x + 233, y + 120, scale: 1, filled: true, color: blue)
        icon(design, x + 287, y + 120, scale: 1, filled: false, color: NSColor(calibratedWhite: 0.96, alpha: 1))
        label("运行       关闭", x + 333, y + 119, size: 12, color: NSColor(calibratedWhite: 0.93, alpha: 1))

        label("浅色界面 · 默认蓝色 / 单色", x + 214, y + 165, size: 12, weight: .medium)
        icon(design, x + 232, y + 195, scale: 1.5, filled: true, color: blue)
        icon(design, x + 303, y + 195, scale: 1.5, filled: false, color: ink)
        label("1.5× 对比", x + 374, y + 200, size: 12)
    }
    label("01—06 提供可编辑 SVG；07 使用原生 SF Symbols 原生渲染。全部提供实心 / 空心透明 PNG。", 32, 1268, size: 13)
}
try sheet.write(to: root.appendingPathComponent("comparison.png"))
print("Exported \(designs.count) designs, filled/outline SVG and transparent PNG, plus comparison.png")

let nativeCup = designs.last!
let nativePreview = render(width: 900, height: 300) {
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 900, height: 300).fill()
    "07  原生咖啡杯".draw(at: NSPoint(x: 28, y: 250), withAttributes: [
        .font: NSFont.systemFont(ofSize: 23, weight: .semibold), .foregroundColor: ink
    ])
    green.setFill()
    NSBezierPath(roundedRect: NSRect(x: 28, y: 58, width: 440, height: 172), xRadius: 16, yRadius: 16).fill()
    draw(nativeCup, in: NSRect(x: 62, y: 107, width: 140, height: 100), filled: true, color: blue)
    draw(nativeCup, in: NSRect(x: 270, y: 107, width: 140, height: 100), filled: false, color: blue)
    for (title, x) in [("实心 · 运行", CGFloat(92)), ("空心 · 关闭", CGFloat(302))] {
        title.draw(at: NSPoint(x: x, y: 76), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white
        ])
    }
    "实际菜单栏尺寸 25 × 18".draw(at: NSPoint(x: 510, y: 191), withAttributes: [
        .font: NSFont.systemFont(ofSize: 15), .foregroundColor: ink
    ])
    green.setFill()
    NSBezierPath(roundedRect: NSRect(x: 510, y: 130, width: 340, height: 42), xRadius: 9, yRadius: 9).fill()
    draw(nativeCup, in: NSRect(x: 535, y: 142, width: 25, height: 18), filled: true, color: blue)
    draw(nativeCup, in: NSRect(x: 599, y: 142, width: 25, height: 18), filled: false, color: blue)
    "cup.and.saucer.fill / cup.and.saucer".draw(at: NSPoint(x: 510, y: 92), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor
    ])
    "椭圆杯口和完整杯碟；颜色仍可自定义。".draw(at: NSPoint(x: 28, y: 20), withAttributes: [
        .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor
    ])
}
try nativePreview.write(to: root.appendingPathComponent("07-native-preview.png"))
