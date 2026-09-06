import Foundation

public struct ProcessUsage: Codable, Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var name: String
    /// CPU fraction (0–1) or bytes, depending on the module.
    public var value: Double
    public var id: Int32 { pid }
    public init(pid: Int32, name: String, value: Double) { self.pid = pid; self.name = name; self.value = value }
}

public struct CPUReading: Codable, Equatable, Sendable {
    /// Fractions 0–1.
    public var total: Double
    public var user: Double
    public var system: Double
    public var perCore: [Double]
    public var performanceCores: Double?
    public var efficiencyCores: Double?
    public var loadAverage: [Double]
    public var topProcesses: [ProcessUsage]
    public var temperature: Double?
    public init(total: Double, user: Double, system: Double, perCore: [Double], performanceCores: Double? = nil, efficiencyCores: Double? = nil, loadAverage: [Double] = [], topProcesses: [ProcessUsage] = [], temperature: Double? = nil) {
        self.total = total; self.user = user; self.system = system; self.perCore = perCore
        self.performanceCores = performanceCores; self.efficiencyCores = efficiencyCores
        self.loadAverage = loadAverage; self.topProcesses = topProcesses; self.temperature = temperature
    }
}

public enum MemoryPressure: String, Codable, Sendable { case normal, warning, critical }

public struct RAMReading: Codable, Equatable, Sendable {
    public var total: UInt64
    public var used: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure
    public var topProcesses: [ProcessUsage]
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    public init(total: UInt64, used: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64, free: UInt64, swapUsed: UInt64 = 0, swapTotal: UInt64 = 0, pressure: MemoryPressure = .normal, topProcesses: [ProcessUsage] = []) {
        self.total = total; self.used = used; self.app = app; self.wired = wired; self.compressed = compressed
        self.cached = cached; self.free = free; self.swapUsed = swapUsed; self.swapTotal = swapTotal
        self.pressure = pressure; self.topProcesses = topProcesses
    }
}

public struct DiskVolume: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var path: String
    public var total: UInt64
    public var available: UInt64
    public var isInternal: Bool
    public var isRemovable: Bool
    public var id: String { path }
    public var used: UInt64 { total >= available ? total - available : 0 }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    public init(name: String, path: String, total: UInt64, available: UInt64, isInternal: Bool, isRemovable: Bool) {
        self.name = name; self.path = path; self.total = total; self.available = available
        self.isInternal = isInternal; self.isRemovable = isRemovable
    }
}

public struct DiskReading: Codable, Equatable, Sendable {
    public var volumes: [DiskVolume]
    /// Bytes per second across all internal drives.
    public var readRate: Double
    public var writeRate: Double
    public var primary: DiskVolume? { volumes.first { $0.path == "/" } ?? volumes.first }
    public init(volumes: [DiskVolume], readRate: Double, writeRate: Double) {
        self.volumes = volumes; self.readRate = readRate; self.writeRate = writeRate
    }
}

public struct NetworkReading: Codable, Equatable, Sendable {
    public var interfaceName: String?
    public var interfaceType: String?
    public var downloadRate: Double
    public var uploadRate: Double
    public var totalDownloaded: UInt64
    public var totalUploaded: UInt64
    public var localIPv4: String?
    public var localIPv6: String?
    public var publicIP: String?
    public init(interfaceName: String? = nil, interfaceType: String? = nil, downloadRate: Double, uploadRate: Double, totalDownloaded: UInt64 = 0, totalUploaded: UInt64 = 0, localIPv4: String? = nil, localIPv6: String? = nil, publicIP: String? = nil) {
        self.interfaceName = interfaceName; self.interfaceType = interfaceType
        self.downloadRate = downloadRate; self.uploadRate = uploadRate
        self.totalDownloaded = totalDownloaded; self.totalUploaded = totalUploaded
        self.localIPv4 = localIPv4; self.localIPv6 = localIPv6; self.publicIP = publicIP
    }
}

public struct BatteryReading: Codable, Equatable, Sendable {
    /// 0–1.
    public var level: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var timeToEmptyMinutes: Int?
    public var timeToFullMinutes: Int?
    public var cycleCount: Int?
    /// Current max capacity divided by design capacity, 0–1.
    public var health: Double?
    public var temperature: Double?
    public var wattage: Double?
    public var adapterDescription: String?
    public init(level: Double, isCharging: Bool, isPluggedIn: Bool, timeToEmptyMinutes: Int? = nil, timeToFullMinutes: Int? = nil, cycleCount: Int? = nil, health: Double? = nil, temperature: Double? = nil, wattage: Double? = nil, adapterDescription: String? = nil) {
        self.level = level; self.isCharging = isCharging; self.isPluggedIn = isPluggedIn
        self.timeToEmptyMinutes = timeToEmptyMinutes; self.timeToFullMinutes = timeToFullMinutes
        self.cycleCount = cycleCount; self.health = health; self.temperature = temperature
        self.wattage = wattage; self.adapterDescription = adapterDescription
    }
}

