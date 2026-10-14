import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let path = NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 210, yRadius: 210)
        NSGradient(colors: [NSColor(red: 0.85, green: 0.40, blue: 0.98, alpha: 1), NSColor(red: 0.39, green: 0.12, blue: 0.74, alpha: 1)])!.draw(in: path, angle: -65)
        let screen = NSBezierPath(roundedRect: NSRect(x: 210, y: 300, width: 604, height: 425), xRadius: 58, yRadius: 58)
        NSGradient(colors: [NSColor(red: 1, green: 0.82, blue: 0.97, alpha: 1), NSColor(red: 0.96, green: 0.45, blue: 0.81, alpha: 1)])!.draw(in: screen, angle: -60)
        NSColor.white.withAlphaComponent(0.75).setStroke(); screen.lineWidth = 12; screen.stroke()
        NSColor(red: 0.91, green: 0.81, blue: 1, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 443, y: 228, width: 138, height: 80), xRadius: 12, yRadius: 12).fill()
        NSBezierPath(roundedRect: NSRect(x: 350, y: 210, width: 324, height: 25), xRadius: 12, yRadius: 12).fill()
        func sparkle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            let star = NSBezierPath(); star.move(to: NSPoint(x: x, y: y + radius))
            star.curve(to: NSPoint(x: x + radius, y: y), controlPoint1: NSPoint(x: x + radius * 0.18, y: y + radius * 0.18), controlPoint2: NSPoint(x: x + radius * 0.18, y: y + radius * 0.18))
            star.curve(to: NSPoint(x: x, y: y - radius), controlPoint1: NSPoint(x: x + radius * 0.18, y: y - radius * 0.18), controlPoint2: NSPoint(x: x + radius * 0.18, y: y - radius * 0.18))
            star.curve(to: NSPoint(x: x - radius, y: y), controlPoint1: NSPoint(x: x - radius * 0.18, y: y - radius * 0.18), controlPoint2: NSPoint(x: x - radius * 0.18, y: y - radius * 0.18))
            star.curve(to: NSPoint(x: x, y: y + radius), controlPoint1: NSPoint(x: x - radius * 0.18, y: y + radius * 0.18), controlPoint2: NSPoint(x: x - radius * 0.18, y: y + radius * 0.18)); star.close(); NSColor.white.setFill(); star.fill()
        }
        sparkle(670, 650, 112); sparkle(390, 455, 57); sparkle(805, 805, 43)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try canvas.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let json: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Contents.json"))
print("Generated native app icon")
