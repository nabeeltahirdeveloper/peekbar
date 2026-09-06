import XCTest
@testable import PeekBarCore

final class WidgetTests: XCTestCase {
    func testAllowedAndDefaultStyles() {
        for m in ModuleID.allCases {
            XCTAssertTrue(WidgetLayoutMath.allowedStyles(for: m).contains(WidgetLayoutMath.defaultStyle(for: m)), "\(m)")
        }
        XCTAssertEqual(WidgetLayoutMath.defaultStyle(for: .network), .speed)
        XCTAssertEqual(WidgetLayoutMath.defaultStyle(for: .battery), .battery)
        XCTAssertEqual(WidgetConfig(module: .cpu).style, .mini)
    }

    func testWidths() {
        XCTAssertEqual(WidgetLayoutMath.width(for: .mini, module: .cpu, coreCount: 8, chartWidth: 44, showLabel: false), 48)
        XCTAssertEqual(WidgetLayoutMath.width(for: .mini, module: .cpu, coreCount: 8, chartWidth: 44, showLabel: true), 64)
        XCTAssertEqual(WidgetLayoutMath.width(for: .lineChart, module: .cpu, coreCount: 8, chartWidth: 60, showLabel: false), 60)
        XCTAssertEqual(WidgetLayoutMath.width(for: .lineChart, module: .cpu, coreCount: 8, chartWidth: 999, showLabel: false), 44)
        XCTAssertEqual(WidgetLayoutMath.width(for: .barChart, module: .cpu, coreCount: 8, chartWidth: 44, showLabel: false), 8 * 2 + 7 + 6)
        XCTAssertEqual(WidgetLayoutMath.width(for: .barChart, module: .cpu, coreCount: 64, chartWidth: 44, showLabel: false), 60)
        XCTAssertEqual(WidgetLayoutMath.width(for: .label, module: .clock, coreCount: 1, chartWidth: 44, showLabel: false), 64)
        XCTAssertEqual(WidgetLayoutMath.width(for: .stateDot, module: .cpu, coreCount: 1, chartWidth: 44, showLabel: false), 10)
    }

    func testChartPointsAndPositions() {
        XCTAssertEqual(WidgetLayoutMath.chartPointCount(width: 44), 20)
        XCTAssertEqual(WidgetLayoutMath.chartPointCount(width: 4), 2)
        XCTAssertEqual(WidgetLayoutMath.preferredPosition(togglePosition: 300, rank: 0), 299)
        XCTAssertEqual(WidgetLayoutMath.preferredPosition(togglePosition: 300, rank: 2), 297)
        XCTAssertEqual(WidgetLayoutMath.preferredPosition(togglePosition: 1, rank: 5), 1)
    }

    func testLoadColor() {
        XCTAssertEqual(WidgetLayoutMath.loadColor(0.1), .normal)
        XCTAssertEqual(WidgetLayoutMath.loadColor(0.6), .elevated)
        XCTAssertEqual(WidgetLayoutMath.loadColor(0.95), .high)
    }

    func testPlacementClassification() {
        // separator 1000..1012, toggle at 1012..1046
        XCTAssertEqual(WidgetPlacementCheck.classify(widgetMinX: 1046, separatorMinX: 1000, separatorMaxX: 1012, toggleMinX: 1012), .pinned)
        XCTAssertEqual(WidgetPlacementCheck.classify(widgetMinX: 900, separatorMinX: 1000, separatorMaxX: 1012, toggleMinX: 1012), .hidden)
        XCTAssertEqual(WidgetPlacementCheck.classify(widgetMinX: 1012, separatorMinX: 1000, separatorMaxX: 1012, toggleMinX: 1040), .interleaved)
        // collapsed: separator spans -500..1012
        XCTAssertEqual(WidgetPlacementCheck.classify(widgetMinX: -900, separatorMinX: -500, separatorMaxX: 1012, toggleMinX: 1012), .hidden)
    }

    func testConfigRoundTrip() throws {
        let c = WidgetConfig(module: .network, style: .speed, showLabel: true, colorMode: .utilization, placement: .hiddenByUser, chartWidth: 60)
        let data = try JSONEncoder().encode([c])
        XCTAssertEqual(try JSONDecoder().decode([WidgetConfig].self, from: data), [c])
    }
}
