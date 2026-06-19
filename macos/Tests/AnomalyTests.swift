//
//  AnomalyTests.swift
//  BurrowTests
//
//  The baseline-vs-recent regression rules (roadmap A.2), tested through
//  their public verdicts so the thresholds can be tuned without rewriting
//  the specification of *what* counts as a regression.
//

import XCTest
@testable import Burrow

final class AnomalyTests: XCTestCase {
    // MARK: percentile convention

    func testPercentile_interpolatesBetweenSamples() {
        let xs = [0.0, 10, 20, 30, 40]
        XCTAssertEqual(Anomaly.median(xs), 20, accuracy: 0.001)
        XCTAssertEqual(Anomaly.percentile(xs, 100), 40, accuracy: 0.001)
        XCTAssertEqual(Anomaly.percentile(xs, 0), 0, accuracy: 0.001)
    }

    // MARK: process CPU

    func testProcessCPU_stableProcess_notFlagged() {
        let baseline = Array(repeating: 20.0, count: 20) + [22, 18, 21, 19]
        let recent = [20.0, 21, 19, 20, 22, 18]
        XCTAssertFalse(Anomaly.processCPUExceedsBaseline(baseline: baseline, recent: recent))
    }

    func testProcessCPU_sustainedDoubling_flagged() {
        let baseline = Array(repeating: 20.0, count: 20)
        let recent = Array(repeating: 45.0, count: 8)   // clears p95(=20) by 25 pts
        XCTAssertTrue(Anomaly.processCPUExceedsBaseline(baseline: baseline, recent: recent))
    }

    func testProcessCPU_tinyAbsoluteChange_notFlagged() {
        // 0.5% → 3%: exceeds the baseline p95 but the effect size is trivial.
        let baseline = Array(repeating: 0.5, count: 20)
        let recent = Array(repeating: 3.0, count: 8)
        XCTAssertFalse(Anomaly.processCPUExceedsBaseline(baseline: baseline, recent: recent),
                       "near-idle noise must not trip a regression alert")
    }

    func testProcessCPU_tooFewSamples_notFlagged() {
        XCTAssertFalse(Anomaly.processCPUExceedsBaseline(baseline: [20, 20, 20],
                                                         recent: [90, 90, 90]))
    }

    // MARK: battery drain

    func testBatteryDrainRate_lostTenPercentOverTwoHours() {
        let session = [(ts: 0, percent: 100.0), (ts: 3600, percent: 95.0), (ts: 7200, percent: 90.0)]
        let rate = Anomaly.batteryDrainRate(session)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate ?? 0, 5, accuracy: 0.001)  // 10% over 2h → 5%/hr
    }

    func testBatteryDrainRate_singlePoint_isNil() {
        XCTAssertNil(Anomaly.batteryDrainRate([(ts: 0, percent: 100)]))
    }

    func testBatteryDrainRegressed_fasterThanBaseline_flagged() {
        XCTAssertTrue(Anomaly.batteryDrainRegressed(baselineRates: [3, 3.5, 4, 3.2], recentRate: 6))
    }

    func testBatteryDrainRegressed_withinNormalVariation_notFlagged() {
        XCTAssertFalse(Anomaly.batteryDrainRegressed(baselineRates: [4, 4.2, 3.8, 4.1], recentRate: 4.3))
    }
}
