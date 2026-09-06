import Foundation

public enum AlertComparator: String, Codable, CaseIterable, Sendable {
    case above, below
    public var title: String { self == .above ? "above" : "below" }
}

/// A threshold notification rule (Stats-style alerts).
public struct AlertRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var metric: MetricKey
    public var comparator: AlertComparator
    /// Fraction (0–1) for percentage metrics, °C for temperatures, bytes/s for rates.
    public var threshold: Double
    /// How long the breach must persist before firing.
    public var duration: TimeInterval
    /// Value must cross back past threshold ∓ hysteresis before the alert clears.
    public var hysteresis: Double
    /// Minimum gap between two firings of the same rule.
    public var cooldown: TimeInterval
    public var enabled: Bool

    public init(id: UUID = UUID(), metric: MetricKey, comparator: AlertComparator = .above, threshold: Double, duration: TimeInterval = 30, hysteresis: Double? = nil, cooldown: TimeInterval = 300, enabled: Bool = true) {
        self.id = id
        self.metric = metric
        self.comparator = comparator
        self.threshold = threshold
        self.duration = duration
        self.hysteresis = hysteresis ?? AlertRule.defaultHysteresis(for: metric, threshold: threshold)
        self.cooldown = cooldown
        self.enabled = enabled
    }

    public static func defaultHysteresis(for metric: MetricKey, threshold: Double) -> Double {
        if metric.isFraction { return 0.05 }
        if metric.metric == "temperature" { return 3 }
        return max(1, threshold * 0.1)
    }

    public static let defaultRule = AlertRule(metric: .cpuTotal, comparator: .above, threshold: 0.9, duration: 30)
}

public enum AlertEvent: Equatable, Sendable {
    case fired(rule: AlertRule, value: Double)
    case cleared(rule: AlertRule, value: Double)

    public var rule: AlertRule {
        switch self { case .fired(let r, _), .cleared(let r, _): return r }
    }
    public var value: Double {
        switch self { case .fired(_, let v), .cleared(_, let v): return v }
    }
    public var isFired: Bool { if case .fired = self { return true } else { return false } }
}

/// Stateful evaluation of rules against a stream of values.
public struct AlertEvaluator: Sendable {
    private struct State: Sendable {
        var breachStart: Date?
        var isActive = false
        var lastFired: Date?
    }

    public private(set) var rules: [AlertRule]
    private var states: [UUID: State] = [:]

    public init(rules: [AlertRule] = []) { self.rules = rules }

    /// Replaces the rules, keeping state for rules that still exist.
    public mutating func setRules(_ new: [AlertRule]) {
        rules = new
        let ids = Set(new.map(\.id))
        states = states.filter { ids.contains($0.key) }
    }

    public func isActive(_ id: UUID) -> Bool { states[id]?.isActive ?? false }

    public mutating func evaluate(value: Double, for key: MetricKey, at now: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for rule in rules where rule.enabled && rule.metric == key {
            var s = states[rule.id] ?? State()
            let breaching = rule.comparator == .above ? value > rule.threshold : value < rule.threshold
            let cleared = rule.comparator == .above ? value < rule.threshold - rule.hysteresis : value > rule.threshold + rule.hysteresis
            if s.isActive {
                if cleared {
                    s.isActive = false
                    s.breachStart = nil
                    events.append(.cleared(rule: rule, value: value))
                }
            } else if breaching {
                if s.breachStart == nil { s.breachStart = now }
                if let start = s.breachStart, now.timeIntervalSince(start) >= rule.duration {
                    let cool = s.lastFired.map { now.timeIntervalSince($0) < rule.cooldown } ?? false
                    if !cool {
                        s.isActive = true
                        s.lastFired = now
                        events.append(.fired(rule: rule, value: value))
                    }
                }
            } else {
                s.breachStart = nil
            }
            states[rule.id] = s
        }
        return events
    }
}
