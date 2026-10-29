import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let s = CGFloat(pixels)
        NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88), xRadius: s*0.20, yRadius: s*0.20).fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: s*0.20, y: s*0.28, width: s*0.60, height: s*0.51), xRadius: s*0.12, yRadius: s*0.12).fill()
        NSColor(calibratedRed: 0.39, green: 0.95, blue: 0.77, alpha: 1).setStroke()
        let chevron = NSBezierPath(); chevron.lineWidth = s*0.045; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
        chevron.move(to: NSPoint(x: s*0.32, y: s*0.61)); chevron.line(to: NSPoint(x: s*0.43, y: s*0.51)); chevron.line(to: NSPoint(x: s*0.32, y: s*0.41)); chevron.stroke()
        let cursor = NSBezierPath(); cursor.lineWidth = s*0.04; cursor.lineCapStyle = .round
        cursor.move(to: NSPoint(x: s*0.52, y: s*0.41)); cursor.line(to: NSPoint(x: s*0.65, y: s*0.41)); cursor.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
