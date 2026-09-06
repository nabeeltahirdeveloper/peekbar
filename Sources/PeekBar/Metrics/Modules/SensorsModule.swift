import Foundation
import PeekBarCore

final class SensorsModule: MetricModule {
    let id: ModuleID = .sensors
    private let smc = SMCClient()
    private let hid = HIDSensors()
    private var keys: [(key: String, descriptor: SensorDescriptor)] = []
    private(set) var lastReading: SensorsReading?
    /// Show keys the catalog cannot name (Settings ▸ advanced).
    var includeUnknown = false

    func start() throws {
        do { try smc.open() } catch {
            hid.start()
            if !hid.isAvailable { throw error }
        }
        let all = smc.allKeys()
        keys = all.compactMap { k in SensorCatalog.describe(key: k).map { (k, $0) } }
        hid.start()
        if keys.isEmpty, hid.isAvailable == false {
            throw NSError(domain: "PeekBar.Metrics", code: 3, userInfo: [NSLocalizedDescriptionKey: "No readable sensors on this Mac"])
        }
    }

    func stop() { smc.close(); hid.stop(); keys.removeAll() }

    func sample() -> ModuleReading {
        var out: [SensorReading] = []
        var seen: Set<String> = []
        for (key, d) in keys {
            guard let v = smc.read(key), SensorCatalog.isSane(v, unit: d.unit) else { continue }
            // Skip fan min/max/target rows unless there is an actual reading for that fan.
            if d.group == .fan, !key.hasSuffix("Ac") { continue }
            out.append(SensorReading(key: key, label: d.label, group: d.group, value: v, unit: d.unit))
            seen.insert(d.label)
        }
        // Several HID services report the same product name; keep the hottest per name.
        var hidMax: [String: Double] = [:]
        for (name, c) in hid.readTemperatures() { hidMax[name] = max(hidMax[name] ?? 0, c) }
        for (name, c) in hidMax {
            out.append(SensorReading(key: "hid:" + name, label: name, group: SensorCatalog.hidGroup(forProduct: name), value: c, unit: .celsius))
        }
        out = SensorCatalog.curate(out, advanced: includeUnknown)
        let reading = SensorsReading(sensors: out)
        lastReading = reading
        return out.isEmpty ? .unavailable("No readable sensors on this Mac") : .sensors(reading)
    }
}
