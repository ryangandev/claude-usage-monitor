// Draws Resources/AppIcon.icns: the menu bar ring, large, on an indigo tile.
//   swift make-icon.swift
import AppKit

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // The tile sits inside the grid macOS icons use: 824 of 1024 with rounded corners.
    let tile = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(srgbRed: 0.42, green: 0.47, blue: 0.88, alpha: 1),
               ending: NSColor(srgbRed: 0.33, green: 0.37, blue: 0.78, alpha: 1))!.draw(in: path, angle: -90)
    let c = NSPoint(x: s / 2, y: s / 2), r = s * 0.24, w = s * 0.075
    let track = NSBezierPath()
    track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
    track.lineWidth = w
    NSColor.white.withAlphaComponent(0.28).setStroke()
    track.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * 0.62, clockwise: true)
    arc.lineWidth = w
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", here.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
print("wrote Resources/AppIcon.icns")
