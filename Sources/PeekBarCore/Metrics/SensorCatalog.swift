import Foundation

public struct SensorDescriptor: Equatable, Sendable {
    public var label: String
    public var group: SensorGroup
    public var unit: SensorUnit
    public init(label: String, group: SensorGroup, unit: SensorUnit) { self.label = label; self.group = group; self.unit = unit }
}

/// Maps SMC keys to labels/groups and decodes SMC value encodings. Pure, so it is unit-tested;
/// the IOKit call itself lives in the app.
public enum SensorCatalog {
    static let known: [String: SensorDescriptor] = [
        // Intel-era and shared keys
        "TC0P": .init(label: "CPU proximity", group: .cpu, unit: .celsius),
        "TC0D": .init(label: "CPU die", group: .cpu, unit: .celsius),
        "TC0E": .init(label: "CPU", group: .cpu, unit: .celsius),
        "TC0F": .init(label: "CPU", group: .cpu, unit: .celsius),
        "TCXC": .init(label: "CPU package", group: .cpu, unit: .celsius),
        "TG0P": .init(label: "GPU proximity", group: .gpu, unit: .celsius),
        "TG0D": .init(label: "GPU die", group: .gpu, unit: .celsius),
        "TA0P": .init(label: "Ambient", group: .ambient, unit: .celsius),
        "TA1P": .init(label: "Ambient 2", group: .ambient, unit: .celsius),
        "TW0P": .init(label: "Wireless", group: .other, unit: .celsius),
        "TB0T": .init(label: "Battery", group: .battery, unit: .celsius),
        "TB1T": .init(label: "Battery 2", group: .battery, unit: .celsius),
        "TB2T": .init(label: "Battery 3", group: .battery, unit: .celsius),
        "Ts0P": .init(label: "Palm rest", group: .ambient, unit: .celsius),
        "Ts1P": .init(label: "Palm rest 2", group: .ambient, unit: .celsius),
        "TH0x": .init(label: "SSD", group: .storage, unit: .celsius),
        "Tm0P": .init(label: "Memory proximity", group: .memory, unit: .celsius),
        "Tm0p": .init(label: "Memory", group: .memory, unit: .celsius),
        "Tm1p": .init(label: "Memory 2", group: .memory, unit: .celsius),
        "TM0P": .init(label: "Memory", group: .memory, unit: .celsius),
        // Apple Silicon
        "Tp0T": .init(label: "CPU", group: .cpu, unit: .celsius),
        "Tg0T": .init(label: "GPU", group: .gpu, unit: .celsius),
        "TW0T": .init(label: "Wireless", group: .other, unit: .celsius),
        // Power
        "PSTR": .init(label: "System total", group: .power, unit: .watts),
        "PCPC": .init(label: "CPU package", group: .power, unit: .watts),
        "PCPT": .init(label: "CPU total", group: .power, unit: .watts),
        "PCPR": .init(label: "CPU", group: .power, unit: .watts),
        "PGPR": .init(label: "GPU", group: .power, unit: .watts),
        "PGPC": .init(label: "GPU package", group: .power, unit: .watts),
        "PDTR": .init(label: "DC in", group: .power, unit: .watts),
        "PPBR": .init(label: "Battery", group: .power, unit: .watts),
        "PHPC": .init(label: "Heatpipe", group: .power, unit: .watts),
        // Fans handled by pattern; voltage/current by prefix.
    ]

    /// Human label, group and unit for a key, or nil for keys we should not display.
    public static func describe(key: String) -> SensorDescriptor? {
        if let k = known[key] { return k }
        guard key.count == 4 else { return nil }
        let chars = Array(key)
        let prefix = String(chars[0])
        // Fans: F<n>Ac (actual), F<n>Mn/Mx (limits), F<n>Tg (target)
        if prefix == "F", let n = Int(String(chars[1])) {
            let suffix = String(chars[2...])
            switch suffix {
            case "Ac": return .init(label: "Fan \(n + 1)", group: .fan, unit: .rpm)
            case "Mn": return .init(label: "Fan \(n + 1) min", group: .fan, unit: .rpm)
            case "Mx": return .init(label: "Fan \(n + 1) max", group: .fan, unit: .rpm)
            case "Tg": return .init(label: "Fan \(n + 1) target", group: .fan, unit: .rpm)
            default: return nil
            }
        }
        if prefix == "T" {
            let second = chars[1]
            let idx = String(chars[2...])
            switch second {
            case "p": return .init(label: "CPU core \(idx)", group: .cpu, unit: .celsius)
            case "e": return .init(label: "CPU efficiency \(idx)", group: .cpu, unit: .celsius)
            case "c", "C": return .init(label: "CPU \(idx)", group: .cpu, unit: .celsius)
            case "g", "G": return .init(label: "GPU \(idx)", group: .gpu, unit: .celsius)
            case "a", "A": return .init(label: "Ambient \(idx)", group: .ambient, unit: .celsius)
            case "B": return .init(label: "Battery \(idx)", group: .battery, unit: .celsius)
            case "H", "h": return .init(label: "Storage \(idx)", group: .storage, unit: .celsius)
            case "m", "M": return .init(label: "Memory \(idx)", group: .memory, unit: .celsius)
            case "s", "S": return .init(label: "Surface \(idx)", group: .ambient, unit: .celsius)
            case "W", "w": return .init(label: "Wireless \(idx)", group: .other, unit: .celsius)
            default: return .init(label: "Sensor \(key)", group: .other, unit: .celsius)
            }
        }
        if prefix == "P", chars.last == "R" || chars.last == "C" || chars.last == "T" {
            return .init(label: "Power \(String(chars[1...2]))", group: .power, unit: .watts)
        }
        if prefix == "V", chars.last == "R" || chars.last == "C" {
            return .init(label: "Voltage \(String(chars[1...2]))", group: .voltage, unit: .volts)
        }
        if prefix == "I", chars.last == "R" || chars.last == "C" {
            return .init(label: "Current \(String(chars[1...2]))", group: .current, unit: .amps)
        }
        return nil
    }

