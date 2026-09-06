import XCTest
@testable import PeekBarCore

final class DisplayDedupeTests: XCTestCase {
    // Primary 0..1512, a 1920-wide display to the left sharing the top edge: -1920..0, delta -1512.
    let left = SecondaryDisplay(minX: -1920, maxX: 0, delta: -1512)

    func testOnScreenCopiesInsideSecondaryAreDropped() {
        let windows = [
            StatusWindowStub(id: 1, minX: 1200, width: 38, name: "WiFi", isOnScreen: true),   // primary
            StatusWindowStub(id: 2, minX: -312, width: 38, name: "WiFi", isOnScreen: true),   // left display copy
            StatusWindowStub(id: 3, minX: -700, width: 32, name: "Item-0", isOnScreen: false), // hidden primary item
        ]
        let copies = DisplayDedupe.copies(in: windows, secondaries: [left])
        XCTAssertEqual(copies, [2])
    }

    func testOffScreenCopiesOfHiddenItemsMatchByDelta() {
        let windows = [
            StatusWindowStub(id: 3, minX: -700, width: 32, name: nil, isOnScreen: false),   // hidden primary
            StatusWindowStub(id: 4, minX: -2212, width: 32, name: nil, isOnScreen: false),  // its left-display copy
            StatusWindowStub(id: 5, minX: -760, width: 40, name: nil, isOnScreen: false),   // another hidden primary
        ]
        XCTAssertEqual(DisplayDedupe.copies(in: windows, secondaries: [left]), [4])
    }

    func testNoSecondaryDisplaysMeansNoCopies() {
        let windows = [StatusWindowStub(id: 1, minX: 1200, width: 38, isOnScreen: true), StatusWindowStub(id: 2, minX: -312, width: 38, isOnScreen: true)]
        XCTAssertTrue(DisplayDedupe.copies(in: windows, secondaries: []).isEmpty)
    }

    func testRightDisplay() {
        let right = SecondaryDisplay(minX: 1512, maxX: 4072, delta: 2560)
        let windows = [
            StatusWindowStub(id: 1, minX: 1200, width: 38, name: "Sound", isOnScreen: true),
            StatusWindowStub(id: 2, minX: 3760, width: 38, name: "Sound", isOnScreen: true),
            StatusWindowStub(id: 3, minX: -600, width: 38, name: "Other", isOnScreen: false),
        ]
        XCTAssertEqual(DisplayDedupe.copies(in: windows, secondaries: [right]), [2])
    }
}
