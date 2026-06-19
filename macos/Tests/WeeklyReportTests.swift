//
//  WeeklyReportTests.swift
//  BurrowTests
//
//  The weekly digest composer (roadmap A.4), tested through the markdown it
//  produces: which sections appear, and the load-bearing numbers.
//

import XCTest
@testable import Burrow

final class WeeklyReportTests: XCTestCase {
    private func base() -> WeeklyReport.Input {
        .init(periodDays: 7, spaceReclaimedBytes: 0, topEnergy: [],
              newLoginItems: [], batteryHealthDeltaPct: nil, forecast: nil)
    }

    func testMarkdown_alwaysHasTitleAndPeriod() {
        let md = WeeklyReport.markdown(base())
        XCTAssertTrue(md.contains("# Burrow weekly report"))
        XCTAssertTrue(md.contains("Last 7 days"))
    }

    func testMarkdown_spaceReclaimed_rendersHumanSize() {
        var i = base(); i.spaceReclaimedBytes = 3_221_225_472  // 3 GB
        let md = WeeklyReport.markdown(i)
        XCTAssertTrue(md.contains("Freed"))
        XCTAssertTrue(md.contains(Fmt.bytes(3_221_225_472)), "uses the house byte formatter")
    }

    func testMarkdown_noReclaim_saysSo() {
        XCTAssertTrue(WeeklyReport.markdown(base()).contains("No space reclaimed"))
    }

    func testMarkdown_reclaimUnknown_saysUnavailable() {
        var i = base(); i.spaceReclaimedBytes = nil
        let md = WeeklyReport.markdown(i)
        XCTAssertTrue(md.contains("unavailable"), "nil reclaimed is 'unavailable', not a false zero")
        XCTAssertFalse(md.contains("No space reclaimed"))
    }

    func testMarkdown_forecastPresent_namesAWeeksPhrase() {
        var i = base()
        i.forecast = .init(daysUntilFull: 21, slopeBytesPerDay: -1, basisDays: 30)
        let md = WeeklyReport.markdown(i)
        XCTAssertTrue(md.contains("fills in"))
        XCTAssertTrue(md.contains("3 weeks"), "21 days renders as ~3 weeks")
        XCTAssertTrue(md.contains("based on 30 days"))
    }

    func testMarkdown_noForecast_omitsDiskSection() {
        XCTAssertFalse(WeeklyReport.markdown(base()).contains("## Disk"),
                       "no bare date when the forecaster declined")
    }

    func testMarkdown_topEnergy_listsNames() {
        var i = base(); i.topEnergy = [("Xcode", 5000), ("Chrome", 3000)]
        let md = WeeklyReport.markdown(i)
        XCTAssertTrue(md.contains("Xcode"))
        XCTAssertTrue(md.contains("Chrome"))
    }

    func testMarkdown_newLoginItems_securitySection() {
        var i = base(); i.newLoginItems = ["com.sketchy.helper"]
        let md = WeeklyReport.markdown(i)
        XCTAssertTrue(md.contains("New startup items"))
        XCTAssertTrue(md.contains("com.sketchy.helper"))
    }

    func testMarkdown_noLoginItems_omitsSection() {
        XCTAssertFalse(WeeklyReport.markdown(base()).contains("New startup items"))
    }

    func testMarkdown_anomalies_rendersChangesSection() {
        var i = base()
        i.anomalies = [.init(process: "WindowServer", recentMedian: 45, baselineMedian: 20)]
        let md = WeeklyReport.markdown(i)
        XCTAssertTrue(md.contains("## Changes"))
        XCTAssertTrue(md.contains("WindowServer"))
    }

    func testMarkdown_noAnomalies_omitsChangesSection() {
        XCTAssertFalse(WeeklyReport.markdown(base()).contains("## Changes"))
    }

    func testMarkdown_batteryDecline_shown_butImprovementHidden() {
        var i = base(); i.batteryHealthDeltaPct = -2.5
        XCTAssertTrue(WeeklyReport.markdown(i).contains("Health down"))
        i.batteryHealthDeltaPct = +1.0
        XCTAssertFalse(WeeklyReport.markdown(i).contains("Health down"))
    }
}
