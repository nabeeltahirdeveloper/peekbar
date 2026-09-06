import Foundation
import Metal
import PeekBarCore

final class GPUModule: MetricModule {
    let id: ModuleID = .gpu
    private var name = "GPU"
    private var memoryTotal: UInt64?
    private var emptyReads = 0
    var temperatureProvider: (() -> Double?)?

    func start() throws {
        if let device = MTLCreateSystemDefaultDevice() {
            name = device.name
            memoryTotal = device.recommendedMaxWorkingSetSize > 0 ? device.recommendedMaxWorkingSetSize : nil
        }
        emptyReads = 0
    }

    func stop() {}

    func sample() -> ModuleReading {
        var utilization: Double?
        var renderer: Double?
        var tiler: Double?
        var used: UInt64?
        for props in IORegistry.allProperties(matching: "IOAccelerator") {
            guard let stats = props["PerformanceStatistics"] as? [String: Any] else { continue }
            if let u = IORegistry.number(stats["Device Utilization %"]) ?? IORegistry.number(stats["GPU Activity(%)"]) { utilization = min(1, u / 100) }
            if let r = IORegistry.number(stats["Renderer Utilization %"]) { renderer = min(1, r / 100) }
            if let t = IORegistry.number(stats["Tiler Utilization %"]) { tiler = min(1, t / 100) }
            if let m = IORegistry.number(stats["In use system memory"]) ?? IORegistry.number(stats["vramUsedBytes"]) { used = UInt64(max(0, m)) }
            if utilization != nil { break }
        }
        if utilization == nil {
            emptyReads += 1
            if emptyReads >= 10 { return .unavailable("This GPU driver does not report utilization") }
        } else {
            emptyReads = 0
        }
        return .gpu(GPUReading(name: name, utilization: utilization, rendererUtilization: renderer, tilerUtilization: tiler,
                               memoryUsed: used, memoryTotal: memoryTotal, temperature: temperatureProvider?()))
    }
}
