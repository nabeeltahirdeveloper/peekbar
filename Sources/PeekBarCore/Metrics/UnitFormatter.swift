import Foundation

public enum ByteStyle: String, Codable, CaseIterable, Sendable {
    case binary, decimal
    public var title: String { self == .binary ? "Binary (GiB)" : "Decimal (GB)" }
}

public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius, fahrenheit
    public var title: String { self == .celsius ? "Celsius" : "Fahrenheit" }
}

/// Human-readable values. Locale-independent digits so widgets stay a fixed width.
public enum UnitFormatter {
    private static let binaryUnits = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
    private static let decimalUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func bytes(_ value: UInt64, style: ByteStyle = .binary, decimals: Int? = nil) -> String {
        bytes(Double(value), style: style, decimals: decimals)
    }

    public static func bytes(_ value: Double, style: ByteStyle = .binary, decimals: Int? = nil) -> String {
        let base: Double = style == .binary ? 1024 : 1000
        let units = style == .binary ? binaryUnits : decimalUnits
        var v = max(0, value)
        var i = 0
        while v >= base && i < units.count - 1 { v /= base; i += 1 }
        let d = decimals ?? (i == 0 ? 0 : (v < 10 ? 2 : (v < 100 ? 1 : 0)))
        return String(format: "%.\(d)f %@", v, units[i])
    }

    /// "1.2 MB/s"
    public static func rate(bytesPerSecond: Double, style: ByteStyle = .decimal) -> String {
        bytes(bytesPerSecond, style: style) + "/s"
    }

    /// Compact rate for widgets: "1.2M" style, at most 5 characters before the unit.
    public static func compactRate(bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        let units = ["B", "K", "M", "G", "T"]
        var x = v; var i = 0
        while x >= 1000 && i < units.count - 1 { x /= 1000; i += 1 }
        if i == 0 { return String(format: "%.0f %@", x, units[i]) }
        return String(format: x < 10 ? "%.1f %@" : "%.0f %@", x, units[i])
    }

    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", min(max(fraction, 0), 9.99) * 100)
    }

    public static func temperature(_ celsius: Double, unit: TemperatureUnit, decimals: Int = 0) -> String {
        switch unit {
        case .celsius: return String(format: "%.\(decimals)f°C", celsius)
        case .fahrenheit: return String(format: "%.\(decimals)f°F", celsius * 9 / 5 + 32)
        }
    }

    /// "2h 15m", "45m", "<1m"
    public static func duration(minutes: Int) -> String {
        if minutes <= 0 { return "<1m" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    public static func power(watts: Double) -> String {
        String(format: watts < 10 ? "%.1f W" : "%.0f W", watts)
    }

    public static func rpm(_ value: Double) -> String { String(format: "%.0f rpm", value) }
}
