import Foundation
import PeekBarCore

/// Demand-driven sampler (SRS: idle CPU ≈ 0). One task per demanded module; modules that
/// nobody displays are stopped and their handles released.
actor MetricsEngine {
    private var modules: [ModuleID: MetricModule] = [:]
    private var tasks: [ModuleID: Task<Void, Never>] = [:]
    private var started: Set<ModuleID> = []
    private var startErrors: [ModuleID: String] = [:]
    private var intervals: [ModuleID: TimeInterval] = [:]
    private var snapshot = MetricsSnapshot()
    private let continuation: AsyncStream<MetricsSnapshot>.Continuation
    nonisolated let snapshots: AsyncStream<MetricsSnapshot>

    init(modules: [MetricModule]) {
        for m in modules { self.modules[m.id] = m }
        var cont: AsyncStream<MetricsSnapshot>.Continuation!
        snapshots = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    var liveTaskCount: Int { tasks.count }
    var liveModules: Set<ModuleID> { Set(tasks.keys) }
    var availableModules: Set<ModuleID> { Set(modules.keys) }

    /// Starts sampling for `demand` and stops everything else.
    func setDemand(_ demand: Set<ModuleID>, intervals newIntervals: [ModuleID: TimeInterval]) {
        intervals = newIntervals
        for (id, task) in tasks where !demand.contains(id) {
            task.cancel()
            tasks[id] = nil
            stopModule(id)
        }
        for id in demand where tasks[id] == nil && modules[id] != nil {
            tasks[id] = Task { [weak self] in await self?.run(id) }
        }
    }

    func stopAll() {
        setDemand([], intervals: intervals)
    }

    func resetBaselines() {
        for id in started { modules[id]?.resetBaselines() }
    }

    /// One-off read (debug / tests). Starts the module if needed.
    func sampleNow(_ id: ModuleID) -> ModuleReading {
        guard modules[id] != nil else { return .unavailable("No such module") }
        return read(id)
    }

    private func run(_ id: ModuleID) async {
        while !Task.isCancelled {
            let reading = read(id)
            snapshot.timestamp = Date()
            snapshot.readings[id] = reading
            continuation.yield(snapshot)
            let interval = intervals[id] ?? id.defaultInterval
            try? await Task.sleep(nanoseconds: UInt64(max(0.25, interval) * 1_000_000_000))
        }
    }

    private func read(_ id: ModuleID) -> ModuleReading {
        guard let module = modules[id] else { return .unavailable("No such module") }
        if !started.contains(id) {
            do {
                try module.start()
                started.insert(id)
                startErrors[id] = nil
            } catch {
                startErrors[id] = error.localizedDescription
                return .unavailable(error.localizedDescription)
            }
        }
        return module.sample()
    }

    private func stopModule(_ id: ModuleID) {
        guard started.contains(id) else { return }
        modules[id]?.stop()
        started.remove(id)
    }
}
