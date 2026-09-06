import Foundation
import Darwin
import PeekBarCore

/// Top processes by CPU or memory without spawning `ps`. Only names and usage are read.
final class ProcessList {
    private var previousCPU: [pid_t: (ticks: UInt64, time: Date)] = [:]
    private var timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    private func pids() -> [pid_t] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 16)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }
        return Array(buf.prefix(Int(written) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    private func name(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : "pid \(pid)"
    }

    /// CPU as a fraction of one core since the previous call (nil entries on first call).
    func topByCPU(limit: Int, now: Date = Date()) -> [ProcessUsage] {
        var current: [pid_t: (ticks: UInt64, time: Date)] = [:]
        var results: [ProcessUsage] = []
        for pid in pids() {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            current[pid] = (ticks, now)
            if let prev = previousCPU[pid] {
                let dt = now.timeIntervalSince(prev.time)
                guard dt > 0, ticks >= prev.ticks else { continue }
                let ns = Double(ticks - prev.ticks) * Double(timebase.numer) / Double(timebase.denom)
                let fraction = ns / 1_000_000_000 / dt
                if fraction > 0.001 { results.append(ProcessUsage(pid: pid, name: name(of: pid), value: fraction)) }
            }
        }
        previousCPU = current
        return Array(results.sorted { $0.value > $1.value }.prefix(limit))
    }

    /// Physical footprint in bytes.
    func topByMemory(limit: Int) -> [ProcessUsage] {
        var results: [ProcessUsage] = []
        for pid in pids() {
            var info = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &info) { ptr -> Bool in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) == 0 }
            }
            guard ok, info.ri_phys_footprint > 0 else { continue }
            results.append(ProcessUsage(pid: pid, name: name(of: pid), value: Double(info.ri_phys_footprint)))
        }
        return Array(results.sorted { $0.value > $1.value }.prefix(limit))
    }

    func reset() { previousCPU.removeAll() }
}
