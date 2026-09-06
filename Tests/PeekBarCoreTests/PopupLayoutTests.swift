import XCTest
@testable import PeekBarCore

final class PopupLayoutTests: XCTestCase {
    func testEmptyLayout() {
        let l = PopupLayout.compute(tileCount: 0, showLabels: false, showSearch: false, maxHeight: 600)
        XCTAssertEqual(l.columns, 0)
        XCTAssertEqual(l.size, PopupLayout.emptyStateSize)
    }

    func testGridWrapsAndGrowsDownward() {
        let l = PopupLayout.compute(tileCount: 14, showLabels: false, showSearch: false, maxHeight: 600)
        XCTAssertEqual(l.columns, 6)
        XCTAssertEqual(l.rows, 3)
        let expectedWidth: CGFloat = 24 + 336 + 40
        let expectedHeight: CGFloat = 24 + 168 + 16
        XCTAssertEqual(l.size.width, expectedWidth)
        XCTAssertEqual(l.size.height, expectedHeight)
    }

    func testSmallCountsShrinkWidthButKeepMinimumColumns() {
        let l = PopupLayout.compute(tileCount: 2, showLabels: true, showSearch: false, maxHeight: 600)
        XCTAssertEqual(l.columns, 3)
        XCTAssertEqual(l.rows, 1)
        let expectedHeight: CGFloat = 24 + 56 + 16
        XCTAssertEqual(l.size.height, expectedHeight)
    }

    func testHeightIsCappedForScrolling() {
        let l = PopupLayout.compute(tileCount: 60, showLabels: true, showSearch: true, maxHeight: 300)
        XCTAssertEqual(l.size.height, 300)
        XCTAssertEqual(l.rows, 10)
    }

    func testSearchThreshold() {
        XCTAssertFalse(PopupLayout.shouldShowSearch(tileCount: 12, threshold: 12, userTyped: false))
        XCTAssertTrue(PopupLayout.shouldShowSearch(tileCount: 13, threshold: 12, userTyped: false))
        XCTAssertTrue(PopupLayout.shouldShowSearch(tileCount: 2, threshold: 12, userTyped: true))
    }

    func testGridNavigation() {
        XCTAssertEqual(GridNavigation.move(from: nil, direction: .right, count: 5, columns: 3), 0)
        XCTAssertEqual(GridNavigation.move(from: 0, direction: .left, count: 5, columns: 3), 0)
        XCTAssertEqual(GridNavigation.move(from: 4, direction: .right, count: 5, columns: 3), 4)
        XCTAssertEqual(GridNavigation.move(from: 1, direction: .down, count: 5, columns: 3), 4)
        XCTAssertEqual(GridNavigation.move(from: 2, direction: .down, count: 5, columns: 3), 2)
        XCTAssertEqual(GridNavigation.move(from: 4, direction: .up, count: 5, columns: 3), 1)
        XCTAssertNil(GridNavigation.move(from: 0, direction: .up, count: 0, columns: 3))
    }

    func testSearchFilter() {
        XCTAssertTrue(SearchFilter.matches(name: "Control Center · Wi‑Fi", query: "wi"))
        XCTAssertTrue(SearchFilter.matches(name: "Éclair", query: "ecl"))
        XCTAssertTrue(SearchFilter.matches(name: "Anything", query: "   "))
        XCTAssertFalse(SearchFilter.matches(name: "Weather", query: "vpn"))
        XCTAssertTrue(SearchFilter.matches(name: "Microsoft Teams", query: "micro teams"))
    }
}
