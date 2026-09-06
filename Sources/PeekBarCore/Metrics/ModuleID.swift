import Foundation

/// The monitoring modules (Stats parity minus fan control).
public enum ModuleID: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case cpu, ram, disk, network, battery, gpu, sensors, bluetooth, clock

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .ram: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .battery: return "Battery"
        case .gpu: return "GPU"
        case .sensors: return "Sensors"
        case .bluetooth: return "Bluetooth"
        case .clock: return "Clock"
        }
    }

    /// SF Symbol used on cards and widgets.
    public var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .ram: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.75"
        case .gpu: return "rectangle.3.group"
        case .sensors: return "thermometer"
        case .bluetooth: return "wave.3.right"
        case .clock: return "clock"
        }
    }

    /// Stats-like default sampling intervals.
    public var defaultInterval: TimeInterval {
        switch self {
        case .cpu, .network, .clock: return 1
        case .ram, .disk, .gpu, .sensors: return 2
        case .battery: return 10
        case .bluetooth: return 30
        }
    }

    /// Modules enabled on a fresh install.
    public static let defaultEnabled: [ModuleID] = [.cpu, .ram, .disk, .network, .battery]

    private var order: Int { ModuleID.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: ModuleID, rhs: ModuleID) -> Bool { lhs.order < rhs.order }
}
