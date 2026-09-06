import Foundation
import IOKit
import IOKit.ps
import PeekBarCore

final class BatteryModule: MetricModule {
    let id: ModuleID = .battery

    func start() throws {
        guard hasInternalBattery() else {
            throw NSError(domain: "PeekBar.Metrics", code: 2, userInfo: [NSLocalizedDescriptionKey: "No battery in this Mac"])
        }
    }

    func stop() {}

    private func powerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
               (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
                return desc
            }
        }
        return nil
    }

    private func hasInternalBattery() -> Bool { powerSource() != nil }

    func sample() -> ModuleReading {
        guard let ps = powerSource() else { return .unavailable("No battery in this Mac") }
        let current = (ps[kIOPSCurrentCapacityKey] as? Double) ?? 0
        let max = (ps[kIOPSMaxCapacityKey] as? Double) ?? 100
        var reading = BatteryReading(
            level: max > 0 ? current / max : 0,
            isCharging: (ps[kIOPSIsChargingKey] as? Bool) ?? false,
            isPluggedIn: (ps[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        )
        if let m = ps[kIOPSTimeToEmptyKey] as? Int, m > 0 { reading.timeToEmptyMinutes = m }
        if let m = ps[kIOPSTimeToFullChargeKey] as? Int, m > 0 { reading.timeToFullMinutes = m }

        if let props = IORegistry.allProperties(matching: "AppleSmartBattery").first {
            if let c = IORegistry.number(props["CycleCount"]) { reading.cycleCount = Int(c) }
            let design = IORegistry.number(props["DesignCapacity"]) ?? 0
            let rawMax = IORegistry.number(props["AppleRawMaxCapacity"]) ?? IORegistry.number(props["NominalChargeCapacity"]) ?? 0
            if design > 0, rawMax > 0 { reading.health = Swift.min(1.2, rawMax / design) }
            if let t = IORegistry.number(props["Temperature"]) { reading.temperature = t / 100 }
            if let v = IORegistry.number(props["Voltage"]), let a = IORegistry.number(props["Amperage"]) {
                var amps = a
                if amps > 32_767 { amps -= 65_536 }   // some firmwares report unsigned 16-bit
                reading.wattage = abs(v / 1000 * amps / 1000)
            }
            if let adapter = props["AdapterDetails"] as? [String: Any] {
                let watts = IORegistry.number(adapter["Watts"])
                let name = (adapter["Description"] as? String) ?? (adapter["Name"] as? String)
                if let watts, watts > 0 { reading.adapterDescription = "\(name ?? "Adapter") \(Int(watts)) W" }
                else if let name { reading.adapterDescription = name }
            }
        }
        return .battery(reading)
    }
}
