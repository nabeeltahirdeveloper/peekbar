import Foundation

/// Identifies one numeric series (for history buffers, widgets and alert rules).
public struct MetricKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public var module: ModuleID
    public var metric: String
    public init(module: ModuleID, metric: String) { self.module = module; self.metric = metric }
    public var description: String { "\(module.rawValue).\(metric)" }

    public static let cpuTotal = MetricKey(module: .cpu, metric: "total")
    public static let cpuTemperature = MetricKey(module: .cpu, metric: "temperature")
    public static let ramUsed = MetricKey(module: .ram, metric: "usedFraction")
    public static let diskUsed = MetricKey(module: .disk, metric: "usedFraction")
    public static let diskRead = MetricKey(module: .disk, metric: "read")
    public static let diskWrite = MetricKey(module: .disk, metric: "write")
    public static let networkDown = MetricKey(module: .network, metric: "down")
    public static let networkUp = MetricKey(module: .network, metric: "up")
    public static let batteryLevel = MetricKey(module: .battery, metric: "level")
    public static let batteryTemperature = MetricKey(module: .battery, metric: "temperature")
    public static let gpuUtilization = MetricKey(module: .gpu, metric: "utilization")
    public static let gpuTemperature = MetricKey(module: .gpu, metric: "temperature")
    public static func sensor(_ key: String) -> MetricKey { MetricKey(module: .sensors, metric: key) }

    /// Human labels for rule pickers.
    public var title: String {
        switch (module, metric) {
        case (.cpu, "total"): return "CPU load"
        case (.cpu, "temperature"): return "CPU temperature"
        case (.ram, "usedFraction"): return "Memory used"
        case (.disk, "usedFraction"): return "Disk used"
        case (.disk, "read"): return "Disk read rate"
        case (.disk, "write"): return "Disk write rate"
        case (.network, "down"): return "Download rate"
        case (.network, "up"): return "Upload rate"
        case (.battery, "level"): return "Battery level"
        case (.battery, "temperature"): return "Battery temperature"
        case (.gpu, "utilization"): return "GPU load"
        case (.gpu, "temperature"): return "GPU temperature"
        case (.sensors, let k): return "Sensor \(k)"
        default: return description
        }
    }

    /// Whether the series is a 0–1 fraction (shown as percent) or an absolute value.
    public var isFraction: Bool {
        ["total", "usedFraction", "level", "utilization"].contains(metric)
    }

    /// Series worth alerting on, in picker order.
    public static let alertable: [MetricKey] = [
        .cpuTotal, .cpuTemperature, .ramUsed, .diskUsed, .networkDown, .networkUp, .batteryLevel, .batteryTemperature, .gpuUtilization, .gpuTemperature,
    ]
}
