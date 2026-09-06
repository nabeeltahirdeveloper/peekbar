import Foundation
import Combine
import PeekBarCore

/// Main-actor view of the engine: latest snapshot plus history series for sparklines.
@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var snapshot = MetricsSnapshot()
    @Published private(set) var history = MetricHistory(capacity: 180)
    @Published private(set) var demand = DemandSet()
    @Published var temperatureUnit: TemperatureUnit = .celsius
    @Published var byteStyle: ByteStyle = .binary
    @Published private(set) var lastUpdate: Date?
    private var previous = MetricsSnapshot()

    let engine: MetricsEngine
    private var consumer: Task<Void, Never>?
    private var evaluator = AlertEvaluator()
    @Published private(set) var activeAlerts: Set<UUID> = []
    /// Threshold events (fired/cleared).
    var onAlert: ((AlertEvent) -> Void)?
    var baseIntervals: [ModuleID: TimeInterval] = [:]
    /// Called with every new snapshot (widgets, alerts).
    var onSnapshot: ((MetricsSnapshot) -> Void)?

    init(engine: MetricsEngine) {
        self.engine = engine
        consumer = Task { [weak self] in
            for await snap in engine.snapshots {
                guard let self else { return }
                self.apply(snap)
            }
        }
    }

    func reading(_ id: ModuleID) -> ModuleReading? { snapshot.readings[id] }

    func setDemand(_ d: DemandSet) {
        guard d != demand else { return }
        demand = d
        let ids = d.demanded
        var intervals: [ModuleID: TimeInterval] = [:]
        for id in ids { intervals[id] = d.interval(for: id, base: baseIntervals[id] ?? id.defaultInterval) }
        Task { await engine.setDemand(ids, intervals: intervals) }
    }

    func resetBaselines() { Task { await engine.resetBaselines() } }

    func setRules(_ rules: [AlertRule]) {
        evaluator.setRules(rules)
        activeAlerts = Set(rules.map(\.id).filter { evaluator.isActive($0) })
    }

    func isAlertActive(_ id: UUID) -> Bool { activeAlerts.contains(id) }

    private func record(_ value: Double, for key: MetricKey, at time: Date) {
        history.record(value, for: key)
        for event in evaluator.evaluate(value: value, for: key, at: time) {
            if event.isFired { activeAlerts.insert(event.rule.id) } else { activeAlerts.remove(event.rule.id) }
            onAlert?(event)
        }
    }

    private func apply(_ snap: MetricsSnapshot) {
        // Only the modules that changed since the last snapshot get new history points; the
        // engine yields the merged snapshot on every module tick.
        let changed = snap.readings.filter { previous.readings[$0.key] != $0.value }
        previous = snap
        snapshot = snap
        lastUpdate = snap.timestamp
        let t = snap.timestamp
        for (_, reading) in changed {
            switch reading {
            case .cpu(let c):
                record(c.total, for: .cpuTotal, at: t)
                if let temp = c.temperature { record(temp, for: .cpuTemperature, at: t) }
            case .ram(let r): record(r.usedFraction, for: .ramUsed, at: t)
            case .disk(let d):
                record(d.readRate, for: .diskRead, at: t)
                record(d.writeRate, for: .diskWrite, at: t)
                if let p = d.primary { record(p.usedFraction, for: .diskUsed, at: t) }
            case .network(let n):
                record(n.downloadRate, for: .networkDown, at: t)
                record(n.uploadRate, for: .networkUp, at: t)
            case .battery(let b):
                record(b.level, for: .batteryLevel, at: t)
                if let temp = b.temperature { record(temp, for: .batteryTemperature, at: t) }
            case .gpu(let g):
                if let u = g.utilization { record(u, for: .gpuUtilization, at: t) }
                if let temp = g.temperature { record(temp, for: .gpuTemperature, at: t) }
            case .sensors(let s):
                for sensor in s.sensors { history.record(sensor.value, for: .sensor(sensor.key)) }
                if let temp = s.cpuTemperature { record(temp, for: .cpuTemperature, at: t) }
                if let temp = s.gpuTemperature { record(temp, for: .gpuTemperature, at: t) }
            default: break
            }
        }
        onSnapshot?(snap)
    }

    /// Debug: everything as JSON (module ids as string keys).
    func snapshotJSON() -> Data {
        struct Dump: Encodable { var timestamp: Date; var readings: [String: ModuleReading] }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let dump = Dump(timestamp: snapshot.timestamp, readings: Dictionary(uniqueKeysWithValues: snapshot.readings.map { ($0.key.rawValue, $0.value) }))
        return (try? enc.encode(dump)) ?? Data()
    }
}
