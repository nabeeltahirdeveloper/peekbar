import AppKit

// Draws the PeekBar app icon: a menu-bar-blue rounded square with a white "tray" glyph.
func draw(size: Int, to url: URL) {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        let inset = s * 0.06
        let r = rect.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: r, xRadius: s * 0.22, yRadius: s * 0.22)
        let grad = NSGradient(colors: [NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.95, alpha: 1),
                                       NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.85, alpha: 1)])!
        grad.draw(in: path, angle: -60)
        // Menu bar band
        let bandH = s * 0.16
        let band = NSBezierPath(roundedRect: NSRect(x: r.minX + s * 0.10, y: r.maxY - s * 0.14 - bandH, width: r.width - s * 0.20, height: bandH), xRadius: bandH * 0.3, yRadius: bandH * 0.3)
        NSColor.white.withAlphaComponent(0.25).setFill(); band.fill()
        // Notch
        let notchW = s * 0.18
        let notch = NSBezierPath(roundedRect: NSRect(x: r.midX - notchW / 2, y: r.maxY - s * 0.14 - bandH * 0.62, width: notchW, height: bandH * 0.62), xRadius: bandH * 0.18, yRadius: bandH * 0.18)
        NSColor(calibratedWhite: 0.05, alpha: 0.85).setFill(); notch.fill()
        // Popup with tiles
        let popW = s * 0.50, popH = s * 0.40
        let pop = NSBezierPath(roundedRect: NSRect(x: r.maxX - s * 0.10 - popW, y: r.maxY - s * 0.14 - bandH - s * 0.06 - popH, width: popW, height: popH), xRadius: s * 0.07, yRadius: s * 0.07)
        NSColor.white.withAlphaComponent(0.92).setFill(); pop.fill()
        let tile = s * 0.11, gap = s * 0.035
        let originX = r.maxX - s * 0.10 - popW + gap * 1.4
        let originY = r.maxY - s * 0.14 - bandH - s * 0.06 - popH + gap * 1.4
        for row in 0..<2 { for col in 0..<3 {
            let t = NSBezierPath(roundedRect: NSRect(x: originX + CGFloat(col) * (tile + gap), y: originY + CGFloat(row) * (tile + gap), width: tile, height: tile), xRadius: tile * 0.25, yRadius: tile * 0.25)
            NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.95, alpha: 0.9 - CGFloat(row) * 0.25).setFill(); t.fill()
        } }
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    draw(size: size, to: out.appendingPathComponent("\(name).png"))
}
