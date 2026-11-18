import AppKit

precondition(CommandLine.arguments.count == 2, "Expected an iconset output directory")
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        context.cgContext.setShouldAntialias(true)

        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 192, yRadius: 192)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        background.fill()

        NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
        let sun = NSBezierPath(ovalIn: NSRect(x: 359, y: 359, width: 306, height: 306))
        sun.lineWidth = 34
        sun.stroke()
        let rays = NSBezierPath()
        rays.lineWidth = 34
        rays.lineCapStyle = .round
        for ray in 0..<8 {
            let angle = Double(ray) * .pi / 4
            rays.move(to: NSPoint(x: 512 + 225 * cos(angle), y: 512 + 225 * sin(angle)))
            rays.line(to: NSPoint(x: 512 + 315 * cos(angle), y: 512 + 315 * sin(angle)))
        }
        rays.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
