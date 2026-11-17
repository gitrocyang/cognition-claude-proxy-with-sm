import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let assetDirectory = root.appendingPathComponent("macos/DevinProxyManager/Resources")
let menuDirectory = root.appendingPathComponent("macos/DevinProxyManager/Sources/DevinProxyManager/Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("DevinProxyManager-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func glyph(outer: NSColor, arrow: NSColor) {
    let d = NSBezierPath()
    d.move(to: NSPoint(x: 255, y: 240))
    d.line(to: NSPoint(x: 255, y: 784))
    d.line(to: NSPoint(x: 440, y: 784))
    d.curve(to: NSPoint(x: 790, y: 512), controlPoint1: NSPoint(x: 655, y: 784), controlPoint2: NSPoint(x: 790, y: 675))
    d.curve(to: NSPoint(x: 440, y: 240), controlPoint1: NSPoint(x: 790, y: 350), controlPoint2: NSPoint(x: 655, y: 240))
    d.close()
    d.lineWidth = 105
    d.lineCapStyle = .round
    d.lineJoinStyle = .round
    outer.setStroke()
    d.stroke()

    let transfer = NSBezierPath()
    transfer.move(to: NSPoint(x: 405, y: 512))
    transfer.line(to: NSPoint(x: 650, y: 512))
    transfer.move(to: NSPoint(x: 560, y: 595))
    transfer.line(to: NSPoint(x: 650, y: 512))
    transfer.line(to: NSPoint(x: 560, y: 429))
    transfer.lineWidth = 80
    transfer.lineCapStyle = .round
    transfer.lineJoinStyle = .round
    arrow.setStroke()
    transfer.stroke()
}

func png(size: Int, menu: Bool) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSAffineTransform(transform: AffineTransform(scaleByX: CGFloat(size) / 1024, byY: CGFloat(size) / 1024)).concat()
    if !menu {
        let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
        background.addClip()
        NSGradient(starting: NSColor(srgbRed: 0.035, green: 0.105, blue: 0.18, alpha: 1),
                   ending: NSColor(srgbRed: 0.025, green: 0.34, blue: 0.41, alpha: 1))!
            .draw(in: background, angle: -45)
        NSColor(srgbRed: 0.21, green: 0.84, blue: 0.78, alpha: 0.10).setFill()
        NSBezierPath(ovalIn: NSRect(x: 420, y: 520, width: 560, height: 560)).fill()
        glyph(outer: .white, arrow: NSColor(srgbRed: 0.29, green: 0.91, blue: 0.80, alpha: 1))
    } else {
        glyph(outer: .black, arrow: .black)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

try png(size: 64, menu: true).write(to: menuDirectory.appendingPathComponent("MenuGlyph.png"))
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (size, name) in sizes { try png(size: size, menu: false).write(to: iconset.appendingPathComponent(name)) }
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", assetDirectory.appendingPathComponent("DevinProxyManager.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
