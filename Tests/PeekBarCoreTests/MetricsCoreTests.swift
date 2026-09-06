import XCTest
@testable import PeekBarCore

final class HistoryBufferTests: XCTestCase {
    func testAppendsAndWraps() {
        var b = HistoryBuffer<Int>(capacity: 3)
        XCTAssertNil(b.last)
        for i in 1...5 { b.append(i) }
        XCTAssertEqual(b.values, [3, 4, 5])
        XCTAssertEqual(b.last, 5)
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b.suffix(2), [4, 5])
        b.removeAll()
        XCTAssertTrue(b.isEmpty)
    }

    func testMetricHistory() {
        var h = MetricHistory(capacity: 2)
        h.record(0.1, for: .cpuTotal)
        h.record(0.2, for: .cpuTotal)
        h.record(0.3, for: .cpuTotal)
        XCTAssertEqual(h.values(for: .cpuTotal), [0.2, 0.3])
        XCTAssertEqual(h.latest(.cpuTotal), 0.3)
        XCTAssertEqual(h.values(for: .ramUsed), [])
    }
}

final class CPUTickMathTests: XCTestCase {
    func testLoadBetweenSamples() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 870, nice: 0)
        let load = CPUTickMath.load(previous: a, current: b)!
        XCTAssertEqual(load.user, 0.6, accuracy: 0.001)
        XCTAssertEqual(load.system, 0.2, accuracy: 0.001)
        XCTAssertEqual(load.busy, 0.8, accuracy: 0.001)
        XCTAssertNil(CPUTickMath.load(previous: a, current: a))
        XCTAssertNil(CPUTickMath.load(previous: b, current: a))
    }

    func testSplitCores() {
        let split = CPUTickMath.splitCores([0.1, 0.3, 0.8, 1.0], efficiencyCount: 2)
        XCTAssertEqual(split.efficiency!, 0.2, accuracy: 0.001)
        XCTAssertEqual(split.performance!, 0.9, accuracy: 0.001)
        XCTAssertNil(CPUTickMath.splitCores([0.5, 0.5], efficiencyCount: 0).performance)
    }
}

final class RateMathTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)
    func testRate() {
        XCTAssertEqual(RateMath.rate(previousBytes: 1000, previousTime: t0, currentBytes: 3000, currentTime: t0.addingTimeInterval(2))!, 1000)
        XCTAssertNil(RateMath.rate(previousBytes: 1000, previousTime: t0, currentBytes: 3000, currentTime: t0))
        XCTAssertNil(RateMath.rate(previousBytes: 3000, previousTime: t0, currentBytes: 1000, currentTime: t0.addingTimeInterval(1)))
    }

    func testThirtyTwoBitWrap() {
        let wrap = UInt64(UInt32.max) + 1
        let r = RateMath.rate(previousBytes: wrap - 500, previousTime: t0, currentBytes: 500, currentTime: t0.addingTimeInterval(1), wrapAt: wrap)
        XCTAssertEqual(r!, 1000)
        // A drop larger than half the range is a reset, not a wrap.
        XCTAssertNil(RateMath.rate(previousBytes: wrap - 500, previousTime: t0, currentBytes: wrap / 2 + 1000, currentTime: t0.addingTimeInterval(1), wrapAt: wrap))
    }

    func testTracker() {
        var tr = RateTracker()
        XCTAssertNil(tr.update("en0", bytes: 100, at: t0))
        XCTAssertEqual(tr.update("en0", bytes: 300, at: t0.addingTimeInterval(1))!, 200)
        XCTAssertNil(tr.update("en1", bytes: 5, at: t0.addingTimeInterval(1)))
        tr.reset()
        XCTAssertNil(tr.update("en0", bytes: 400, at: t0.addingTimeInterval(2)))
    }
}

final class MemoryMathTests: XCTestCase {
    func testBreakdown() {
        let page: UInt64 = 16_384
        let total: UInt64 = 1000 * page
        let s = VMStatsInput(free: 200, active: 300, inactive: 100, wired: 150, speculative: 10, compressor: 50, purgeable: 20, external: 180, internalPages: 320)
        let r = MemoryMath.breakdown(s, pageSize: page, total: total)
        XCTAssertEqual(r.app, 300 * page)
        XCTAssertEqual(r.wired, 150 * page)
        XCTAssertEqual(r.compressed, 50 * page)
        XCTAssertEqual(r.cached, 200 * page)
        XCTAssertEqual(r.used, 500 * page)
        XCTAssertEqual(r.free, 500 * page)
        XCTAssertEqual(r.usedFraction, 0.5, accuracy: 0.0001)
    }

    func testPressure() {
        XCTAssertEqual(MemoryMath.pressure(fromFreeLevel: 60), .normal)
        XCTAssertEqual(MemoryMath.pressure(fromFreeLevel: 15), .warning)
        XCTAssertEqual(MemoryMath.pressure(fromFreeLevel: 3), .critical)
    }
}

