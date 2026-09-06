import XCTest
@testable import PeekBarCore

final class GeometryTests: XCTestCase {
    // A 14-inch MacBook Pro: 1512x982, 32pt housing, notch between x=663 and x=848.
    let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 87, width: 1512, height: 862),
        safeAreaTop: 32,
        notch: CGRect(x: 663, y: 950, width: 185, height: 32)
    )
    let external = ScreenGeometry(
        frame: CGRect(x: 1512, y: 100, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 100, width: 2560, height: 1415),
        safeAreaTop: 0,
        notch: nil,
        statusBarThickness: 24
    )

    func testCollapseLengthUsesWidestScreenAndCap() {
        XCTAssertEqual(CollapseMath.collapseLength(screenWidths: [1512, 2560]), 2560)
        XCTAssertEqual(CollapseMath.collapseLength(screenWidths: [1512]), 1512)
        XCTAssertEqual(CollapseMath.collapseLength(screenWidths: []), 1000)
        XCTAssertEqual(CollapseMath.collapseLength(screenWidths: [640]), 1000)
        XCTAssertEqual(CollapseMath.collapseLength(screenWidths: [20_000]), 10_000)
    }

    func testCoordinateConversion() {
        let cg = CGRect(x: 100, y: 0, width: 40, height: 33)
        let cocoa = CoordinateSpace.cocoaRect(fromCG: cg, primaryScreenHeight: 982)
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 949, width: 40, height: 33))
        XCTAssertEqual(CoordinateSpace.cgRect(fromCocoa: cocoa, primaryScreenHeight: 982), cg)
        XCTAssertEqual(CoordinateSpace.cgPoint(fromCocoa: CGPoint(x: 5, y: 982), primaryScreenHeight: 982), CGPoint(x: 5, y: 0))
    }

    func testMenuBarBandOnNotchedAndPlainDisplays() {
        XCTAssertEqual(notched.menuBarBandHeight, 32)
        XCTAssertEqual(notched.menuBarBottom, 950)
        XCTAssertEqual(external.menuBarBandHeight, 25)
        XCTAssertEqual(external.menuBarBottom, 1515)
        let autoHidden = ScreenGeometry(frame: external.frame, visibleFrame: external.frame, safeAreaTop: 0, notch: nil, statusBarThickness: 24)
        XCTAssertEqual(autoHidden.menuBarBandHeight, 26)
    }

    func testPopupOpensBelowMenuBarBandRightAlignedToAnchor() {
        let f = PopupPositioner.frame(anchorMaxX: 1300, size: CGSize(width: 400, height: 200), on: notched)
        XCTAssertEqual(f.maxY, 950 - PopupPositioner.gap)
        XCTAssertEqual(f.maxX, 1300)
        XCTAssertEqual(f.height, 200)
        // Never inside the camera housing band.
        XCTAssertLessThanOrEqual(f.maxY, notched.notch!.minY)
    }

    func testPopupClampsToScreenEdges() {
        let left = PopupPositioner.frame(anchorMaxX: 100, size: CGSize(width: 400, height: 200), on: notched)
        XCTAssertEqual(left.minX, PopupPositioner.margin)
        let right = PopupPositioner.frame(anchorMaxX: 5000, size: CGSize(width: 400, height: 200), on: notched)
        XCTAssertEqual(right.maxX, 1512 - PopupPositioner.margin)
        let tall = PopupPositioner.frame(anchorMaxX: 1300, size: CGSize(width: 400, height: 5000), on: notched)
        XCTAssertEqual(tall.height, PopupPositioner.maxHeight(on: notched))
        XCTAssertGreaterThanOrEqual(tall.minY, notched.visibleFrame.minY)
    }

    func testPopupOnExternalDisplayStaysOnThatDisplay() {
        let anchor = PopupPositioner.mirroredAnchorMaxX(anchorMaxX: 1300, from: notched, to: external)
        XCTAssertEqual(anchor, 1512 + 2560 - 212)
        let f = PopupPositioner.frame(anchorMaxX: anchor, size: CGSize(width: 400, height: 200), on: external)
        XCTAssertTrue(external.frame.contains(f))
        XCTAssertEqual(f.maxY, external.menuBarBottom - PopupPositioner.gap)
    }

    func testVisibilityCheckDetectsNotchAndOffscreen() {
        XCTAssertTrue(VisibilityCheck.isFullyVisible(itemFrame: CGRect(x: 1200, y: 949, width: 30, height: 33), on: notched))
        XCTAssertFalse(VisibilityCheck.isFullyVisible(itemFrame: CGRect(x: 700, y: 949, width: 30, height: 33), on: notched))
        XCTAssertFalse(VisibilityCheck.isFullyVisible(itemFrame: CGRect(x: 650, y: 949, width: 30, height: 33), on: notched))
        XCTAssertFalse(VisibilityCheck.isFullyVisible(itemFrame: CGRect(x: -3000, y: 949, width: 30, height: 33), on: notched))
        XCTAssertTrue(VisibilityCheck.isFullyVisible(itemFrame: CGRect(x: 2000, y: 1515, width: 30, height: 24), on: external))
    }

    func testNotchOverflow() {
        XCTAssertEqual(notched.statusAreaWidth, 664)
        XCTAssertFalse(NotchFit.overflows(itemWidths: Array(repeating: 30, count: 20), availableWidth: 664))
        XCTAssertTrue(NotchFit.overflows(itemWidths: Array(repeating: 30, count: 23), availableWidth: 664))
    }
}

final class RevealMathTests: XCTestCase {
    let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 87, width: 1512, height: 862),
        safeAreaTop: 32,
        notch: CGRect(x: 663, y: 950, width: 185, height: 32)
    )

    func testDrawableBoundary() {
        XCTAssertEqual(RevealMath.drawableMinX(on: notched), 848 + 44)
        let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: .zero, safeAreaTop: 0, notch: nil)
        XCTAssertEqual(RevealMath.drawableMinX(on: plain), 1280)
    }

    func testBringingHiddenItemToBoundary() {
        // Collapsed length 1512, item at -777; bring it to 900: shorten by 1677 -> clamp to min.
        XCTAssertEqual(RevealMath.length(current: 1512, itemMinX: -777, targetMinX: 900, minLength: 34), 34)
        // Item at -100 -> 900 needs a shift of 1000: 512.
        XCTAssertEqual(RevealMath.length(current: 1512, itemMinX: -100, targetMinX: 900, minLength: 34), 512)
        // Already right of the target: no change beyond rounding.
        XCTAssertEqual(RevealMath.length(current: 1512, itemMinX: 950, targetMinX: 900, minLength: 34), 1562)
    }

    func testLeftEdgePlacement() {
        XCTAssertEqual(RevealMath.length(rightEdge: 923, leftEdgeAt: 700, minLength: 34), 223)
        XCTAssertEqual(RevealMath.length(rightEdge: 923, leftEdgeAt: 920, minLength: 34), 34)
    }
}
