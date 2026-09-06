import Foundation
import IOKit
import PeekBarCore

final class DiskModule: MetricModule {
    let id: ModuleID = .disk
    private var rates = RateTracker()
    private var lastVolumes: [DiskVolume] = []
    private var lastVolumeScan: Date = .distantPast

    func start() throws { rates.reset() }
    func stop() { rates.reset() }
    func resetBaselines() { rates.reset() }

    private func volumes() -> [DiskVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) else { return [] }
        var out: [DiskVolume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: keys), v.volumeIsBrowsable ?? true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let available = v.volumeAvailableCapacityForImportantUsage ?? 0
            out.append(DiskVolume(name: v.volumeName ?? url.lastPathComponent, path: url.path, total: UInt64(total),
                                  available: UInt64(max(0, available)), isInternal: v.volumeIsInternal ?? false, isRemovable: v.volumeIsRemovable ?? false))
        }
        return out.sorted { ($0.path == "/" ? 0 : 1, $0.name) < ($1.path == "/" ? 0 : 1, $1.name) }
    }

    func sample() -> ModuleReading {
        let now = Date()
        if now.timeIntervalSince(lastVolumeScan) > 10 || lastVolumes.isEmpty {
            lastVolumes = volumes()
            lastVolumeScan = now
        }
        var read: UInt64 = 0, write: UInt64 = 0
        for props in IORegistry.allProperties(matching: "IOBlockStorageDriver") {
            guard let stats = props["Statistics"] as? [String: Any] else { continue }
            read &+= UInt64(IORegistry.number(stats["Bytes (Read)"]) ?? 0)
            write &+= UInt64(IORegistry.number(stats["Bytes (Write)"]) ?? 0)
        }
        let r = rates.update("read", bytes: read, at: now) ?? 0
        let w = rates.update("write", bytes: write, at: now) ?? 0
        return .disk(DiskReading(volumes: lastVolumes, readRate: r, writeRate: w))
    }
}
