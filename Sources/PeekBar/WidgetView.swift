import AppKit
import PeekBarCore

/// What a widget draws. Built from `MetricsStore` by `WidgetController`.
struct WidgetData: Equatable {
    var fraction: Double?          // 0–1 primary load
    var text: String = "–"         // mini / label text
    var downText: String = ""      // speed
    var upText: String = ""
    var series: [Double] = []
    var seriesRange: ClosedRange<Double>? = 0...1
    var perCore: [Double] = []
    var batteryLevel: Double?
    var charging = false
    var unavailable = false
    var shortLabel = ""            // "CPU", "RAM" … when showLabel is on
}

/// Draws one Stats-style widget inside a status item button. Clicks fall through to the
/// button (`hitTest` returns nil) so native ⌘-drag reordering keeps working.
final class WidgetView: NSView {
    var config: WidgetConfig { didSet { needsDisplay = true } }
    var data = WidgetData() { didSet { if data != oldValue { needsDisplay = true } } }

    init(config: WidgetConfig) {
        self.config = config
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { false }

    private var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    private var lineWidth: CGFloat { increaseContrast ? 2 : 1.5 }

    private var ink: NSColor { NSColor.labelColor.withAlphaComponent(data.unavailable ? 0.4 : 1) }
    private var faint: NSColor { NSColor.labelColor.withAlphaComponent(increaseContrast ? 0.35 : 0.18) }

    private func loadColor(_ fraction: Double) -> NSColor {
        guard config.colorMode == .utilization else { return ink }
        switch WidgetLayoutMath.loadColor(fraction) {
        case .normal: return NSColor.systemGreen
        case .elevated: return NSColor.systemYellow
        case .high: return NSColor.systemRed
        }
    }

    private func font(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat = 10, weight: NSFont.Weight = .medium, align: NSTextAlignment = .center, color: NSColor? = nil) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [.font: font(size, weight: weight), .foregroundColor: color ?? ink, .paragraphStyle: style]
        let h = (text as NSString).size(withAttributes: attrs).height
        let r = NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        (text as NSString).draw(in: r, withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        var area = bounds.insetBy(dx: 2, dy: 3)
        if config.showLabel, !data.shortLabel.isEmpty {
            let labelRect = NSRect(x: area.minX, y: area.minY, width: 16, height: area.height)
            drawText(data.shortLabel, in: labelRect, size: 7, weight: .semibold, align: .left, color: NSColor.secondaryLabelColor)
            area.origin.x += 16
            area.size.width -= 16
        }
        if data.unavailable {
            drawText("–", in: area, size: 11, color: ink)
            return
        }
        switch config.style {
        case .mini: drawMini(area)
        case .lineChart: drawLineChart(area)
        case .barChart: drawBarChart(area)
        case .ring: drawRing(area)
        case .tachometer: drawTachometer(area)
        case .label: drawText(data.text, in: area, size: 11, align: .center)
        case .speed: drawSpeed(area)
        case .battery: drawBattery(area)
        case .memoryBar: drawMemoryBar(area)
        case .stateDot:
            let d: CGFloat = 8
            let r = NSRect(x: area.midX - d / 2, y: area.midY - d / 2, width: d, height: d)
            loadColorOrGreen(data.fraction ?? 0).setFill()
            NSBezierPath(ovalIn: r).fill()
        }
    }

    private func loadColorOrGreen(_ f: Double) -> NSColor {
        switch WidgetLayoutMath.loadColor(f) {
        case .normal: return .systemGreen
        case .elevated: return .systemYellow
        case .high: return .systemRed
        }
    }

    // MARK: Styles

    private func drawMini(_ area: NSRect) {
        // Icon-sized label on top, small bar underneath.
        let textRect = NSRect(x: area.minX, y: area.midY - 1, width: area.width, height: area.height / 2 + 1)
        drawText(data.text, in: textRect, size: 9.5, weight: .semibold)
        let f = CGFloat(min(1, max(0, data.fraction ?? 0)))
        let bar = NSRect(x: area.minX + 4, y: area.minY + 2, width: area.width - 8, height: 3)
        faint.setFill(); NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        loadColor(Double(f)).setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: max(2, bar.width * f), height: bar.height), xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func drawLineChart(_ area: NSRect) {
        let box = NSBezierPath(roundedRect: area, xRadius: 2, yRadius: 2)
        faint.withAlphaComponent(0.12).setFill(); box.fill()
        let n = WidgetLayoutMath.chartPointCount(width: area.width)
        let points = Array(data.series.suffix(n))
        guard points.count >= 2 else { return }
        let lo = data.seriesRange?.lowerBound ?? (points.min() ?? 0)
        let hiRaw = data.seriesRange?.upperBound ?? (points.max() ?? 1)
        let hi = hiRaw > lo ? hiRaw : lo + 1
        let stepX = area.width / CGFloat(n - 1)
        let path = NSBezierPath()
        let startX = area.minX + area.width - stepX * CGFloat(points.count - 1)
        for (i, v) in points.enumerated() {
            let y = area.minY + 1 + CGFloat((v - lo) / (hi - lo)) * (area.height - 2)
            let p = NSPoint(x: startX + stepX * CGFloat(i), y: y)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        let fill = path.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: area.maxX, y: area.minY))
        fill.line(to: NSPoint(x: startX, y: area.minY))
        fill.close()
        let color = loadColor(points.last ?? 0)
        color.withAlphaComponent(0.25).setFill(); fill.fill()
        color.setStroke(); path.lineWidth = lineWidth; path.stroke()
    }

