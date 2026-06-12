//
//  FeedsTests.swift
//  BurrowTests
//
//  The demand-driven feed layer (issue #53): shared refcounted pumps
//  keyed by query, task-scoped subscription lifecycle, in-flight
//  coalescing, keep-stale-on-failure, and change suppression — asserted
//  against published values on a manual clock. Render nothing; spawn
//  nothing. Leak-freedom is structural: nothing ticks without a
//  subscriber, so the HistoryView timer-leak class is unrepresentable.
//

import XCTest
@testable import Burrow

@MainActor
final class FeedsTests: XCTestCase {
    private var clock: ManualFeedClock!
    private var hub: FeedHub!

    override func setUp() async throws {
        clock = ManualFeedClock()
        hub = FeedHub(clock: clock)
    }

    /// Let the feed's internal fetch Task hop the actor and apply.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: Sharing — identical keys resolve to ONE pump

    func testFeed_isSharedByQueryKey() {
        let a: Feed<Int> = hub.feed("cpu", cadence: 2) { 1 }
        let b: Feed<Int> = hub.feed("cpu", cadence: 2) { 2 }
        let c: Feed<Int> = hub.feed("mem", cadence: 2) { 3 }
        XCTAssertTrue(a === b, "same key → same instance → one timer, one fetch, N observers")
        XCTAssertFalse(a === c)
    }

    // MARK: Demand counting + structural leak-freedom

    func testFirstSubscriberStartsThePump_lastStopsIt() async {
        let feed: Feed<Int> = hub.feed("k", cadence: 2) { 7 }
        XCTAssertEqual(feed.fetchCount, 0, "nothing ticks without a subscriber")

        feed.attach()
        await settle()
        XCTAssertEqual(feed.fetchCount, 1, "first attach takes an immediate sample")
        XCTAssertEqual(feed.value, 7)

        feed.attach()                       // second observer of the same pump
        clock.advance()
        await settle()
        XCTAssertEqual(feed.fetchCount, 2, "two subscribers + one tick = ONE upstream fetch")

        feed.detach()
        clock.advance()
        await settle()
        XCTAssertEqual(feed.fetchCount, 3, "still one subscriber → still ticking")

        feed.detach()
        clock.advance()
        clock.advance()
        await settle()
        XCTAssertEqual(feed.fetchCount, 3, "zero subscribers → zero fetches, structurally")
    }

    func testSubscribeValues_cancellationIsTheUnsubscribe() async {
        let feed: Feed<Int> = hub.feed("k", cadence: 2) { 5 }
        let task = Task { @MainActor in
            for await v in feed.subscribeValues() {
                XCTAssertEqual(v, 5)
                break   // got the first value; keep the subscription parked
            }
        }
        _ = await task.value
        await settle()
        XCTAssertGreaterThanOrEqual(feed.fetchCount, 1)

        // The for-await loop above ended (break terminates the stream), so
        // the subscription is gone: further ticks must fetch nothing.
        let before = feed.fetchCount
        clock.advance()
        await settle()
        XCTAssertEqual(feed.fetchCount, before, "ended subscription = detached pump")
    }

    // MARK: Coalescing — a slow fetch absorbs ticks

    func testTicksCoalesceWhileAFetchIsInFlight() async {
        let gate = FetchGate()
        let feed: Feed<Int> = hub.feed("slow", cadence: 2) { await gate.wait() }
        feed.attach()
        await settle()
        clock.advance()
        clock.advance()
        clock.advance()
        await settle()
        XCTAssertEqual(feed.fetchCount, 1, "three ticks over one in-flight fetch = one call")
        await gate.open(42)
        await settle()
        XCTAssertEqual(feed.value, 42)
        feed.detach()
    }

    // MARK: Failure keeps the stale value; the next tick self-heals

    func testFailureKeepsStaleValue_thenSelfHeals() async {
        let script = ScriptedFetch([.success(1), .failure, .success(2)])
        let feed: Feed<Int> = hub.feed("flaky", cadence: 2) { script.next() }
        feed.attach()
        await settle()
        XCTAssertEqual(feed.value, 1)

        clock.advance()
        await settle()
        guard case .failed(let stale) = feed.phase else {
            return XCTFail("fetch failure must surface as .failed, got \(feed.phase)")
        }
        XCTAssertEqual(stale, 1, "dashboards degrade, they don't blank")
        XCTAssertEqual(feed.value, 1)

        clock.advance()
        await settle()
        XCTAssertEqual(feed.value, 2, "next successful tick self-heals")
        feed.detach()
    }

    // MARK: Change suppression — identical token, zero re-publishes

    func testIdenticalChangeTokenDoesNotRepublish() async {
        let feed: Feed<Int> = hub.feed("same", cadence: 1,
                                       changeToken: { AnyHashable($0) }) { 9 }
        var publishes = 0
        let sub = feed.objectWillChange.sink { publishes += 1 }
        defer { sub.cancel() }

        feed.attach()
        await settle()
        let afterFirst = publishes
        clock.advance()
        clock.advance()
        await settle()
        XCTAssertEqual(publishes, afterFirst,
                       "1 Hz polling over an unchanged row must cause zero invalidations")
        feed.detach()
    }

    /// Suppression must not survive a failure: success → fail → identical
    /// success has to land back in .ready, or the feed reports a stale
    /// failure forever while fetches are healthy.
    func testRecoveryAfterFailure_republishesEvenWithIdenticalToken() async {
        let script = ScriptedFetch([.success(1), .failure, .success(1)])
        let feed: Feed<Int> = hub.feed("recover", cadence: 2,
                                       changeToken: { AnyHashable($0) }) { script.next() }
        feed.attach()
        await settle()
        XCTAssertEqual(feed.value, 1)

        clock.advance()
        await settle()
        guard case .failed = feed.phase else {
            return XCTFail("expected .failed after the flaky tick, got \(feed.phase)")
        }

        clock.advance()
        await settle()
        guard case .ready(let v) = feed.phase else {
            return XCTFail("a healthy fetch must return the feed to .ready even when the value is unchanged — got \(feed.phase)")
        }
        XCTAssertEqual(v, 1)
        feed.detach()
    }
}

// MARK: - Test plumbing

/// Holds fetches open until released — the coalescing scenario.
private actor FetchGate {
    private var continuations: [CheckedContinuation<Int?, Never>] = []
    func wait() async -> Int? {
        await withCheckedContinuation { continuations.append($0) }
    }
    func open(_ value: Int) {
        let conts = continuations
        continuations = []
        for c in conts { c.resume(returning: value) }
    }
}

/// Deterministic fetch script: each call returns the next result.
private final class ScriptedFetch: @unchecked Sendable {
    enum Step { case success(Int), failure }
    private var steps: [Step]
    private let lock = NSLock()
    init(_ steps: [Step]) { self.steps = steps }
    func next() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard !steps.isEmpty else { return nil }
        switch steps.removeFirst() {
        case .success(let v): return v
        case .failure: return nil
        }
    }
}
