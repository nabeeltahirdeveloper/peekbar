import Foundation
import Darwin
import PeekBarCore

final class RAMModule: MetricModule {
    let id: ModuleID = .ram
    private var total: UInt64 = 0
    private let processes = ProcessList()
    private var lastProcessSample: Date = .distantPast
    private var topProcesses: [ProcessUsage] = []
    var processInterval: TimeInterval = 3

    func start() throws {
        total = Sysctl.uint64("hw.memsize") ?? 0
        guard total > 0 else { throw NSError(domain: "PeekBar.Metrics", code: 1, userInfo: [NSLocalizedDescriptionKey: "hw.memsize unavailable"]) }
    }

    func stop() {}

    func sample() -> ModuleReading {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return .unavailable("host_statistics64 failed") }
        let input = VMStatsInput(
            free: UInt64(stats.free_count), active: UInt64(stats.active_count), inactive: UInt64(stats.inactive_count),
            wired: UInt64(stats.wire_count), speculative: UInt64(stats.speculative_count), compressor: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count), external: UInt64(stats.external_page_count), internalPages: UInt64(stats.internal_page_count)
        )
        var reading = MemoryMath.breakdown(input, pageSize: UInt64(vm_kernel_page_size), total: total)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            reading.swapUsed = swap.xsu_used
            reading.swapTotal = swap.xsu_total
        }
        if let level = Sysctl.int32("kern.memorystatus_level") {
            reading.pressure = MemoryMath.pressure(fromFreeLevel: Int(level))
        }
        let now = Date()
        if now.timeIntervalSince(lastProcessSample) >= processInterval {
            topProcesses = processes.topByMemory(limit: 5)
            lastProcessSample = now
        }
        reading.topProcesses = topProcesses
        return .ram(reading)
    }
}