    private func drawBarChart(_ area: NSRect) {
        let cores = data.perCore
        guard !cores.isEmpty else { return }
        let gap: CGFloat = 1
        let barW = max(1, (area.width - 6 - gap * CGFloat(cores.count - 1)) / CGFloat(cores.count))
        var x = area.minX + 3
        for v in cores {
            let h = max(1.5, (area.height - 2) * CGFloat(min(1, max(0, v))))
            faint.setFill(); NSBezierPath(rect: NSRect(x: x, y: area.minY + 1, width: barW, height: area.height - 2)).fill()
            loadColor(v).setFill(); NSBezierPath(rect: NSRect(x: x, y: area.minY + 1, width: barW, height: h)).fill()
            x += barW + gap
        }
    }

    private func drawRing(_ area: NSRect) {
        let d = min(area.width, area.height) - 2
        let rect = NSRect(x: area.midX - d / 2, y: area.midY - d / 2, width: d, height: d)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth + 0.5
        faint.setStroke(); track.stroke()
        let f = CGFloat(min(1, max(0, data.fraction ?? 0)))
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: d / 2, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
        arc.lineWidth = lineWidth + 0.5
        arc.lineCapStyle = .round
        loadColor(Double(f)).setStroke(); arc.stroke()
    }

    private func drawTachometer(_ area: NSRect) {
        let r = min(area.width / 2, area.height) - 1
        let c = NSPoint(x: area.midX, y: area.minY + 2)
        let track = NSBezierPath()
        track.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: 0, clockwise: true)
        track.lineWidth = lineWidth + 0.5; track.lineCapStyle = .round
        faint.setStroke(); track.stroke()
        let f = CGFloat(min(1, max(0, data.fraction ?? 0)))
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: 180 - 180 * f, clockwise: true)
        arc.lineWidth = lineWidth + 0.5; arc.lineCapStyle = .round
        loadColor(Double(f)).setStroke(); arc.stroke()
        // Needle
        let angle = (180 - 180 * f) * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: c)
        needle.line(to: NSPoint(x: c.x + cos(angle) * (r - 3), y: c.y + sin(angle) * (r - 3)))
        needle.lineWidth = 1.2
        ink.setStroke(); needle.stroke()
    }

    private func drawSpeed(_ area: NSRect) {
        let half = area.height / 2
        let top = NSRect(x: area.minX, y: area.midY, width: area.width, height: half)
        let bottom = NSRect(x: area.minX, y: area.minY, width: area.width, height: half)
        drawText("↓ " + data.downText, in: top, size: 8, weight: .semibold, align: .left)
        drawText("↑ " + data.upText, in: bottom, size: 8, weight: .semibold, align: .left)
    }

    private func drawBattery(_ area: NSRect) {
        let level = CGFloat(min(1, max(0, data.batteryLevel ?? 0)))
        let bodyW: CGFloat = 22, bodyH: CGFloat = 11
        let body = NSRect(x: area.midX - bodyW / 2 - 1, y: area.midY - bodyH / 2, width: bodyW, height: bodyH)
        let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        ink.withAlphaComponent(0.6).setStroke(); outline.stroke()
        let nub = NSRect(x: body.maxX + 1, y: body.midY - 2, width: 1.5, height: 4)
        ink.withAlphaComponent(0.6).setFill(); NSBezierPath(roundedRect: nub, xRadius: 0.5, yRadius: 0.5).fill()
        let inner = body.insetBy(dx: 2, dy: 2)
        let fillColor: NSColor = level <= 0.2 ? .systemRed : (data.charging ? .systemGreen : ink)
        fillColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: max(1, inner.width * level), height: inner.height), xRadius: 1, yRadius: 1).fill()
        if data.charging {
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: body.midX + 1, y: body.maxY - 1))
            bolt.line(to: NSPoint(x: body.midX - 2, y: body.midY))
            bolt.line(to: NSPoint(x: body.midX + 0.5, y: body.midY))
            bolt.line(to: NSPoint(x: body.midX - 1, y: body.minY + 1))
            bolt.line(to: NSPoint(x: body.midX + 2, y: body.midY))
            bolt.line(to: NSPoint(x: body.midX - 0.5, y: body.midY))
            bolt.close()
            NSColor.labelColor.setFill(); bolt.fill()
        }
    }

    private func drawMemoryBar(_ area: NSRect) {
        let bar = NSRect(x: area.minX + 2, y: area.midY - 4, width: area.width - 4, height: 8)
        let outline = NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2)
        outline.lineWidth = 1
        ink.withAlphaComponent(0.6).setStroke(); outline.stroke()
        let f = CGFloat(min(1, max(0, data.fraction ?? 0)))
        loadColor(Double(f)).setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX + 1.5, y: bar.minY + 1.5, width: max(1, (bar.width - 3) * f), height: bar.height - 3), xRadius: 1, yRadius: 1).fill()
    }
}
