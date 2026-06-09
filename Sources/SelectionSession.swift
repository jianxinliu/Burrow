//
//  SelectionSession.swift
//  Burrow
//
//  The interactive selection flow (`mo installer` / `mo purge`) as a PURE
//  reducer. `reduce(state, event) -> (state, [effect])` has no I/O, no clock,
//  and no SwiftUI inside it: the host (an ObservableObject) owns the
//  pseudo-terminal and a timer, pumps PTY bytes and timer fires in as events,
//  and interprets the returned effects (send keystrokes / quit). Because the
//  decision-making is pure and the terminal is injected, the safety-critical
//  delete path is driven entirely by unit tests with a scripted fake terminal.
//
//  The pure parsing/planning vocabulary lives in `MoTUI` (frame parse, item
//  stitch, keystroke planning, confirm-count). This file is the state machine
//  that sequences them.
//

import Foundation

/// The pseudo-terminal seam the selection host drives. Production uses the real
/// `PTYTask`; tests use a scripted fake that maps received keystrokes to canned
/// frames. Callbacks are always delivered on the main thread so the host (and
/// the reducer it drives) stays single-threaded.
protocol PTYPort: AnyObject {
    var onOutput: ((String) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }
    func launch(_ executable: String, _ args: [String]) throws
    func send(_ bytes: [UInt8])
    func terminate()
}

enum SelectionSession {

    // MARK: - State

    enum Phase: Equatable {
        case scanning          // waiting for Mole's list to render
        case choosing          // list is up; waiting for the user
        case loadingAll        // scrolling to pull in every row past the viewport cap
        case applyingViewport  // sent the toggles; settling + verifying in one viewport
        case applyingFull      // selection spans >1 viewport; scroll-verifying every row
        case awaitingConfirm   // proceeded; waiting for Mole's "Remove N?" screen
        case confirming        // sent the final Enter; collecting Mole's removal output
        case done(Int32)
        case failed(String)
    }

    struct State: Equatable {
        var phase: Phase = .scanning
        var items: [MoTUIItem] = []
        var totalCount = 0
        var viewportCount = 0      // rows in the FIRST frame — Mole's viewport cap

        // Internal terminal buffers, routed by phase.
        var screen = ""
        var confirmScreen = ""
        var result = ""
        var resultText = ""        // user-facing removal log, set on exit
        var listReady = false

        // Selection bookkeeping (set when the user confirms).
        var wanted: Set<Int> = []
        var wantedSigs: Set<String> = []
        var wantedNames: Set<String> = []
        var expectedCount = 0
        var settleAttempt = 0
        var lastSelected: Set<Int>? = nil

        // "Show all" scroll-capture bookkeeping.
        var fullyLoaded = false
        var loadPressesLeft = 0

        // Scroll-verify bookkeeping (selection spanning >1 viewport).
        var verifyChecked: Set<String> = []
        var verifySeen: Set<String> = []
        var verifyPressesLeft = 0
    }

    /// Row identity for safe comparison — full name plus size and location, so
    /// two items sharing a basename can't be confused.
    static func sig(_ i: MoTUIItem) -> String { "\(i.name)\u{1}\(i.size)\u{1}\(i.location)" }

    enum Event {
        case output(String)            // raw PTY bytes arrived
        case processExited(Int32)
        case showAllRequested
        case confirmRequested(Set<Int>)
        case tick                      // a logical clock pulse (settle / timeout)
    }

    enum Effect: Equatable {
        case send([UInt8])
        case terminate
    }

    // MARK: - Reducer

