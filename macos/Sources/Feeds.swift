//
//  Feeds.swift
//  Burrow
//
//  The demand-driven metrics feed layer (issue #53): one hub vending
//  shared, refcounted, self-refreshing published values, keyed by query.
//  Views become dumb bodies binding to a feed; NOTHING in a view owns a
//  timer — the HistoryView `autoRefreshTimer` leak class becomes
//  unrepresentable because a pump cannot tick without a subscriber, and
//  subscription is task-scoped so view disappearance IS the unsubscribe.
//
//  What it owns: refresh scheduling, demand counting, in-flight
//  coalescing, loading/failed-keeps-stale phases, and change suppression
//  (1 Hz polling over a 60 s sampler causes zero invalidations). It never
//  performs I/O of its own — the fetch closure is the query.
//

import Foundation
import Combine

// MARK: - Clock seam

/// One repeating-tick handle. Production wraps a Timer; tests use the
/// manual clock so feed scheduling is deterministic and instant.
@MainActor
protocol FeedTicker: AnyObject {
    func start(every interval: TimeInterval, _ tick: @escaping () -> Void)
    func stop()
}

@MainActor
protocol FeedClock {
    func makeTicker() -> FeedTicker
}

/// Production clock: main-run-loop timers.
@MainActor
final class TimerFeedClock: FeedClock {
    // Nonisolated so it can serve as FeedHub.init's default argument
    // (default args evaluate outside the actor).
    nonisolated init() {}
    func makeTicker() -> FeedTicker { TimerTicker() }

    private final class TimerTicker: FeedTicker {
        private var timer: Timer?
        func start(every interval: TimeInterval, _ tick: @escaping () -> Void) {
            stop()
            let t = Timer(timeInterval: interval, repeats: true) { _ in
                Task { @MainActor in tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        func stop() {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Feed

/// A shared, self-refreshing published value. Obtain via `FeedHub.feed` —
/// identical keys resolve to one instance (one timer, one fetch, N
/// observers).
@MainActor
final class Feed<Value>: ObservableObject {
    enum Phase {
        case idle
        case loading                       // no value yet, fetch running
        case ready(Value)
        case failed(stale: Value?)         // fetch failed; last good value kept
    }

    @Published private(set) var phase: Phase = .idle

    /// The renderable value: ready, or the stale value on failure. Tiles
    /// read this and never switch on Phase — dashboards degrade, not blank.
    var value: Value? {
        switch phase {
        case .ready(let v): return v
        case .failed(let stale): return stale
        case .idle, .loading: return nil
        }
    }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// Fetches started over this feed's lifetime — the test observability
    /// for demand counting and coalescing.
    private(set) var fetchCount = 0

    private let cadence: TimeInterval
    private let ticker: FeedTicker
    private let changeToken: (Value) -> AnyHashable?
    /// nil = fetch failed. Runs off-main when the closure does (queries
    /// hop themselves; the feed only touches state on the main actor).
    private let fetchValue: @Sendable () async -> Value?

    private var demand = 0
    private var inFlight = false
    private var lastToken: AnyHashable?

    init(cadence: TimeInterval, ticker: FeedTicker,
         changeToken: @escaping (Value) -> AnyHashable? = { _ in nil },
         fetch: @escaping @Sendable () async -> Value?) {
        self.cadence = cadence
        self.ticker = ticker
        self.changeToken = changeToken
        self.fetchValue = fetch
    }

    /// First subscriber starts the pump (with an immediate sample); the
    /// last one leaving stops it. Nothing ticks at zero demand.
    func attach() {
        demand += 1
        guard demand == 1 else { return }
        ticker.start(every: cadence) { [weak self] in self?.tick() }
        tick()
    }

    func detach() {
        demand = max(0, demand - 1)
        if demand == 0 { ticker.stop() }
    }

    /// Attach for the lifetime of the surrounding task: yields the current
    /// value (if any) and every subsequent change; cancellation — or the
    /// consumer breaking out — IS the unsubscribe. The only lifecycle line
    /// a view writes is `for await v in feed.subscribeValues() { … }`.
    func subscribeValues() -> AsyncStream<Value> {
        AsyncStream { [weak self] cont in
            guard let self else { cont.finish(); return }
            self.attach()
            let sub = self.$phase.sink { phase in
                switch phase {
                case .ready(let v): cont.yield(v)
                case .idle, .loading, .failed: break   // stale already yielded
                }
            }
            cont.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    sub.cancel()
                    self?.detach()
                }
            }
        }
    }

    /// Manual refresh, coalesced with any in-flight fetch.
    func refresh() {
        tick()
    }

    private func tick() {
        guard demand > 0, !inFlight else { return }   // coalesce; never pump unwatched
        inFlight = true
        fetchCount += 1
        if value == nil { phase = .loading }
        let fetch = fetchValue
        Task { @MainActor [weak self] in
            let result = await fetch()
            guard let self else { return }
            self.inFlight = false
            self.apply(result)
        }
    }

    private func apply(_ result: Value?) {
        guard let v = result else {
            phase = .failed(stale: value)             // degrade, don't blank
            // A failure invalidates the suppression token: the next healthy
            // fetch must re-publish .ready even when the value is unchanged,
            // or the feed would sit in .failed forever while fetches succeed.
            lastToken = nil
            return
        }
        let token = changeToken(v)
        if let token, token == lastToken { return }   // identical data: zero invalidations
        lastToken = token
        phase = .ready(v)
    }
}

// MARK: - Hub

/// Vends feeds keyed by query value — exact-match keys are predictable;
/// the same key from two screens shares one pump (the popup HUD and the
/// Status pane stop double-polling the moment they ask for the same data).
@MainActor
final class FeedHub {
    private let clock: FeedClock
    private var feeds: [AnyHashable: AnyObject] = [:]

    // Nonisolated so owners (AppDelegate) can hold it as a stored
    // property without an actor hop at construction.
    nonisolated init(clock: FeedClock = TimerFeedClock()) {
        self.clock = clock
    }

    /// Idempotent per key: the first registration's closures win; later
    /// calls with the same key return the existing feed.
    func feed<Value>(_ key: some Hashable, cadence: TimeInterval,
                     changeToken: @escaping (Value) -> AnyHashable? = { _ in nil },
                     fetch: @escaping @Sendable () async -> Value?) -> Feed<Value> {
        let k = AnyHashable(key)
        if let existing = feeds[k] {
            guard let typed = existing as? Feed<Value> else {
                // Overwriting would orphan a possibly-live pump (its timer
                // keeps ticking for existing subscribers while the hub loses
                // track of it). A key is one query — one value type.
                preconditionFailure("FeedHub key '\(key)' already registered with \(type(of: existing)), not Feed<\(Value.self)>")
            }
            return typed
        }
        let made = Feed<Value>(cadence: cadence, ticker: clock.makeTicker(),
                               changeToken: changeToken, fetch: fetch)
        feeds[k] = made
        return made
    }
}
