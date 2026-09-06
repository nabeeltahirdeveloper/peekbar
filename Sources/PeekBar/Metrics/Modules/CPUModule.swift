import Foundation
import Darwin
import PeekBarCore

final class CPUModule: MetricModule {
    let id: ModuleID = .cpu
    private var previous: [CPUTicks]?
    private var efficiencyCores = 0
    private let processes = ProcessList()
    private var lastProcessSample: Date = .distantPast
    private var topProcesses: [ProcessUsage] = []
    var processInterval: TimeInterval = 3
    /// Filled from the sensors module when available.
    var temperatureProvider: (() -> Double?)?

    func start() throws {
        // On Apple Silicon perflevel1 is the efficiency cluster; on Intel there is one level.
        if let levels = Sysctl.int32("hw.nperflevels"), levels > 1 {
            efficiencyCores = Int(Sysctl.int32("hw.perflevel1.logicalcpu") ?? 0)
        }
        previous = readTicks()
        processes.reset()
    }

    func stop() { previous = nil; processes.reset() }
    func resetBaselines() { previous = nil; processes.reset() }

    private func readTicks() -> [CPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var ticks: [CPUTicks] = []
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(count) {
            let base = core * states
            ticks.append(CPUTicks(
                user: UInt64(info[base + Int(CPU_STATE_USER)]),
                system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return ticks
    }

    func sample() -> ModuleReading {
        guard let current = readTicks() else { return .unavailable("host_processor_info failed") }
        defer { previous = current }
        var perCore: [Double] = []
        var user = 0.0, system = 0.0
        if let prev = previous, prev.count == current.count {
            for (p, c) in zip(prev, current) {
                if let load = CPUTickMath.load(previous: p, current: c) {
                    perCore.append(load.busy); user += load.user; system += load.system
                } else {
                    perCore.append(0)
                }
            }
        } else {
            perCore = Array(repeating: 0, count: current.count)
        }
        let n = Double(max(1, perCore.count))
        let total = perCore.reduce(0, +) / n
        let split = CPUTickMath.splitCores(perCore, efficiencyCount: efficiencyCores)
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        let now = Date()
        if now.timeIntervalSince(lastProcessSample) >= processInterval {
            topProcesses = processes.topByCPU(limit: 5, now: now)
            lastProcessSample = now
        }
        return .cpu(CPUReading(total: total, user: user / n, system: system / n, perCore: perCore,
                               performanceCores: split.performance, efficiencyCores: split.efficiency,
                               loadAverage: loads, topProcesses: topProcesses, temperature: temperatureProvider?()))
    }
}
