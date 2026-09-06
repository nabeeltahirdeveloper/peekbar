import XCTest
@testable import PeekBarCore

final class ZoneAndStoreTests: XCTestCase {
    func testHiddenWhenLeftOfSeparator() {
        XCTAssertTrue(ZoneResolver.isHidden(itemMinX: -4000, separatorMinX: -3800))
        XCTAssertFalse(ZoneResolver.isHidden(itemMinX: 1300, separatorMinX: -3800))
        // Expanded state: separator at 1100, item right of it.
        XCTAssertFalse(ZoneResolver.isHidden(itemMinX: 1110, separatorMinX: 1100))
        XCTAssertTrue(ZoneResolver.isHidden(itemMinX: 1050, separatorMinX: 1100))
    }

    func testEffectiveZone() {
        XCTAssertEqual(ZoneResolver.effectiveZone(physicallyHidden: false, storedZone: .vault), .pinned)
        XCTAssertEqual(ZoneResolver.effectiveZone(physicallyHidden: true, storedZone: nil), .pocket)
        XCTAssertEqual(ZoneResolver.effectiveZone(physicallyHidden: true, storedZone: .vault), .vault)
        XCTAssertEqual(ZoneResolver.effectiveZone(physicallyHidden: true, storedZone: .pinned), .pocket)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peekbar-tests-\(UUID().uuidString)")
            .appendingPathComponent("layout.json")
    }

    func testNewExtrasDefaultToPocketAndAreFlaggedNew() {
        let store = LayoutStore(fileURL: nil)
        let rec = store.observe(id: ExtraID("com.x|item"), displayName: "X", bundleID: "com.x", physicallyHidden: true, orderX: 5)
        XCTAssertEqual(rec.zone, .pocket)
        XCTAssertTrue(rec.isNew)
        XCTAssertEqual(store.newCount, 1)
        store.dismissNew(rec.id)
        XCTAssertEqual(store.newCount, 0)
    }

    func testVaultFlagSurvivesObservationWhileHiddenButNotWhenPinned() {
        let store = LayoutStore(fileURL: nil)
        let id = ExtraID("com.x|item")
        store.observe(id: id, displayName: "X", bundleID: "com.x", physicallyHidden: true, orderX: 0)
        store.setZone(.vault, for: id)
        XCTAssertEqual(store.observe(id: id, displayName: "X", bundleID: nil, physicallyHidden: true, orderX: 0).zone, .vault)
        XCTAssertEqual(store.observe(id: id, displayName: "X", bundleID: nil, physicallyHidden: false, orderX: 0).zone, .pinned)
    }

    func testPersistenceRoundTrip() throws {
        let url = tempURL()
        let store = LayoutStore(fileURL: url)
        let id = ExtraID("com.x|item")
        store.observe(id: id, displayName: "X", bundleID: "com.x", physicallyHidden: true, orderX: 42)
        store.setZone(.vault, for: id)
        store.setIncompatible(id, reason: "no menu")
        store.save()

        let reloaded = LayoutStore(fileURL: url)
        let rec = try XCTUnwrap(reloaded.record(for: id))
        XCTAssertEqual(rec.zone, .vault)
        XCTAssertEqual(rec.displayName, "X")
        XCTAssertEqual(rec.incompatibleReason, "no menu")
        XCTAssertEqual(rec.lastOrderX, 42)
        XCTAssertTrue(rec.isNew)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testResetAndExportImport() throws {
        let store = LayoutStore(fileURL: nil)
        store.observe(id: ExtraID("a|item"), displayName: "A", bundleID: "a", physicallyHidden: true, orderX: 0)
        store.observe(id: ExtraID("b|item"), displayName: "B", bundleID: "b", physicallyHidden: false, orderX: 1)
        let data = try store.exportJSON()
        store.reset()
        XCTAssertTrue(store.records.isEmpty)
        try store.importJSON(data)
        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.records(in: .pinned).map(\.displayName), ["B"])
    }

    func testImportRejectsNewerVersion() {
        let store = LayoutStore(fileURL: nil)
        let json = #"{"version": 99, "records": []}"#.data(using: .utf8)!
        XCTAssertThrowsError(try store.importJSON(json))
    }

    func testPrune() {
        var clock = Date(timeIntervalSince1970: 0)
        let store = LayoutStore(fileURL: nil, now: { clock })
        store.observe(id: ExtraID("old|item"), displayName: "Old", bundleID: nil, physicallyHidden: true, orderX: 0)
        clock = clock.addingTimeInterval(100 * 86_400)
        store.observe(id: ExtraID("new|item"), displayName: "New", bundleID: nil, physicallyHidden: true, orderX: 0)
        store.prune(olderThan: 30 * 86_400)
        XCTAssertNil(store.record(for: ExtraID("old|item")))
        XCTAssertNotNil(store.record(for: ExtraID("new|item")))
    }
}
