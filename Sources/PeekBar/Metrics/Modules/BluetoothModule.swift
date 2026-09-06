import Foundation
import IOBluetooth
import PeekBarCore

final class BluetoothModule: MetricModule {
    let id: ModuleID = .bluetooth

    func start() throws {}
    func stop() {}

    private static let batteryClasses = ["AppleDeviceManagementHIDEventService", "AppleHSBluetoothDevice", "IOBluetoothHIDDriver", "AppleBluetoothHIDKeyboard", "AppleBluetoothHIDMouse", "BNBTrackpadDevice", "BNBMouseDevice"]

    private static func normalize(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    private struct Battery { var main: Double?; var left: Double?; var right: Double?; var caseLevel: Double? }

    private func batteryLevels() -> [String: Battery] {
        var out: [String: Battery] = [:]
        for cls in Self.batteryClasses {
            for props in IORegistry.allProperties(matching: cls) {
                guard let addr = (props["DeviceAddress"] as? String) ?? (props["BD_ADDR"] as? String) else { continue }
                var b = out[Self.normalize(addr)] ?? Battery()
                if let v = IORegistry.number(props["BatteryPercent"]) { b.main = v / 100 }
                if let v = IORegistry.number(props["BatteryPercentLeft"]) { b.left = v / 100 }
                if let v = IORegistry.number(props["BatteryPercentRight"]) { b.right = v / 100 }
                if let v = IORegistry.number(props["BatteryPercentCase"]) { b.caseLevel = v / 100 }
                out[Self.normalize(addr)] = b
            }
        }
        return out
    }

    func sample() -> ModuleReading {
        let levels = batteryLevels()
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        var devices: [BluetoothDevice] = []
        for d in paired {
            let addr = Self.normalize(d.addressString ?? "")
            let b = levels[addr]
            devices.append(BluetoothDevice(name: d.name ?? addr, address: addr, isConnected: d.isConnected(),
                                           battery: b?.main, batteryLeft: b?.left, batteryRight: b?.right, batteryCase: b?.caseLevel))
        }
        // Registry entries with a battery but no pairing record (rare) still get listed.
        for (addr, b) in levels where !devices.contains(where: { $0.address == addr }) {
            devices.append(BluetoothDevice(name: addr, address: addr, isConnected: true, battery: b.main, batteryLeft: b.left, batteryRight: b.right, batteryCase: b.caseLevel))
        }
        devices.sort { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
        return .bluetooth(BluetoothReading(devices: devices))
    }
}