final class UnitFormatterTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(UnitFormatter.bytes(UInt64(512)), "512 B")
        XCTAssertEqual(UnitFormatter.bytes(UInt64(1536)), "1.50 KiB")
        XCTAssertEqual(UnitFormatter.bytes(UInt64(15 * 1024 * 1024)), "15.0 MiB")
        XCTAssertEqual(UnitFormatter.bytes(UInt64(250) * 1024 * 1024 * 1024), "250 GiB")
        XCTAssertEqual(UnitFormatter.bytes(UInt64(1_500_000), style: .decimal), "1.50 MB")
    }

    func testRatesAndPercent() {
        XCTAssertEqual(UnitFormatter.rate(bytesPerSecond: 1_200_000), "1.20 MB/s")
        XCTAssertEqual(UnitFormatter.compactRate(bytesPerSecond: 1_234_567), "1.2 M")
        XCTAssertEqual(UnitFormatter.compactRate(bytesPerSecond: 42), "42 B")
        XCTAssertEqual(UnitFormatter.percent(0.456), "46%")
        XCTAssertEqual(UnitFormatter.percent(0.456, decimals: 1), "45.6%")
    }

    func testTemperatureDurationPower() {
        XCTAssertEqual(UnitFormatter.temperature(50, unit: .celsius), "50°C")
        XCTAssertEqual(UnitFormatter.temperature(50, unit: .fahrenheit), "122°F")
        XCTAssertEqual(UnitFormatter.duration(minutes: 135), "2h 15m")
        XCTAssertEqual(UnitFormatter.duration(minutes: 60), "1h")
        XCTAssertEqual(UnitFormatter.duration(minutes: 0), "<1m")
        XCTAssertEqual(UnitFormatter.power(watts: 7.4), "7.4 W")
        XCTAssertEqual(UnitFormatter.power(watts: 65), "65 W")
    }
}

final class DemandSetTests: XCTestCase {
    func testDemandUnionRespectsEnabled() {
        let d = DemandSet(popupModules: [.cpu, .ram], widgetModules: [.network], alertModules: [.battery, .gpu], enabledModules: [.cpu, .ram, .network, .battery])
        XCTAssertEqual(d.demanded, [.cpu, .ram, .network, .battery])
        XCTAssertEqual(d.interval(for: .cpu, base: 1), 1)
        XCTAssertEqual(d.interval(for: .battery, base: 1), 5)
        XCTAssertEqual(d.interval(for: .battery, base: 10), 10)
        XCTAssertTrue(DemandSet().demanded.isEmpty)
    }
}

final class DashboardLayoutTests: XCTestCase {
    func testLegacyOverloadUnchanged() {
        let a = PopupLayout.compute(tileCount: 7, showLabels: true, showSearch: false, maxHeight: 500)
        let b = PopupLayout.compute(tileCount: 7, showLabels: true, showSearch: false, dashboardCards: 0, detailHeight: nil, maxHeight: 500)
        XCTAssertEqual(a, b)
    }

    func testDashboardForcesFullWidth() {
        let l = PopupLayout.compute(tileCount: 4, showLabels: false, showSearch: false, dashboardCards: 2, detailHeight: nil, maxHeight: 600)
        XCTAssertEqual(l.columns, 6)
        XCTAssertEqual(l.size.width, PopupLayout.fullWidth)
        let expected: CGFloat = 24 + 64 + 8 + 56
        XCTAssertEqual(l.size.height, expected)
    }

    func testDashboardRowsAndEmptyFooter() {
        XCTAssertEqual(PopupLayout.dashboardBlockHeight(cards: 5), 208) // 3 rows * 64 + 2 gaps * 8
        let l = PopupLayout.compute(tileCount: 0, showLabels: false, showSearch: false, dashboardCards: 5, detailHeight: nil, maxHeight: 600)
        let expected: CGFloat = 280 // 24 top + 208 dashboard + 8 gap + 40 bottom
        XCTAssertEqual(l.size.height, expected)
        XCTAssertEqual(l.rows, 0)
    }

    func testDetailPageHeightAndCap() {
        let l = PopupLayout.compute(tileCount: 9, showLabels: true, showSearch: true, dashboardCards: 3, detailHeight: 300, maxHeight: 600)
        let expected: CGFloat = 24 + 28 + 8 + 300
        XCTAssertEqual(l.size.height, expected)
        XCTAssertEqual(l.size.width, PopupLayout.fullWidth)
        let capped = PopupLayout.compute(tileCount: 0, showLabels: false, showSearch: false, dashboardCards: 0, detailHeight: 900, maxHeight: 500)
        XCTAssertEqual(capped.size.height, 500)
    }

    func testCardWidthFitsTwoColumns() {
        XCTAssertEqual(PopupLayout.cardWidth * 2 + PopupLayout.spacing + PopupLayout.padding * 2, PopupLayout.fullWidth)
    }
}
