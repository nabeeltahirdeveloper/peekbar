import XCTest
@testable import PeekBarCore

final class AlertEvaluatorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testSpikeShorterThanDurationDoesNotFire() {
        var e = AlertEvaluator(rules: [AlertRule(metric: .cpuTotal, threshold: 0.9, duration: 10)])
        XCTAssertTrue(e.evaluate(value: 0.95, for: .cpuTotal, at: at(0)).isEmpty)
        XCTAssertTrue(e.evaluate(value: 0.95, for: .cpuTotal, at: at(5)).isEmpty)
        XCTAssertTrue(e.evaluate(value: 0.2, for: .cpuTotal, at: at(6)).isEmpty)
        XCTAssertTrue(e.evaluate(value: 0.95, for: .cpuTotal, at: at(12)).isEmpty) // breach restarted
    }

    func testSustainedBreachFiresOnceThenClearsWithHysteresis() {
        let rule = AlertRule(metric: .cpuTotal, threshold: 0.9, duration: 10, hysteresis: 0.05, cooldown: 60)
        var e = AlertEvaluator(rules: [rule])
        XCTAssertTrue(e.evaluate(value: 0.95, for: .cpuTotal, at: at(0)).isEmpty)
        let fired = e.evaluate(value: 0.96, for: .cpuTotal, at: at(10))
        XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(fired[0].isFired)
        XCTAssertEqual(fired[0].value, 0.96)
        XCTAssertTrue(e.isActive(rule.id))
        // Still breaching: no repeat.
        XCTAssertTrue(e.evaluate(value: 0.97, for: .cpuTotal, at: at(20)).isEmpty)
        // Dips inside the hysteresis band: still active.
        XCTAssertTrue(e.evaluate(value: 0.88, for: .cpuTotal, at: at(21)).isEmpty)
        XCTAssertTrue(e.isActive(rule.id))
        // Crosses below threshold - hysteresis: clears.
        let cleared = e.evaluate(value: 0.80, for: .cpuTotal, at: at(22))
        XCTAssertEqual(cleared.count, 1)
        XCTAssertFalse(cleared[0].isFired)
        XCTAssertFalse(e.isActive(rule.id))
    }

    func testCooldownSuppressesRefire() {
        let rule = AlertRule(metric: .cpuTotal, threshold: 0.9, duration: 0, hysteresis: 0.05, cooldown: 100)
        var e = AlertEvaluator(rules: [rule])
        XCTAssertEqual(e.evaluate(value: 0.95, for: .cpuTotal, at: at(0)).count, 1)
        XCTAssertEqual(e.evaluate(value: 0.5, for: .cpuTotal, at: at(1)).count, 1)   // cleared
        XCTAssertTrue(e.evaluate(value: 0.95, for: .cpuTotal, at: at(2)).isEmpty)     // within cooldown
        XCTAssertEqual(e.evaluate(value: 0.95, for: .cpuTotal, at: at(101)).count, 1) // cooldown over
    }

    func testBelowComparatorAndUnrelatedKeys() {
        let rule = AlertRule(metric: .batteryLevel, comparator: .below, threshold: 0.2, duration: 0, hysteresis: 0.05)
        var e = AlertEvaluator(rules: [rule])
        XCTAssertTrue(e.evaluate(value: 0.1, for: .cpuTotal, at: at(0)).isEmpty)
        XCTAssertEqual(e.evaluate(value: 0.15, for: .batteryLevel, at: at(0)).count, 1)
        XCTAssertTrue(e.evaluate(value: 0.22, for: .batteryLevel, at: at(1)).isEmpty) // inside band
        XCTAssertEqual(e.evaluate(value: 0.3, for: .batteryLevel, at: at(2)).count, 1)
    }

    func testDisabledRulesAndSetRulesKeepsState() {
        var rule = AlertRule(metric: .cpuTotal, threshold: 0.5, duration: 0)
        var e = AlertEvaluator(rules: [rule])
        XCTAssertEqual(e.evaluate(value: 0.9, for: .cpuTotal, at: at(0)).count, 1)
        e.setRules([rule])
        XCTAssertTrue(e.isActive(rule.id))
        rule.enabled = false
        e.setRules([rule])
        XCTAssertTrue(e.evaluate(value: 0.1, for: .cpuTotal, at: at(1)).isEmpty)
        e.setRules([])
        XCTAssertFalse(e.isActive(rule.id))
    }

    func testDefaultsAndCodable() throws {
        XCTAssertEqual(AlertRule.defaultHysteresis(for: .cpuTotal, threshold: 0.9), 0.05)
        XCTAssertEqual(AlertRule.defaultHysteresis(for: .cpuTemperature, threshold: 90), 3)
        XCTAssertEqual(AlertRule.defaultHysteresis(for: .networkDown, threshold: 1_000_000), 100_000)
        let r = AlertRule.defaultRule
        let data = try JSONEncoder().encode([r])
        XCTAssertEqual(try JSONDecoder().decode([AlertRule].self, from: data), [r])
    }
}
