import Foundation

/// Page counts from `vm_statistics64`.
public struct VMStatsInput: Equatable, Sendable {
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var wired: UInt64
    public var speculative: UInt64
    public var compressor: UInt64
    public var purgeable: UInt64
    public var external: UInt64
    public var internalPages: UInt64
    public init(free: UInt64, active: UInt64, inactive: UInt64, wired: UInt64, speculative: UInt64, compressor: UInt64, purgeable: UInt64, external: UInt64, internalPages: UInt64) {
        self.free = free; self.active = active; self.inactive = inactive; self.wired = wired
        self.speculative = speculative; self.compressor = compressor; self.purgeable = purgeable
        self.external = external; self.internalPages = internalPages
    }
}

public enum MemoryMath {
    /// Activity Monitor style breakdown: app = anonymous pages minus purgeable, cached =
    /// file-backed plus purgeable, used = app + wired + compressed.
    public static func breakdown(_ s: VMStatsInput, pageSize: UInt64, total: UInt64) -> RAMReading {
        let app = s.internalPages >= s.purgeable ? (s.internalPages - s.purgeable) * pageSize : 0
        let wired = s.wired * pageSize
        let compressed = s.compressor * pageSize
        let cached = (s.external + s.purgeable) * pageSize
        let used = min(total, app + wired + compressed)
        let free = total >= used ? total - used : 0
        return RAMReading(total: total, used: used, app: app, wired: wired, compressed: compressed, cached: cached, free: free)
    }

    /// Maps `kern.memorystatus_level` (percent of memory considered free) to a pressure level.
    public static func pressure(fromFreeLevel level: Int) -> MemoryPressure {
        if level <= 5 { return .critical }
        if level <= 20 { return .warning }
        return .normal
    }
}
