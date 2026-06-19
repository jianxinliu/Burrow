//
//  AlertEngineTests.swift
//  BurrowTests
//
//  Threshold-alert hysteresis + cooldown (roadmap D.12), tested by folding a
//  reading sequence through `step` and asserting when it fires.
//

import XCTest
@testable import Burrow

final class AlertEngineTests: XCTestCase {
    private let rule = ThresholdRule(id: "cpu", high: 90, low: 70, cooldownSeconds: 300)

    func testBelowThreshold_neverFires() {
        let r = AlertEngine.step(rule: rule, value: 50, ts: 0, state: AlertState())
        XCTAssertFalse(r.fired)
        XCTAssertFalse(r.state.firing)
    }

    func testCrossingHigh_firesOnce() {
        let r = AlertEngine.step(rule: rule, value: 95, ts: 0, state: AlertState())
        XCTAssertTrue(r.fired)
        XCTAssertTrue(r.state.firing)
        XCTAssertEqual(r.state.lastFiredTS, 0)
    }

    func testStayingHigh_doesNotRefire() {
        let first = AlertEngine.step(rule: rule, value: 95, ts: 0, state: AlertState())
        let second = AlertEngine.step(rule: rule, value: 97, ts: 60, state: first.state)
        XCTAssertFalse(second.fired, "one fire per episode, not per sample")
        XCTAssertTrue(second.state.firing)
    }

    func testDipAboveLow_staysInEpisode() {
        let fire = AlertEngine.step(rule: rule, value: 95, ts: 0, state: AlertState())
        let dip = AlertEngine.step(rule: rule, value: 80, ts: 60, state: fire.state)  // 70<80<90
        XCTAssertTrue(dip.state.firing, "still firing until it recovers below low")
        XCTAssertFalse(dip.fired)
    }

    func testRecoveryBelowLow_endsEpisode() {
        let fire = AlertEngine.step(rule: rule, value: 95, ts: 0, state: AlertState())
        let recover = AlertEngine.step(rule: rule, value: 65, ts: 60, state: fire.state)
        XCTAssertFalse(recover.state.firing)
        XCTAssertFalse(recover.fired)
    }

    func testReCrossWithinCooldown_doesNotFire() {
        var s = AlertEngine.step(rule: rule, value: 95, ts: 0, state: AlertState()).state
        s = AlertEngine.step(rule: rule, value: 65, ts: 100, state: s).state   // recovered
        let again = AlertEngine.step(rule: rule, value: 95, ts: 200, state: s)  // 200-0 < 300
        XCTAssertFalse(again.fired, "still cooling down from the last fire")
        XCTAssertTrue(again.state.firing, "but the episode is armed")
    }

    func testReCrossAfterCooldown_firesAgain() {
        var s = AlertEngine.step(rule: rule, value: 95, ts: 0, state: AlertState()).state
        s = AlertEngine.step(rule: rule, value: 65, ts: 100, state: s).state
        let again = AlertEngine.step(rule: rule, value: 95, ts: 400, state: s)  // 400-0 >= 300
        XCTAssertTrue(again.fired, "new episode past the cooldown fires")
        XCTAssertEqual(again.state.lastFiredTS, 400)
    }
}
