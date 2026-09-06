import XCTest
@testable import PeekBarCore

final class SensorCatalogTests: XCTestCase {
    func testDecoders() {
        XCTAssertEqual(SensorCatalog.decode(type: "sp78", bytes: [0x2A, 0x80])!, 42.5, accuracy: 0.001)
        XCTAssertEqual(SensorCatalog.decode(type: "sp78", bytes: [0xFF, 0x80])!, -0.5, accuracy: 0.001)
        XCTAssertEqual(SensorCatalog.decode(type: "fpe2", bytes: [0x0B, 0xB8])!, 750, accuracy: 0.001)
        XCTAssertEqual(SensorCatalog.decode(type: "ui16", bytes: [0x01, 0x02])!, 258)
        XCTAssertEqual(SensorCatalog.decode(type: "ui8 ", bytes: [200])!, 200)
        XCTAssertEqual(SensorCatalog.decode(type: "si8 ", bytes: [0xFE])!, -2)
        let f: Float = 37.25
        let bits = f.bitPattern
        let le = [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24 & 0xFF)]
        XCTAssertEqual(SensorCatalog.decode(type: "flt ", bytes: le)!, 37.25, accuracy: 0.001)
        XCTAssertNil(SensorCatalog.decode(type: "ch8*", bytes: [1, 2, 3]))
        XCTAssertNil(SensorCatalog.decode(type: "flt ", bytes: [1]))
    }

    func testDescribe() {
        XCTAssertEqual(SensorCatalog.describe(key: "TC0P")?.group, .cpu)
        XCTAssertEqual(SensorCatalog.describe(key: "Tp09"), SensorDescriptor(label: "CPU core 09", group: .cpu, unit: .celsius))
        XCTAssertEqual(SensorCatalog.describe(key: "Tg0D")?.group, .gpu)
        XCTAssertEqual(SensorCatalog.describe(key: "F0Ac"), SensorDescriptor(label: "Fan 1", group: .fan, unit: .rpm))
        XCTAssertEqual(SensorCatalog.describe(key: "F1Mx")?.label, "Fan 2 max")
        XCTAssertEqual(SensorCatalog.describe(key: "PSTR")?.unit, .watts)
        XCTAssertEqual(SensorCatalog.describe(key: "VD0R")?.unit, .volts)
        XCTAssertEqual(SensorCatalog.describe(key: "ID0R")?.unit, .amps)
        XCTAssertNil(SensorCatalog.describe(key: "#KEY"))
        XCTAssertNil(SensorCatalog.describe(key: "FNum"))
    }

    func testSanity() {
        XCTAssertTrue(SensorCatalog.isSane(45, unit: .celsius))
        XCTAssertFalse(SensorCatalog.isSane(0, unit: .celsius))
        XCTAssertFalse(SensorCatalog.isSane(200, unit: .celsius))
        XCTAssertFalse(SensorCatalog.isSane(.nan, unit: .watts))
        XCTAssertTrue(SensorCatalog.isSane(0, unit: .rpm))
    }

    func testCuration() {
        var readings: [SensorReading] = []
        for i in 0..<30 { readings.append(SensorReading(key: "Ta\(i)", label: "Ambient \(i)", group: .ambient, value: 30, unit: .celsius)) }
        readings.append(SensorReading(key: "TA0P", label: "Ambient", group: .ambient, value: 31, unit: .celsius))
        readings.append(SensorReading(key: "ID0R", label: "Current D0", group: .current, value: 0, unit: .amps))
        readings.append(SensorReading(key: "IPBR", label: "Current PB", group: .current, value: 0.5, unit: .amps))
        readings.append(SensorReading(key: "PSTR", label: "System total", group: .power, value: 12, unit: .watts))
        readings.append(SensorReading(key: "F0Ac", label: "Fan 1", group: .fan, value: 0, unit: .rpm))
        let basic = SensorCatalog.curate(readings, advanced: false)
        XCTAssertEqual(basic.filter { $0.group == .ambient }.count, 4)
        XCTAssertEqual(basic.first { $0.group == .ambient }?.key, "TA0P")
        XCTAssertTrue(basic.filter { $0.group == .current }.isEmpty)
        XCTAssertTrue(basic.contains { $0.key == "PSTR" })
        XCTAssertTrue(basic.contains { $0.key == "F0Ac" })
        let advanced = SensorCatalog.curate(readings, advanced: true)
        XCTAssertEqual(advanced.filter { $0.group == .current }.map(\.key), ["IPBR"])
        XCTAssertEqual(advanced.filter { $0.group == .ambient }.count, 12)
    }

    func testHIDGroups() {
        XCTAssertEqual(SensorCatalog.hidGroup(forProduct: "PMU tdie1"), .cpu)
        XCTAssertEqual(SensorCatalog.hidGroup(forProduct: "gas gauge battery"), .battery)
        XCTAssertEqual(SensorCatalog.hidGroup(forProduct: "NAND CH0 temp"), .storage)
        XCTAssertEqual(SensorCatalog.hidGroup(forProduct: "PMU TP1w"), .soc)
    }
}

final class ClockFormatterTests: XCTestCase {
    func testOffsetText() {
        let utc = TimeZone(identifier: "UTC")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let noon = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC
        XCTAssertEqual(ClockFormatter.offsetText(utc, relativeTo: utc, at: noon), "same time")
        XCTAssertEqual(ClockFormatter.offsetText(tokyo, relativeTo: utc, at: noon), "+9h, tomorrow")
        XCTAssertEqual(ClockFormatter.offsetText(kolkata, relativeTo: utc, at: noon), "+5h 30m, tomorrow")
        XCTAssertEqual(ClockFormatter.offsetText(utc, relativeTo: tokyo, at: noon), "−9h, yesterday")
    }

    func testEntryUsesLabelOrCity() {
        let clock = WorldClock(timeZoneID: "America/New_York", label: "")
        let e = ClockFormatter.entry(for: clock, now: Date(timeIntervalSince1970: 1_700_000_000), local: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(e.label, "New York")
        XCTAssertEqual(e.time.replacingOccurrences(of: "\u{202F}", with: " "), "5:13 PM")
        XCTAssertTrue(e.offset.hasPrefix("−5h"))
        let labelled = WorldClock(timeZoneID: "America/New_York", label: "HQ")
        XCTAssertEqual(ClockFormatter.entry(for: labelled, now: Date(), locale: Locale(identifier: "en_US")).label, "HQ")
    }

    func testWorldClockCodable() throws {
        let c = WorldClock(timeZoneID: "Europe/Berlin", label: "Berlin")
        let data = try JSONEncoder().encode([c])
        XCTAssertEqual(try JSONDecoder().decode([WorldClock].self, from: data), [c])
    }
}