public struct GPUReading: Codable, Equatable, Sendable {
    public var name: String
    public var utilization: Double?
    public var rendererUtilization: Double?
    public var tilerUtilization: Double?
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64?
    public var temperature: Double?
    public init(name: String, utilization: Double? = nil, rendererUtilization: Double? = nil, tilerUtilization: Double? = nil, memoryUsed: UInt64? = nil, memoryTotal: UInt64? = nil, temperature: Double? = nil) {
        self.name = name; self.utilization = utilization; self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization; self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal
        self.temperature = temperature
    }
}

public enum SensorGroup: String, Codable, Sendable, CaseIterable {
    case cpu, gpu, soc, memory, storage, battery, ambient, fan, power, voltage, current, other
    public var title: String {
        switch self {
        case .cpu: return "CPU"; case .gpu: return "GPU"; case .soc: return "System"; case .memory: return "Memory"
        case .storage: return "Storage"; case .battery: return "Battery"; case .ambient: return "Ambient"
        case .fan: return "Fans"; case .power: return "Power"; case .voltage: return "Voltage"
        case .current: return "Current"; case .other: return "Other"
        }
    }
}

public enum SensorUnit: String, Codable, Sendable { case celsius, rpm, watts, volts, amps, raw }

public struct SensorReading: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var group: SensorGroup
    public var value: Double
    public var unit: SensorUnit
    public var id: String { key }
    public init(key: String, label: String, group: SensorGroup, value: Double, unit: SensorUnit) {
        self.key = key; self.label = label; self.group = group; self.value = value; self.unit = unit
    }
}

public struct SensorsReading: Codable, Equatable, Sendable {
    public var sensors: [SensorReading]
    public init(sensors: [SensorReading]) { self.sensors = sensors }
    public var cpuTemperature: Double? { sensors.filter { $0.group == .cpu && $0.unit == .celsius }.map(\.value).max() }
    public var gpuTemperature: Double? { sensors.filter { $0.group == .gpu && $0.unit == .celsius }.map(\.value).max() }
    public var fanSpeeds: [SensorReading] { sensors.filter { $0.unit == .rpm } }
    public var totalPower: Double? { sensors.first { $0.key == "PSTR" }?.value }
}

public struct BluetoothDevice: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var address: String
    public var isConnected: Bool
    public var battery: Double?
    public var batteryLeft: Double?
    public var batteryRight: Double?
    public var batteryCase: Double?
    public var id: String { address }
    public init(name: String, address: String, isConnected: Bool, battery: Double? = nil, batteryLeft: Double? = nil, batteryRight: Double? = nil, batteryCase: Double? = nil) {
        self.name = name; self.address = address; self.isConnected = isConnected; self.battery = battery
        self.batteryLeft = batteryLeft; self.batteryRight = batteryRight; self.batteryCase = batteryCase
    }
}

public struct BluetoothReading: Codable, Equatable, Sendable {
    public var devices: [BluetoothDevice]
    public init(devices: [BluetoothDevice]) { self.devices = devices }
}

public struct ClockEntryReading: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var time: String
    public var date: String
    public var offset: String
    public init(id: UUID, label: String, time: String, date: String, offset: String) {
        self.id = id; self.label = label; self.time = time; self.date = date; self.offset = offset
    }
}

public struct ClockReading: Codable, Equatable, Sendable {
    public var entries: [ClockEntryReading]
    public init(entries: [ClockEntryReading]) { self.entries = entries }
}

/// One module's latest result.
public enum ModuleReading: Codable, Equatable, Sendable {
    case cpu(CPUReading)
    case ram(RAMReading)
    case disk(DiskReading)
    case network(NetworkReading)
    case battery(BatteryReading)
    case gpu(GPUReading)
    case sensors(SensorsReading)
    case bluetooth(BluetoothReading)
    case clock(ClockReading)
    case unavailable(String)

    public var isUnavailable: Bool { if case .unavailable = self { return true } else { return false } }
    public var unavailableReason: String? { if case .unavailable(let r) = self { return r } else { return nil } }
}

public struct MetricsSnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var readings: [ModuleID: ModuleReading]
    public init(timestamp: Date = Date(), readings: [ModuleID: ModuleReading] = [:]) {
        self.timestamp = timestamp; self.readings = readings
    }
    public subscript(_ id: ModuleID) -> ModuleReading? { readings[id] }
}
