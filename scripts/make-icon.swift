// Renders the Cermin app icon (design §06) into an .iconset folder.
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body, continuous corners.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    shape.fill()
    ctx.restoreGState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.37, green: 0.75, blue: 0.74, alpha: 1),
                        NSColor(srgbRed: 0.0, green: 0.47, blue: 0.48, alpha: 1)])!.draw(in: body, angle: -90)

    // Two phones: the real one and its reflection, split by a thin "mirror" line.
    let pw = body.width * 0.25, ph = pw * 2.05, gap = body.width * 0.04
    let y = body.midY - ph / 2
    let left = CGRect(x: body.midX - gap / 2 - pw, y: y, width: pw, height: ph)
    let right = CGRect(x: body.midX + gap / 2, y: y, width: pw, height: ph)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: left, xRadius: pw * 0.2, yRadius: pw * 0.2).fill()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0.25)])!
        .draw(in: NSBezierPath(roundedRect: right, xRadius: pw * 0.2, yRadius: pw * 0.2), angle: 0)
    NSColor.white.withAlphaComponent(0.55).setFill()
    NSBezierPath(rect: CGRect(x: body.midX - s * 0.0015, y: y - ph * 0.08, width: max(1, s * 0.003), height: ph * 1.16)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("wrote \(out.path)")
