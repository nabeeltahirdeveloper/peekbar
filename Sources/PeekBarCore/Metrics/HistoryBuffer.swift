import Foundation

/// Fixed-capacity ring buffer for sparklines and rate history.
public struct HistoryBuffer<Element>: Sendable where Element: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ value: Element) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[head] = value
            head = (head + 1) % capacity
        }
    }

    /// Oldest to newest.
    public var values: [Element] {
        if storage.count < capacity { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        if storage.count < capacity { return storage.last }
        return storage[(head + capacity - 1) % capacity]
    }

    public func suffix(_ n: Int) -> [Element] { Array(values.suffix(max(0, n))) }

    public mutating func removeAll() { storage.removeAll(keepingCapacity: true); head = 0 }
}

/// All numeric series kept by the store.
public struct MetricHistory: Sendable {
    public var capacity: Int
    public private(set) var series: [MetricKey: HistoryBuffer<Double>] = [:]

    public init(capacity: Int = 180) { self.capacity = capacity }

    public mutating func record(_ value: Double, for key: MetricKey) {
        var buf = series[key] ?? HistoryBuffer(capacity: capacity)
        buf.append(value)
        series[key] = buf
    }

    public func values(for key: MetricKey, last n: Int? = nil) -> [Double] {
        guard let buf = series[key] else { return [] }
        return n.map { buf.suffix($0) } ?? buf.values
    }

    public func latest(_ key: MetricKey) -> Double? { series[key]?.last }

    public mutating func clear() { series.removeAll() }
}
