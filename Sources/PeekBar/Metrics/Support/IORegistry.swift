import Foundation
import IOKit

/// Thin helpers over the I/O Registry. Read-only.
enum IORegistry {
    /// Matching services; the caller must `IOObjectRelease` each.
    static func services(matching className: String) -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [io_service_t] = []
        while case let s = IOIteratorNext(iterator), s != 0 { out.append(s) }
        return out
    }

    static func properties(of service: io_service_t) -> [String: Any] {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return [:] }
        return dict
    }

    static func property(_ key: String, of service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Properties of every matching service, releasing the handles.
    static func allProperties(matching className: String) -> [[String: Any]] {
        services(matching: className).map { s in
            defer { IOObjectRelease(s) }
            return properties(of: s)
        }
    }

    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
