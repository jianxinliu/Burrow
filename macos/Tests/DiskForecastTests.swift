//
//  DiskForecastTests.swift
//  BurrowTests
//
//  The disk-full forecaster (roadmap A.3): a pure (ts, free-bytes) series →
//  projection. Tested through `forecast(_:now:)` only, so the regression
//  method can change without rewriting these.
//

import XCTest
@testable import Burrow

final class DiskForecastTests: XCTestCase {
    private let gb = 1_000_000_000.0
    private let day = 86_400

    /// `count` daily samples ending at day `count-1`, free starting at
    /// `startGB` and changing by `perDayGB` each day.
    private func series(count: Int, startGB: Double, perDayGB: Double)
        -> [(ts: Int, freeBytes: Double)] {
        (0..<count).map { d in
            (ts: d * day, freeBytes: (startGB + perDayGB * Double(d)) * gb)
        }
    }

    func testForecast_steadyDecline_projectsDaysToZero() {
        // 31 daily points, 130 GB losing 1 GB/day → 100 GB left at day 30.
        let s = series(count: 31, startGB: 130, perDayGB: -1)
        let p = DiskForecast.forecast(s, now: 30 * day)
        XCTAssertEqual(p.slopeBytesPerDay, -gb, accuracy: gb * 0.02)
        XCTAssertEqual(p.basisDays, 30, accuracy: 0.001)
        XCTAssertNotNil(p.daysUntilFull)
        XCTAssertEqual(p.daysUntilFull ?? -1, 100, accuracy: 1.0)
    }

    func testForecast_shortHistory_givesNoDate() {
        // Declining, but only 2 days of history (< minBasisDays).
        let s = series(count: 3, startGB: 100, perDayGB: -5)
        let p = DiskForecast.forecast(s, now: 2 * day)
        XCTAssertNil(p.daysUntilFull, "under a week of history must not name a date")
        XCTAssertLessThan(p.slopeBytesPerDay, 0, "but the slope is still reported")
    }

    func testForecast_flatTrend_givesNoDate() {
        let s = series(count: 30, startGB: 100, perDayGB: 0)
        let p = DiskForecast.forecast(s, now: 29 * day)
        XCTAssertNil(p.daysUntilFull, "a flat disk never fills")
    }

    func testForecast_growingFree_givesNoDate() {
        let s = series(count: 30, startGB: 50, perDayGB: +1)
        let p = DiskForecast.forecast(s, now: 29 * day)
        XCTAssertNil(p.daysUntilFull, "free space growing → no fill date")
        XCTAssertGreaterThan(p.slopeBytesPerDay, 0)
    }

    func testForecast_barelyDeclining_beyondHorizon_givesNoDate() {
        // 100 GB losing 1 MB/day → ~100,000 days; past the 5-year horizon.
        var s = series(count: 30, startGB: 100, perDayGB: 0)
        s = s.enumerated().map { i, p in (ts: p.ts, freeBytes: p.freeBytes - Double(i) * 1_000_000) }
        let p = DiskForecast.forecast(s, now: 29 * day)
        XCTAssertNil(p.daysUntilFull, "a forecast past the horizon is suppressed")
        XCTAssertLessThan(p.slopeBytesPerDay, 0)
    }

    func testForecast_resistsSingleCliff() {
        // Steady -1 GB/day for 31 days, but one sample cliffs to ~1 GB free
        // (a temp file). The robust slope must barely move.
        var s = series(count: 31, startGB: 130, perDayGB: -1)
        s[15] = (ts: 15 * day, freeBytes: 1 * gb)
        let p = DiskForecast.forecast(s, now: 30 * day)
        XCTAssertNotNil(p.daysUntilFull)
        XCTAssertEqual(p.daysUntilFull ?? -1, 100, accuracy: 15,
                       "one cliff sample must not derail the forecast")
    }

    func testForecast_emptyOrSingleSample_returnsNil() {
        XCTAssertNil(DiskForecast.forecast([], now: 0).daysUntilFull)
        XCTAssertEqual(DiskForecast.forecast([], now: 0).basisDays, 0)
        let one: [(ts: Int, freeBytes: Double)] = [(ts: 0, freeBytes: 50 * gb)]
        XCTAssertNil(DiskForecast.forecast(one, now: 0).daysUntilFull)
    }
}
