import Foundation

/// Persistent facts about one extra (SRS F-04, F-05, F-31).
public struct ExtraRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: ExtraID
    public var displayName: String
    public var bundleID: String?
    public var zone: Zone
    public var isNew: Bool
    public var firstSeen: Date
    public var lastSeen: Date
    public var incompatibleReason: String?
    public var lastOrderX: Double

    public init(id: ExtraID, displayName: String, bundleID: String?, zone: Zone, isNew: Bool, firstSeen: Date, lastSeen: Date, incompatibleReason: String? = nil, lastOrderX: Double = 0) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.zone = zone
        self.isNew = isNew
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.incompatibleReason = incompatibleReason
        self.lastOrderX = lastOrderX
    }
}

public struct LayoutSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var records: [ExtraRecord]
    public var exportedAt: Date?

    public init(version: Int = LayoutSnapshot.currentVersion, records: [ExtraRecord] = [], exportedAt: Date? = nil) {
        self.version = version
        self.records = records
        self.exportedAt = exportedAt
    }
}

/// Zone assignments and metadata, persisted as a small JSON file (SRS §12 LayoutStore).
public final class LayoutStore {
    public private(set) var records: [ExtraID: ExtraRecord] = [:]
    public let fileURL: URL?
    private let now: () -> Date
    public var onChange: (() -> Void)?

    public init(fileURL: URL?, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        load()
    }

    // MARK: Persistence

    public func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        if let snap = try? Self.decoder.decode(LayoutSnapshot.self, from: data) {
            apply(snapshot: snap)
        }
    }

    public func save() {
        guard let url = fileURL else { return }
        let snap = snapshot()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snap)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence failures must never crash the app; the in-memory state stays valid.
        }
        onChange?()
    }

    public func snapshot() -> LayoutSnapshot {
        LayoutSnapshot(records: records.values.sorted { $0.id < $1.id }, exportedAt: now())
    }

    private func apply(snapshot: LayoutSnapshot) {
        records = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Queries

    public func record(for id: ExtraID) -> ExtraRecord? { records[id] }

    public var newCount: Int { records.values.filter(\.isNew).count }

    public func records(in zone: Zone) -> [ExtraRecord] {
        records.values.filter { $0.zone == zone }.sorted { $0.lastOrderX < $1.lastOrderX }
    }

    public var incompatible: [ExtraRecord] {
        records.values.filter { $0.incompatibleReason != nil }.sorted { $0.displayName < $1.displayName }
    }

    // MARK: Mutations

    /// Records an observation of an extra. New extras are flagged "New" (F-05). Returns the
    /// effective zone for that extra.
    @discardableResult
    public func observe(id: ExtraID, displayName: String, bundleID: String?, physicallyHidden: Bool, orderX: Double) -> ExtraRecord {
        let t = now()
        if var existing = records[id] {
            existing.displayName = displayName
            if let b = bundleID { existing.bundleID = b }
            existing.zone = ZoneResolver.storedZone(afterObserving: physicallyHidden, previous: existing.zone)
            existing.lastSeen = t
            existing.lastOrderX = orderX
            records[id] = existing
            return existing
        }
        let rec = ExtraRecord(
            id: id,
            displayName: displayName,
            bundleID: bundleID,
            zone: ZoneResolver.storedZone(afterObserving: physicallyHidden, previous: nil),
            isNew: true,
            firstSeen: t,
            lastSeen: t,
            lastOrderX: orderX
        )
        records[id] = rec
        return rec
    }

    /// Sets the user's intent for an extra. Pinned/Pocket/Vault semantics are physical for
    /// pinned vs hidden; the store just remembers the flag.
    public func setZone(_ zone: Zone, for id: ExtraID) {
        guard var rec = records[id] else { return }
        rec.zone = zone
        records[id] = rec
    }

    public func dismissNew(_ id: ExtraID) {
        guard var rec = records[id] else { return }
        rec.isNew = false
        records[id] = rec
    }

    public func dismissAllNew() {
        for (k, var v) in records where v.isNew {
            v.isNew = false
            records[k] = v
        }
    }

    public func setIncompatible(_ id: ExtraID, reason: String?) {
        guard var rec = records[id] else { return }
        rec.incompatibleReason = reason
        records[id] = rec
    }

    /// F-07: reset all assignments to defaults.
    public func reset() {
        records.removeAll()
    }

    /// Drops records not seen for a long time so the file does not grow forever.
    public func prune(olderThan interval: TimeInterval) {
        let cutoff = now().addingTimeInterval(-interval)
        records = records.filter { $0.value.lastSeen >= cutoff }
    }

    // MARK: Export / import (F-64)

    public func exportJSON() throws -> Data {
        try Self.encoder.encode(snapshot())
    }

    public func importJSON(_ data: Data) throws {
        let snap = try Self.decoder.decode(LayoutSnapshot.self, from: data)
        guard snap.version <= LayoutSnapshot.currentVersion else {
            throw LayoutStoreError.unsupportedVersion(snap.version)
        }
        apply(snapshot: snap)
    }
}

public enum LayoutStoreError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return "This layout file was written by a newer PeekBar (version \(v))."
        }
    }
}
