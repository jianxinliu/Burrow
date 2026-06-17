//
//  NotificationsTests.swift
//  BurrowTests
//
//  The pure reminder rules behind the opt-in smart reminders: low-disk
//  hysteresis, the full-Trash re-arm-on-empty, the weekly cooldowns,
//  and the "never invent a cadence nudge without a previous clean"
//  guarantee. The notifier itself stays inert under XCTest by design
//  (it must never prompt for permission from a test run), so what's
//  testable is exactly this decision layer.
//

import XCTest
@testable import Burrow

final class NotificationsTests: XCTestCase {
    private let day: TimeInterval = 86_400

    // MARK: - Low disk (hysteresis)

    func testDiskLow_firesOnCrossing_thenStaysQuietWhileActive() {
        let first = ReminderRules.diskLow(freeFraction: 0.08, active: false)
        XCTAssertTrue(first.notify)
        XCTAssertTrue(first.nowActive)
        // Still low on the next sweep — already told them once.
        let again = ReminderRules.diskLow(freeFraction: 0.07, active: true)
        XCTAssertFalse(again.notify)
        XCTAssertTrue(again.nowActive)
    }

    func testDiskLow_hysteresisBandHolds_recoveryRearms() {
        // 10–12% is the dead band: no notice, no re-arm — a disk
        // hovering at the threshold must not flap.
        let band = ReminderRules.diskLow(freeFraction: 0.11, active: true)
        XCTAssertFalse(band.notify)
        XCTAssertTrue(band.nowActive)
        let recovered = ReminderRules.diskLow(freeFraction: 0.13, active: true)
        XCTAssertFalse(recovered.notify)
        XCTAssertFalse(recovered.nowActive, "recovery past 12% re-arms the rule")
        XCTAssertFalse(ReminderRules.diskLow(freeFraction: 0.50, active: false).notify)
    }

    // MARK: - Full Trash

    func testTrashFull_firesOnCross_quietWhileFull_rearmsOnEmpty() {
        let now = Date()
        let cross = ReminderRules.trashFull(bytes: 6 << 30, active: false, lastNotice: nil, now: now)
        XCTAssertTrue(cross.notify)
        XCTAssertTrue(cross.nowActive)
        // Trash stays full → one notice was enough.
        let still = ReminderRules.trashFull(bytes: 7 << 30, active: true, lastNotice: now, now: now)
        XCTAssertFalse(still.notify)
        XCTAssertTrue(still.nowActive)
        // Emptied (below half the threshold) → re-armed for next time.
        let emptied = ReminderRules.trashFull(bytes: 100, active: true, lastNotice: now, now: now)
        XCTAssertFalse(emptied.notify)
        XCTAssertFalse(emptied.nowActive)
    }

    func testTrashFull_weeklyCooldownBlocksRefire() {
        let now = Date()
        // Emptied and refilled within two days: cooled-down rule waits.
        let blocked = ReminderRules.trashFull(bytes: 6 << 30, active: false,
                                              lastNotice: now.addingTimeInterval(-2 * day), now: now)
        XCTAssertFalse(blocked.notify)
        XCTAssertFalse(blocked.nowActive, "not consumed — it may fire once the cooldown passes")
        let cooled = ReminderRules.trashFull(bytes: 6 << 30, active: false,
                                             lastNotice: now.addingTimeInterval(-8 * day), now: now)
        XCTAssertTrue(cooled.notify)
    }

    // MARK: - Clean cadence

    func testCleanLapsed_requiresAPreviousClean() {
        XCTAssertNil(ReminderRules.cleanLapsedDays(lastClean: nil, lastNotice: nil),
                     "a Mac that never cleaned gets no invented cadence nudge")
    }

    func testCleanLapsed_firesAfterTwoWeeks_throttledWeekly() {
        let now = Date()
        let old = now.addingTimeInterval(-20 * day)
        XCTAssertEqual(ReminderRules.cleanLapsedDays(lastClean: old, lastNotice: nil, now: now), 20)
        // Reminded three days ago → quiet.
        XCTAssertNil(ReminderRules.cleanLapsedDays(lastClean: old,
                                                   lastNotice: now.addingTimeInterval(-3 * day), now: now))
        // Cleaned five days ago → not lapsed at all.
        XCTAssertNil(ReminderRules.cleanLapsedDays(lastClean: now.addingTimeInterval(-5 * day),
                                                   lastNotice: nil, now: now))
    }

    // MARK: - Backup overdue

    func testBackupOverdue_firesPastThreshold_silentWhenRecentOrUnknown() {
        let now = Date()
        XCTAssertEqual(ReminderRules.backupOverdue(daysAgo: 9, lastNotice: nil, now: now), 9)
        XCTAssertNil(ReminderRules.backupOverdue(daysAgo: 3, lastNotice: nil, now: now), "under threshold")
        XCTAssertNil(ReminderRules.backupOverdue(daysAgo: nil, lastNotice: nil, now: now), "no backup history → silent")
        // Weekly cooldown blocks a refire.
        XCTAssertNil(ReminderRules.backupOverdue(daysAgo: 30, lastNotice: now.addingTimeInterval(-2 * day), now: now))
        XCTAssertEqual(ReminderRules.backupOverdue(daysAgo: 30, lastNotice: now.addingTimeInterval(-8 * day), now: now), 30)
    }

    // MARK: - SMART failing

    func testSmartFailing_onlyOnFalseVerdict_throttledWeekly() {
        let now = Date()
        XCTAssertTrue(ReminderRules.smartFailing(verified: false, lastNotice: nil, now: now))
        XCTAssertFalse(ReminderRules.smartFailing(verified: true, lastNotice: nil, now: now), "verified → silent")
        XCTAssertFalse(ReminderRules.smartFailing(verified: nil, lastNotice: nil, now: now), "unknown → never cry wolf")
        XCTAssertFalse(ReminderRules.smartFailing(verified: false, lastNotice: now.addingTimeInterval(-day), now: now),
                       "weekly cooldown")
        XCTAssertTrue(ReminderRules.smartFailing(verified: false, lastNotice: now.addingTimeInterval(-8 * day), now: now))
    }

    // MARK: - mo history parsing

    private func session(_ command: String, startedAt: String, endedAt: String) -> HistorySession {
        HistorySession(command: command, startedAt: startedAt, endedAt: endedAt,
                       items: 0, size: "", operationCount: 1,
                       removed: 0, trashed: 0, skipped: 0, failed: 0)
    }

    func testLastCompletedClean_picksNewestCompleteCleanOnly() throws {
        let last = ReminderRules.lastCompletedClean([
            session("clean", startedAt: "2026-06-01 10:00:00", endedAt: "2026-06-01 10:02:00"),
            session("clean", startedAt: "2026-06-06 20:33:49", endedAt: "2026-06-06 20:35:23"),
            session("clean", startedAt: "2026-06-09 09:00:00", endedAt: ""),       // crashed mid-run
            session("optimize", startedAt: "2026-06-10 09:00:00", endedAt: "2026-06-10 09:01:00"),
            session("clean", startedAt: "not a date", endedAt: "also not"),        // drift → ignored
        ])
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        XCTAssertEqual(try XCTUnwrap(last), fmt.date(from: "2026-06-06 20:33:49"))
    }

    func testLastCompletedClean_emptyOrNoCleansIsNil() {
        XCTAssertNil(ReminderRules.lastCompletedClean([]))
        XCTAssertNil(ReminderRules.lastCompletedClean([
            session("optimize", startedAt: "2026-06-10 09:00:00", endedAt: "2026-06-10 09:01:00"),
        ]))
    }
}
