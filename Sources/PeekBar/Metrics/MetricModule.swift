import Foundation
import PeekBarCore

/// One monitoring source. Instances are owned by `MetricsEngine` and only ever called from
/// inside that actor, so they may keep mutable state without locks.
protocol MetricModule: AnyObject {
    var id: ModuleID { get }
    /// Open handles, prime deltas. Throwing marks the module unavailable with the error text.
    func start() throws
    /// Fast, non-blocking read of the current values.
    func sample() -> ModuleReading
    /// Release handles. Called when the module is no longer demanded.
    func stop()
    /// Forget delta baselines (sleep/wake, counter resets).
    func resetBaselines()
}

extension MetricModule {
    func resetBaselines() {}
}

/// sysctl helpers shared by modules.
enum Sysctl {
    static func uint64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func int32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
