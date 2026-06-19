//
//  AnomalyScanTests.swift
//  BurrowTests
//
//  Anomaly findings over baseline/recent per-process CPU maps (roadmap A.2).
//

import XCTest
@testable import Burrow

final class AnomalyScanTests: XCTestCase {
    func testCPUFindings_flagsRegressedProcessOnly() {
        let baseline: [String: [Double]] = [
            "WindowServer": Array(repeating: 20.0, count: 20),
            "Finder": Array(repeating: 2.0, count: 20),
        ]
        let recent: [String: [Double]] = [
            "WindowServer": Array(repeating: 50.0, count: 8),   // doubled+ → flagged
            "Finder": Array(repeating: 2.5, count: 8),           // steady → not flagged
        ]
        let findings = AnomalyScan.cpuFindings(baseline: baseline, recent: recent)
        XCTAssertEqual(findings.map(\.process), ["WindowServer"])
        XCTAssertEqual(findings.first?.baselineMedian ?? 0, 20, accuracy: 0.001)
    }

    func testCPUFindings_ignoresProcessWithoutBaseline() {
        let findings = AnomalyScan.cpuFindings(
            baseline: [:], recent: ["new": Array(repeating: 90.0, count: 8)])
        XCTAssertTrue(findings.isEmpty, "no baseline to compare against → not a regression")
    }

    func testCPUFindings_sortedByRecentMedianDescending() {
        let baseline = ["a": Array(repeating: 5.0, count: 20), "b": Array(repeating: 5.0, count: 20)]
        let recent = ["a": Array(repeating: 40.0, count: 8), "b": Array(repeating: 70.0, count: 8)]
        XCTAssertEqual(AnomalyScan.cpuFindings(baseline: baseline, recent: recent).map(\.process), ["b", "a"])
    }
}
