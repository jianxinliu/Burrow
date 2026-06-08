//
//  Sampler.swift
//  Burrow
//
//  Periodic sampler: spawns `mo status --json` on a background queue,
//  parses the JSON, writes the raw text to the DB under
//  `prefix: "mole.snapshot"`.
//
//  Cadence model: Burrow doesn't run kernel sample loops itself (that's
//  Mole's job). The "energy gate" from Stats reduces here to a single
//  knob — `intervalSeconds` — defaulting to 60. At that rate, the
//  subprocess spawn cost is amortized to negligible; the popup-state
//  gate Stats needed for in-process readers doesn't apply.
//
//  Failure model: a single failed `mo status` invocation (timeout,
//  exec error, malformed JSON) is logged and retried at the next tick.
//  Repeated failure becomes visible through `/info`'s reader-staleness
//  surface — a Burrow consumer sees `mole.snapshot` getting older just
//  the same way the Stats fork's stale-reader chip works.
//

import Foundation

final class Sampler {
    /// Bare-key prefix used by the QueryServer + chart code. One row per
    /// successful invocation, value = raw `mo status --json` payload.
    static let snapshotPrefix = "mole.snapshot"

    private let db: DB
    private let intervalSeconds: TimeInterval
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.caezium.burrow.sampler", qos: .utility)
    private let dec = JSONDecoder()
    /// Fills the gaps Mole leaves on Apple Silicon (disk I/O, GPU usage) by
    /// reading them natively and patching them into the snapshot JSON.
    private let local = LocalMetrics()

    /// While a live metrics view (Status / History) is on screen we sample
    /// much faster so network spikes and disk-I/O bursts actually land on the
    /// chart instead of being missed between the slow background ticks. Off
    /// screen we fall back to the configured interval to keep the app idle.
    private var foreground = false
    private let foregroundInterval: TimeInterval = 5

    /// Wall-clock time of the most recent successful sample. Exposed for
    /// the menu-bar status surface so we can show "12s ago" without
    /// hitting the DB.
    private(set) var lastSampleAt: Date?

    /// Last decoded snapshot — kept in memory so the popup can render the
    /// current values without a DB read on every redraw.
    private(set) var lastSnapshot: MoleStatus?

    init(db: DB, intervalSeconds: TimeInterval = 60) {
        self.db = db
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        // Initial sample so the popup has data immediately; rest of the
        // schedule is driven by `scheduleNext`, which re-reads
        // `Store.sampleIntervalSeconds` every tick so a Settings change
        // takes effect within one cycle without needing a sampler
        // restart.
        self.queue.async { self.tick() }
        self.scheduleNext()
    }

    func stop() {
        self.timer?.cancel()
        self.timer = nil
    }

    /// Switch between background and live (foreground) cadence. Called by the
    /// metrics views as they appear/disappear. Turning it on takes a fresh
    /// sample immediately so the view isn't waiting a whole interval for data.
    func setForeground(_ on: Bool) {
        self.queue.async {
            guard self.foreground != on else { return }
            self.foreground = on
            if on { self.tick() }     // immediate fresh sample for the opening view
            self.scheduleNext()        // re-arm at the new cadence right away
        }
    }

    /// The cadence for the next fire. Foreground uses the faster of the live
    /// interval and the user's configured one (so a user who set 5 s keeps it).
    private func currentInterval() -> TimeInterval {
        let slow = TimeInterval(Store.sampleIntervalSeconds)
        return self.foreground ? min(self.foregroundInterval, slow) : slow
    }

    /// One-shot timer that re-arms after each tick. This is what lets
    /// the Sampler honor a Settings change (or a foreground switch) at runtime
    /// — we re-pull the interval at the moment we schedule the next fire.
    /// Cancels any pending timer first so a mid-wait `setForeground` re-arm
    /// can't leave two timers running.
    private func scheduleNext() {
        self.timer?.cancel()
        let interval = self.currentInterval()
        let t = DispatchSource.makeTimerSource(queue: self.queue)
        t.schedule(deadline: .now() + interval, repeating: .never,
                   leeway: .milliseconds(self.foreground ? 250 : 2000))
        t.setEventHandler { [weak self] in
            self?.tick()
            self?.scheduleNext()
        }
        t.resume()
        self.timer = t
    }

    /// Single sample iteration. Synchronous from the caller's perspective —
    /// the timer queue is utility-priority so we don't block anything
    /// user-visible. Failures are swallowed and surfaced only through
    /// `lastSampleAt` not advancing.
    private func tick() {
        let result: MoleCLI.Result
        do {
            result = try MoleCLI.run(args: ["status", "--json"], timeout: 8)
        } catch {
            NSLog("Burrow.Sampler: mo status failed to spawn: \(error.localizedDescription)")
            return
        }
        guard result.exitCode == 0 else {
            NSLog("Burrow.Sampler: mo status exit=\(result.exitCode) stderr=\(result.stderr.prefix(200))")
            return
        }
        // Patch in natively-read disk I/O + GPU usage where Mole reports none,
        // then treat the patched text as the canonical snapshot (decode + store).
        let json = self.local.patched(json: result.stdout)
        guard let data = json.data(using: .utf8) else { return }

        // Parse first — a malformed snapshot shouldn't pollute the DB.
        let snapshot: MoleStatus
        do {
            snapshot = try self.dec.decode(MoleStatus.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            // Surface the full coding path so a schema drift in `mo` shows
            // up as "missing key 'X' at path [a, b]" rather than the
            // useless "data couldn't be read" localized string.
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            NSLog("Burrow.Sampler: missing key '\(key.stringValue)' at path '\(path)'")
            return
        } catch let DecodingError.typeMismatch(type, ctx) {
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            NSLog("Burrow.Sampler: type mismatch (expected \(type)) at path '\(path)' — \(ctx.debugDescription)")
            return
        } catch let DecodingError.valueNotFound(type, ctx) {
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            NSLog("Burrow.Sampler: nil value where \(type) expected at path '\(path)'")
            return
        } catch let DecodingError.dataCorrupted(ctx) {
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            NSLog("Burrow.Sampler: data corrupted at path '\(path)' — \(ctx.debugDescription)")
            return
        } catch {
            NSLog("Burrow.Sampler: JSON decode failed: \(error). First 200b: \(result.stdout.prefix(200))")
            return
        }

        // Use the timestamp Mole stamped on the snapshot rather than
        // Date() here. Two reasons: (1) if our tick lags by 200 ms, the
        // chart x-axis is still accurate; (2) Mole's `collected_at`
        // captures the sample window, not the JSON-emit time.
        let ts = Int(snapshot.collectedAt.timeIntervalSince1970)
        do {
            try self.db.insert(prefix: Sampler.snapshotPrefix, ts: ts, json: json)
        } catch {
            NSLog("Burrow.Sampler: DB insert failed: \(error.localizedDescription)")
            return
        }

        self.lastSampleAt = Date()
        self.lastSnapshot = snapshot
    }
}