    /// Discards readings that cannot be real (unpowered sensors report 0 or huge values).
    public static func isSane(_ value: Double, unit: SensorUnit) -> Bool {
        guard value.isFinite else { return false }
        switch unit {
        case .celsius: return value > 0 && value < 150
        case .rpm: return value >= 0 && value < 20_000
        case .watts: return value >= 0 && value < 1_000
        case .volts: return value >= 0 && value < 100
        case .amps: return value > -100 && value < 100
        case .raw: return true
        }
    }

    /// Decodes an SMC value by its 4-character type code.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        guard !bytes.isEmpty else { return nil }
        func be16() -> UInt16? { bytes.count >= 2 ? (UInt16(bytes[0]) << 8 | UInt16(bytes[1])) : nil }
        func be32() -> UInt32? { bytes.count >= 4 ? (UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])) : nil }
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 ", "ui8": return Double(bytes[0])
        case "ui16": return be16().map(Double.init)
        case "ui32": return be32().map(Double.init)
        case "si8 ", "si8": return Double(Int8(bitPattern: bytes[0]))
        case "si16": return be16().map { Double(Int16(bitPattern: $0)) }
        case "ioft":
            // 64-bit fixed point, 16 fractional bits, big endian.
            guard bytes.count >= 8 else { return nil }
            var v: UInt64 = 0
            for b in bytes.prefix(8) { v = v << 8 | UInt64(b) }
            return Double(v) / 65_536
        default:
            break
        }
        // Signed fixed point: sp<i><f> (i integer bits, f fractional bits, hex digits)
        // Unsigned fixed point: fp<i><f>
        if type.count == 4, type.hasPrefix("sp") || type.hasPrefix("fp"), let raw = be16() {
            let chars = Array(type)
            guard let f = Int(String(chars[3]), radix: 16) else { return nil }
            if type.hasPrefix("sp") {
                return Double(Int16(bitPattern: raw)) / Double(1 << f)
            }
            return Double(raw) / Double(1 << f)
        }
        return nil
    }

    /// Keys with a hand-written label (vs. a pattern-generated one) rank first.
    public static func isCurated(key: String) -> Bool {
        known[key] != nil || key.hasPrefix("hid:") || (key.hasPrefix("F") && key.hasSuffix("Ac"))
    }

    /// Per-group caps so a 3,000-key SMC does not flood the page. Voltage/current rails are
    /// only shown in advanced mode.
    public static func cap(for group: SensorGroup, advanced: Bool) -> Int {
        switch group {
        case .cpu: return 16
        case .gpu: return 8
        case .soc, .memory, .storage, .battery: return 4
        case .ambient: return advanced ? 12 : 4
        case .fan: return 8
        case .power: return advanced ? 16 : 8
        case .voltage, .current: return advanced ? 12 : 0
        case .other: return advanced ? 8 : 2
        }
    }

    /// Orders curated entries first (natural label order within), applies the caps, and
    /// drops meaningless rows (zero currents).
    public static func curate(_ readings: [SensorReading], advanced: Bool, limit: Int = 64) -> [SensorReading] {
        var out: [SensorReading] = []
        for group in SensorGroup.allCases {
            let cap = cap(for: group, advanced: advanced)
            guard cap > 0 else { continue }
            let items = readings.filter { $0.group == group && !($0.unit == .amps && $0.value == 0) }
                .sorted {
                    let a = isCurated(key: $0.key), b = isCurated(key: $1.key)
                    if a != b { return a }
                    return $0.label.localizedStandardCompare($1.label) == .orderedAscending
                }
            out.append(contentsOf: items.prefix(cap))
        }
        return Array(out.prefix(limit))
    }

    /// HID temperature sensor names on Apple Silicon → group.
    public static func hidGroup(forProduct name: String) -> SensorGroup {
        let n = name.lowercased()
        if n.contains("gpu") { return .gpu }
        if n.contains("tdie") || n.contains("tdev") || n.contains("cpu") || n.contains("soc") { return .cpu }
        if n.contains("gas gauge") || n.contains("battery") { return .battery }
        if n.contains("nand") || n.contains("ssd") { return .storage }
        if n.contains("pmu") || n.contains("tcal") { return .soc }
        return .other
    }
}
