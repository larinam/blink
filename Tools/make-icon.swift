import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let rect = NSRect(x: p * 0.035, y: p * 0.035, width: p * 0.93, height: p * 0.93)
        let background = NSBezierPath(roundedRect: rect, xRadius: p * 0.22, yRadius: p * 0.22)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.42, blue: 0.36, alpha: 1), ending: NSColor(srgbRed: 0.07, green: 0.23, blue: 0.21, alpha: 1))!
        gradient.draw(in: background, angle: -55)
        NSColor(srgbRed: 0.84, green: 0.95, blue: 0.85, alpha: 1).setStroke()
        let eye = NSBezierPath()
        eye.move(to: NSPoint(x: p * 0.20, y: p * 0.51))
        eye.curve(to: NSPoint(x: p * 0.80, y: p * 0.51), controlPoint1: NSPoint(x: p * 0.37, y: p * 0.76), controlPoint2: NSPoint(x: p * 0.64, y: p * 0.76))
        eye.curve(to: NSPoint(x: p * 0.20, y: p * 0.51), controlPoint1: NSPoint(x: p * 0.63, y: p * 0.26), controlPoint2: NSPoint(x: p * 0.36, y: p * 0.26))
        eye.lineWidth = p * 0.048
        eye.lineCapStyle = .round
        eye.stroke()
        NSColor(srgbRed: 0.87, green: 0.97, blue: 0.85, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: p * 0.421, y: p * 0.421, width: p * 0.158, height: p * 0.158)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
