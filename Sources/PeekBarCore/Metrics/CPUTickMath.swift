import Foundation

public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
    public var total: UInt64 { user &+ system &+ idle &+ nice }
}

public struct CPULoad: Equatable, Sendable {
    public var user: Double
    public var system: Double
    public var idle: Double
    public var busy: Double { min(1, max(0, 1 - idle)) }
    public init(user: Double, system: Double, idle: Double) { self.user = user; self.system = system; self.idle = idle }
}

public enum CPUTickMath {
    /// Load between two tick samples. Nil when no ticks elapsed (same sample) or on wrap.
    public static func load(previous: CPUTicks, current: CPUTicks) -> CPULoad? {
        let dTotal = current.total &- previous.total
        guard dTotal > 0, current.total >= previous.total else { return nil }
        let dUser = Double((current.user &+ current.nice) &- (previous.user &+ previous.nice))
        let dSystem = Double(current.system &- previous.system)
        let dIdle = Double(current.idle &- previous.idle)
        let t = Double(dTotal)
        return CPULoad(user: dUser / t, system: dSystem / t, idle: dIdle / t)
    }

    /// On Apple Silicon efficiency cores are the lowest-numbered CPUs.
    public static func splitCores(_ perCore: [Double], efficiencyCount: Int) -> (performance: Double?, efficiency: Double?) {
        guard efficiencyCount > 0, efficiencyCount < perCore.count else { return (nil, nil) }
        let e = perCore.prefix(efficiencyCount)
        let p = perCore.dropFirst(efficiencyCount)
        return (p.reduce(0, +) / Double(p.count), e.reduce(0, +) / Double(e.count))
    }
}
