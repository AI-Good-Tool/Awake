import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/AwakeIcon.iconset")
let sourceURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "Assets/Brand/AppIcon.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("Cannot load app icon: \(sourceURL.path)")
}
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: item.pixels,
        pixelsHigh: item.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create icon bitmap")
    }
    bitmap.size = NSSize(width: item.pixels, height: item.pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: item.pixels, height: item.pixels),
                from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon PNG")
    }
    try data.write(to: outputURL.appendingPathComponent(item.name))
}