    static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        var s = state
        switch event {
        case .output(let text):
            return ingest(&s, text)
        case .processExited(let code):
            return exited(&s, code)
        case .confirmRequested(let wanted):
            return confirm(&s, wanted)
        case .showAllRequested:
            return showAll(&s)
        case .tick:
            return tick(&s)
        }
    }

    /// Begin scroll-capture of every row past Mole's viewport cap. No-op unless
    /// the list is up and Mole reported more rows than are visible.
    private static func showAll(_ s: inout State) -> (State, [Effect]) {
        guard s.phase == .choosing, !s.fullyLoaded else { return (s, []) }
        guard s.totalCount > s.items.count else { s.fullyLoaded = true; return (s, []) }
        s.phase = .loadingAll
        s.loadPressesLeft = s.totalCount + 20
        return (s, [])
    }

    private static func confirm(_ s: inout State, _ wanted: Set<Int>) -> (State, [Effect]) {
        guard s.phase == .choosing, !wanted.isEmpty else { return (s, []) }
        s.wanted = wanted
        s.wantedSigs = Set(wanted.compactMap { s.items.indices.contains($0) ? sig(s.items[$0]) : nil })
        s.wantedNames = Set(wanted.compactMap { s.items.indices.contains($0) ? s.items[$0].name : nil })
        s.expectedCount = s.items.count
        let keys = MoTUI.keystrokesToSelect(wanted, count: s.items.count, confirm: false)
        if s.items.count > s.viewportCount {
            // Selection spans more rows than Mole renders at once (the user pulled
            // in everything via "Show all"). One frame can't show them all, so we
            // scroll the whole list and confirm the checked rows match by identity.
            // Return the cursor to the top first; the verify walk reads downward.
            s.phase = .applyingFull
            s.verifyChecked = []
            s.verifySeen = []
            s.verifyPressesLeft = s.items.count + 20
            s.screen = ""
            let ups = Array(repeating: MoTUI.up, count: s.items.count + 5).flatMap { $0 }
            return (s, [.send(keys), .send(ups)])
        }
        s.phase = .applyingViewport
        s.settleAttempt = 0
        s.lastSelected = nil
        return (s, [.send(keys)])
    }

    // MARK: - Tick (settle / verify / timeout)

    private static func tick(_ s: inout State) -> (State, [Effect]) {
        switch s.phase {
        case .loadingAll:       return tickLoadingAll(&s)
        case .applyingViewport: return tickViewport(&s)
        case .applyingFull:     return tickFull(&s)
        case .awaitingConfirm:  return tickAwaitConfirm(&s)
        default:                return (s, [])
        }
    }

    /// Scroll-verify a selection that spans more than one viewport: walk from the
    /// top accumulating the CHECKED rows across every frame, then proceed only if
    /// that set exactly equals what the user picked (by identity). Any mismatch or
    /// timeout → quit, remove nothing. Mole's own "Remove N?" count in
    /// `tickAwaitConfirm` is the final backstop.
    private static func tickFull(_ s: inout State) -> (State, [Effect]) {
        for it in MoTUI.parse(s.screen).items {
            let sg = sig(it)
            s.verifySeen.insert(sg)
            if it.selected { s.verifyChecked.insert(sg) }
        }
        if s.verifySeen.count >= s.items.count || s.verifyPressesLeft <= 0 {
            if s.verifyChecked == s.wantedSigs {
                s.phase = .awaitingConfirm
                s.confirmScreen = ""
                s.settleAttempt = 0
                return (s, [.send([0x0d])])
            }
            s.phase = .failed("Couldn't verify the full selection safely (\(s.verifyChecked.count)/\(s.wantedSigs.count) confirmed). Nothing was removed — please try again.")
            return (s, [.send(MoTUI.quit)])
        }
        s.verifyPressesLeft -= 1
        if s.screen.count > 80_000 { s.screen = String(s.screen.suffix(40_000)) }
        return (s, [.send(MoTUI.down)])
    }

    /// Walk the cursor to the bottom one row per tick, stitching each overlapping
    /// frame into the ordered list (dedup by identity), until we've captured the
    /// reported total. Then return the cursor to the top so a later selection
    /// walk still starts at row 0.
    private static func tickLoadingAll(_ s: inout State) -> (State, [Effect]) {
        let vp = MoTUI.parse(s.screen).items
        if !vp.isEmpty { s.items = MoTUI.mergeItems(s.items, vp) }
        if s.items.count >= s.totalCount || s.loadPressesLeft <= 0 {
            let ups = Array(repeating: MoTUI.up, count: s.items.count + 5).flatMap { $0 }
            s.fullyLoaded = true
            s.phase = .choosing
            return (s, [.send(ups)])
        }
        s.loadPressesLeft -= 1
        if s.screen.count > 80_000 { s.screen = String(s.screen.suffix(40_000)) }  // keep parse cheap
        return (s, [.send(MoTUI.down)])
    }

    /// After the first Enter, Mole shows a SECOND screen — "Remove/Delete N …,
    /// Enter confirm, ESC cancel". Confirm ONLY once a parseable count is on a
    /// screen that also shows the cancel prompt, and ONLY if that count equals
    /// what the user picked. Wrong count or no screen in time → ESC + quit,
    /// remove nothing. (The verb varies: `purge` says "Remove", `installer`
    /// says "Delete" — `removalCount` accepts both.)
    private static func tickAwaitConfirm(_ s: inout State) -> (State, [Effect]) {
        let maxAttempts = 75      // ~4.5s for Mole to reach its confirm screen (slow purges)
        let txt = MoTUI.stripANSI(s.confirmScreen)
        if txt.localizedCaseInsensitiveContains("esc cancel"), let n = MoTUI.removalCount(txt) {
            if n == s.wanted.count {
                s.phase = .confirming
                return (s, [.send([0x0d])])     // final Enter → Mole executes the removal
            }
            s.phase = .failed("mo's confirm showed \(n) item\(n == 1 ? "" : "s"), but you picked \(s.wanted.count). Nothing was removed — please rescan and try again.")
            return (s, [.send([0x1b]), .send(MoTUI.quit)])
        }
        guard s.settleAttempt < maxAttempts else {
            s.phase = .failed("mo didn't reach its confirm screen in time. Nothing was removed — please try again.")
            return (s, [.send([0x1b]), .send(MoTUI.quit)])
        }
        s.settleAttempt += 1
        return (s, [])
    }

    /// Re-read the screen each tick until the on-screen selection is stable
    /// across two reads, then confirm ONLY if the checked rows match the wanted
    /// items by index AND name AND unchanged row count — otherwise quit, remove
    /// nothing. Identity matching means a scrolled/again-redrawn frame that
    /// happens to check the same positions can't trick Mole into the wrong delete.
    private static func tickViewport(_ s: inout State) -> (State, [Effect]) {
        let maxAttempts = 35      // ~2.1s of settle headroom at the host's tick rate
        let screenNow = MoTUI.parse(s.screen)
        let onScreen = MoTUI.selectedIndices(screenNow)
        if s.settleAttempt > 0, onScreen == s.lastSelected {
            let onScreenNames = Set(screenNow.items.filter { $0.selected }.map { $0.name })
            let safe = screenNow.items.count == s.expectedCount
                && onScreen == s.wanted
                && onScreenNames == s.wantedNames
            if safe {
                s.phase = .awaitingConfirm
                s.confirmScreen = ""
                s.settleAttempt = 0
                return (s, [.send([0x0d])])     // Enter → Mole's final "Remove N?" screen
            }
            s.phase = .failed("Couldn't confirm the selection safely (\(onScreen.count)/\(s.wanted.count) toggled). Nothing was removed — please try again.")
            return (s, [.send(MoTUI.quit)])
        }
        guard s.settleAttempt < maxAttempts else {
            s.phase = .failed("The selection didn't settle in time. Nothing was removed — please try again.")
            return (s, [.send(MoTUI.quit)])
        }
        s.lastSelected = onScreen
        s.settleAttempt += 1
        return (s, [])
    }

    private static func exited(_ s: inout State, _ code: Int32) -> (State, [Effect]) {
        switch s.phase {
        case .done, .failed:
            return (s, [])                 // never override a decided terminal state
        case .scanning where !s.listReady:
            s.phase = .done(code)          // exited before a list — "nothing to remove"
            return (s, [])
        case .confirming, .awaitingConfirm:
            // Proceeded: `result` holds the removal log; if Mole exited right
            // after the first Enter (no second screen), fall back to what we saw.
            let raw = s.result.isEmpty ? s.confirmScreen : s.result
            s.resultText = MoTUI.stripANSI(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.resultText.isEmpty { s.resultText = "Done — mo finished." }
            s.phase = .done(code)
            return (s, [])
        default:
            return (s, [])
        }
    }

    // MARK: - Output ingest

    private static func ingest(_ s: inout State, _ text: String) -> (State, [Effect]) {
        switch s.phase {
        case .scanning:
            s.screen += text
            if !s.listReady, s.screen.contains("Enter"), s.screen.contains("Confirm") {
                let parsed = MoTUI.parse(s.screen)
                if !parsed.items.isEmpty {
                    s.listReady = true
                    s.items = parsed.items
                    s.viewportCount = parsed.items.count
                    s.totalCount = max(MoTUI.totalCount(s.screen) ?? parsed.items.count, parsed.items.count)
                    s.phase = .choosing
                }
            }
            return (s, [])
        case .loadingAll, .applyingViewport, .applyingFull:
            s.screen += text       // accumulate redraws so the tick can re-read the screen
            return (s, [])
        case .awaitingConfirm:
            s.confirmScreen += text   // Mole's "Remove N?" screen, verified before the final Enter
            return (s, [])
        case .confirming:
            s.result += text          // Mole's removal log after the final Enter
            return (s, [])
        default:
            return (s, [])
        }
    }
}
