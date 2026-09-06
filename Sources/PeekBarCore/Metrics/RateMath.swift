import Foundation

public enum RateMath {
    /// Bytes per second between two counter samples. Handles counter wrap at `wrapAt`
    /// (2^32 for the 32-bit `if_data` fields). Nil when time did not advance or the counter
    /// reset (a wrap larger than half the range is treated as a reset).
    public static func rate(previousBytes: UInt64, previousTime: Date, currentBytes: UInt64, currentTime: Date, wrapAt: UInt64? = nil) -> Double? {
        let dt = currentTime.timeIntervalSince(previousTime)
        guard dt > 0 else { return nil }
        var delta: UInt64
        if currentBytes >= previousBytes {
            delta = currentBytes - previousBytes
        } else if let w = wrapAt, previousBytes < w {
            delta = (w - previousBytes) &+ currentBytes
            if delta > w / 2 { return nil }
        } else {
            return nil
        }
        return Double(delta) / dt
    }
}

/// Keeps the previous sample per counter so modules can ask for rates by name.
public struct RateTracker: Sendable {
    private var samples: [String: (bytes: UInt64, time: Date)] = [:]
    public var wrapAt: UInt64?
    public init(wrapAt: UInt64? = nil) { self.wrapAt = wrapAt }

    /// Returns the rate since the previous call for `key`, or nil on the first call.
    public mutating func update(_ key: String, bytes: UInt64, at time: Date) -> Double? {
        defer { samples[key] = (bytes, time) }
        guard let prev = samples[key] else { return nil }
        return RateMath.rate(previousBytes: prev.bytes, previousTime: prev.time, currentBytes: bytes, currentTime: time, wrapAt: wrapAt)
    }

    public mutating func reset() { samples.removeAll() }
}
