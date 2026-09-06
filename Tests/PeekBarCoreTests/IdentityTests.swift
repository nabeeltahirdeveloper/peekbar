import XCTest
@testable import PeekBarCore

final class IdentityTests: XCTestCase {
    func testBundleAndTitleFormKey() {
        let s = IdentitySource(bundleID: "com.example.app", title: "VPN", windowName: "Item-0", width: 30, minX: 10)
        XCTAssertEqual(ExtraIdentity.baseKey(s), "com.example.app|VPN")
    }

    func testWindowNameUsedWhenNoTitle() {
        let s = IdentitySource(bundleID: "com.apple.controlcenter", title: nil, windowName: "WiFi", width: 30, minX: 10)
        XCTAssertEqual(ExtraIdentity.baseKey(s), "com.apple.controlcenter|WiFi")
    }

    func testUnknownOwnerFallsBackToWidthSignature() {
        let s = IdentitySource(bundleID: nil, title: nil, windowName: nil, width: 37.6, minX: 10)
        XCTAssertEqual(ExtraIdentity.baseKey(s), "unknown|w38")
    }

    func testDuplicatesGetOrdinalsInLeftToRightOrder() {
        let sources = [
            IdentitySource(bundleID: "com.a", title: nil, windowName: nil, width: 30, minX: 500),
            IdentitySource(bundleID: "com.b", title: nil, windowName: nil, width: 30, minX: 400),
            IdentitySource(bundleID: "com.a", title: nil, windowName: nil, width: 30, minX: 100),
        ]
        let ids = ExtraIdentity.makeIDs(for: sources)
        XCTAssertEqual(ids[0].raw, "com.a|item#2")
        XCTAssertEqual(ids[1].raw, "com.b|item")
        XCTAssertEqual(ids[2].raw, "com.a|item#1")
    }

    func testIDsAreStableAcrossMoves() {
        // Same extra pushed off-screen by the collapse keeps the same id.
        let visible = IdentitySource(bundleID: "com.x", title: "T", windowName: nil, width: 30, minX: 1200)
        let hidden = IdentitySource(bundleID: "com.x", title: "T", windowName: nil, width: 30, minX: -9000)
        XCTAssertEqual(ExtraIdentity.makeIDs(for: [visible]), ExtraIdentity.makeIDs(for: [hidden]))
    }

    func testDisplayNames() {
        XCTAssertEqual(ExtraIdentity.displayName(bundleID: "com.x", appName: "Weather", title: nil, windowName: "Item-0", siblingCount: 1), "Weather")
        XCTAssertEqual(ExtraIdentity.displayName(bundleID: "com.apple.controlcenter", appName: "Control Center", title: "Wi‑Fi", windowName: nil, siblingCount: 5), "Control Center · Wi‑Fi")
        XCTAssertEqual(ExtraIdentity.displayName(bundleID: nil, appName: nil, title: nil, windowName: nil, siblingCount: 1), "Unknown extra")
        XCTAssertEqual(ExtraIdentity.displayName(bundleID: nil, appName: nil, title: nil, windowName: "Clock", siblingCount: 1), "Clock")
    }
}
