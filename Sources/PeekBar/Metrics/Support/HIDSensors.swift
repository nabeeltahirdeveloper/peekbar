import Foundation
import IOKit
import PeekBarCore

/// Apple Silicon die temperatures come from HID "sensor" services that the public HID API does
/// not expose. The symbols are resolved at runtime; every step is optional so a future macOS
/// that removes them simply yields no readings.
final class HIDSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private let create: CreateFn?
    private let setMatching: SetMatchingFn?
    private let copyServices: CopyServicesFn?
    private let copyProperty: CopyPropertyFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?
    private var client: AnyObject?
    private var services: [(name: String, service: AnyObject)] = []

    private static let temperatureEventType: Int64 = 15
    private static var temperatureField: Int32 { Int32(temperatureEventType << 16) }

    init() {
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        create = sym("IOHIDEventSystemClientCreate", CreateFn.self)
        setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self)
        copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self)
        copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self)
        copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self)
        getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self)
    }

    var isAvailable: Bool { create != nil && setMatching != nil && copyServices != nil && copyProperty != nil && copyEvent != nil && getFloat != nil }

    func start() {
        guard isAvailable, client == nil, let create, let setMatching, let copyServices, let copyProperty else { return }
        guard let c = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        client = c
        let matching: [String: Any] = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5]
        setMatching(c, matching as CFDictionary)
        guard let list = copyServices(c)?.takeRetainedValue() as? [AnyObject] else { return }
        services = list.compactMap { s in
            guard let name = copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String else { return nil }
            return (name, s)
        }
    }

    func stop() { services.removeAll(); client = nil }

    /// Temperatures in °C keyed by the product name.
    func readTemperatures() -> [(name: String, celsius: Double)] {
        guard let copyEvent, let getFloat else { return [] }
        var out: [(String, Double)] = []
        for (name, service) in services {
            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
            let v = getFloat(event, Self.temperatureField)
            if SensorCatalog.isSane(v, unit: .celsius) { out.append((name, v)) }
        }
        return out
    }
}
