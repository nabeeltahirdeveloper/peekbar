import Foundation
import PeekBarCore

final class ClockModule: MetricModule {
    let id: ModuleID = .clock
    private let lock = NSLock()
    private var _clocks: [WorldClock] = []
    var clocks: [WorldClock] {
        get { lock.lock(); defer { lock.unlock() }; return _clocks }
        set { lock.lock(); _clocks = newValue; lock.unlock() }
    }

    func start() throws {}
    func stop() {}

    func sample() -> ModuleReading {
        let now = Date()
        let list = clocks
        guard !list.isEmpty else { return .clock(ClockReading(entries: [])) }
        return .clock(ClockReading(entries: list.map { ClockFormatter.entry(for: $0, now: now) }))
    }
}
