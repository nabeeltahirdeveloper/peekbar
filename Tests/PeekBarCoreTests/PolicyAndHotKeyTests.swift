import XCTest
@testable import PeekBarCore

final class PolicyAndHotKeyTests: XCTestCase {
    func testCloseBehavior() {
        XCTAssertTrue(PopupCloseBehavior.smart.shouldClose(menuOpened: true))
        XCTAssertFalse(PopupCloseBehavior.smart.shouldClose(menuOpened: false))
        XCTAssertTrue(PopupCloseBehavior.always.shouldClose(menuOpened: false))
        XCTAssertFalse(PopupCloseBehavior.never.shouldClose(menuOpened: true))
    }

    func testAutoCloseAndRefresh() {
        XCTAssertNil(AutoCloseOption.off.seconds)
        XCTAssertEqual(AutoCloseOption.thirty.seconds, 30)
        XCTAssertEqual(LiveRefreshRate.twoHz.interval, 0.5)
        XCTAssertNil(LiveRefreshRate.off.interval)
    }

    func testActivationOutcome() {
        XCTAssertTrue(ActivationOutcome.menuOpened.succeeded)
        XCTAssertTrue(ActivationOutcome.activated.succeeded)
        XCTAssertFalse(ActivationOutcome.needsAccessibility.succeeded)
        XCTAssertEqual(ActivationOutcome.notVisible("under the notch").failureReason, "under the notch")
        XCTAssertNotNil(ActivationOutcome.needsAccessibility.failureReason)
    }

    func testKeyComboDisplayAndUsability() {
        XCTAssertEqual(KeyCombo.defaultCombo.displayString, "⌥⌘B")
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: KeyCombo.control | KeyCombo.shift).displayString, "⌃⇧Space")
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: KeyCombo.shift).isUsable)
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: KeyCombo.control).isUsable)
        // Unrelated modifier bits (e.g. caps lock) are stripped.
        XCTAssertEqual(KeyCombo(keyCode: 0, modifiers: KeyCombo.cmd | 0x400).modifiers, KeyCombo.cmd)
    }

    func testKeyComboRoundTripsThroughJSON() throws {
        let combo = KeyCombo(keyCode: 35, modifiers: KeyCombo.cmd | KeyCombo.shift)
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), combo)
    }

    func testConflictDetection() {
        let system = [
            SystemHotKey(keyCode: 49, modifiers: KeyCombo.cmd, enabled: true),          // ⌘Space Spotlight
            SystemHotKey(keyCode: 49, modifiers: KeyCombo.cmd | KeyCombo.option, enabled: false),
        ]
        XCTAssertTrue(HotKeyConflictChecker.conflicts(KeyCombo(keyCode: 49, modifiers: KeyCombo.cmd), with: system))
        XCTAssertFalse(HotKeyConflictChecker.conflicts(KeyCombo(keyCode: 49, modifiers: KeyCombo.cmd | KeyCombo.option), with: system))
        XCTAssertFalse(HotKeyConflictChecker.conflicts(KeyCombo.defaultCombo, with: system))
    }
}
