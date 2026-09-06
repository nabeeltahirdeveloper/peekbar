import Foundation
import CoreGraphics

/// Stats-style menu bar widget looks.
public enum WidgetStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case mini, lineChart, barChart, ring, tachometer, label, speed, battery, memoryBar, stateDot
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mini: return "Mini"
        case .lineChart: return "Line chart"
        case .barChart: return "Bar chart"
        case .ring: return "Ring"
        case .tachometer: return "Tachometer"
        case .label: return "Label"
        case .speed: return "Speed"
        case .battery: return "Battery"
        case .memoryBar: return "Memory bar"
        case .stateDot: return "State dot"
        }
    }
}

public enum WidgetColorMode: String, Codable, CaseIterable, Sendable {
    case monochrome, utilization
    public var title: String { self == .monochrome ? "Monochrome" : "Color by load" }
}

public enum WidgetPlacement: String, Codable, Sendable { case pinned, hiddenByUser }

public struct WidgetConfig: Codable, Equatable, Identifiable, Sendable {
    public var module: ModuleID
    public var style: WidgetStyle
    public var showLabel: Bool
    public var colorMode: WidgetColorMode
    public var placement: WidgetPlacement
    public var chartWidth: Int
    public var id: String { module.rawValue }

    public init(module: ModuleID, style: WidgetStyle? = nil, showLabel: Bool = false, colorMode: WidgetColorMode = .monochrome, placement: WidgetPlacement = .pinned, chartWidth: Int = 44) {
        self.module = module
        self.style = style ?? WidgetLayoutMath.defaultStyle(for: module)
        self.showLabel = showLabel
        self.colorMode = colorMode
        self.placement = placement
        self.chartWidth = chartWidth
    }
}

public enum WidgetLayoutMath {
    public static let chartWidths = [32, 44, 60]

    public static func allowedStyles(for module: ModuleID) -> [WidgetStyle] {
        switch module {
        case .cpu: return [.mini, .lineChart, .barChart, .ring, .tachometer, .label, .stateDot]
        case .ram: return [.mini, .memoryBar, .lineChart, .ring, .label, .stateDot]
        case .disk: return [.mini, .ring, .speed, .lineChart, .label]
        case .network: return [.speed, .lineChart, .mini, .label]
        case .battery: return [.battery, .mini, .label]
        case .gpu: return [.mini, .lineChart, .ring, .tachometer, .label, .stateDot]
        case .sensors: return [.label, .mini]
        case .bluetooth: return [.mini, .label]
        case .clock: return [.label]
        }
    }

    public static func defaultStyle(for module: ModuleID) -> WidgetStyle {
        switch module {
        case .network: return .speed
        case .battery: return .battery
        case .clock, .sensors: return .label
        default: return .mini
        }
    }

    /// Fixed item length in points. Fixed so neighbours never reflow while values change.
    public static func width(for style: WidgetStyle, module: ModuleID, coreCount: Int, chartWidth: Int, showLabel: Bool) -> CGFloat {
        var w: CGFloat
        switch style {
        case .mini: w = 48
        case .lineChart: w = CGFloat(chartWidths.contains(chartWidth) ? chartWidth : 44)
        case .barChart:
            let cores = max(1, coreCount)
            w = min(60, CGFloat(cores * 2 + (cores - 1) + 6))
        case .ring: w = 18
        case .tachometer: w = 22
        case .label: w = module == .clock ? 64 : 80
        case .speed: w = 70
        case .battery: w = 26
        case .memoryBar: w = 30
        case .stateDot: w = 10
        }
        if showLabel { w += 16 }
        return w
    }

    /// One data point per 2 pt of chart width.
    public static func chartPointCount(width: CGFloat) -> Int {
        max(2, Int((width - 4) / 2))
    }

    /// Saved "Preferred Position" for a widget that should sit immediately right of the
    /// PeekBar icon. Larger values sit further left, so rank 0 is nearest the icon.
    public static func preferredPosition(togglePosition: CGFloat, rank: Int) -> CGFloat {
        max(1, togglePosition - 1 - CGFloat(rank))
    }

    /// Load → colour bucket for the "colour by load" mode.
    public enum LoadColor: Equatable { case normal, elevated, high }
    public static func loadColor(_ fraction: Double) -> LoadColor {
        if fraction >= 0.8 { return .high }
        if fraction >= 0.5 { return .elevated }
        return .normal
    }
}

/// Where a widget ended up relative to PeekBar's own items after a ⌘-drag.
public enum WidgetPlacementCheck {
    public enum Result: Equatable { case pinned, hidden, interleaved }

    public static func classify(widgetMinX: CGFloat, separatorMinX: CGFloat, separatorMaxX: CGFloat, toggleMinX: CGFloat) -> Result {
        if widgetMinX < separatorMinX { return .hidden }
        if widgetMinX >= separatorMaxX - 1 && widgetMinX < toggleMinX - 1 { return .interleaved }
        return .pinned
    }
}
