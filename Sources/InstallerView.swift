//
//  InstallerView.swift
//  Burrow
//
//  The Installers tool — pick which leftover installers to remove, with
//  MOLE doing the deletion. Mole's `installer` is an interactive selection
//  TUI (no flags/JSON for targeted removal), so Burrow runs it in a
//  pseudo-terminal (MoInteractiveRunner), shows Mole's own list as a native
//  checklist, and replays the user's choices as keystrokes — then verifies
//  the on-screen selection before letting Mole confirm. Nothing is removed
//  by Burrow itself.
//

import SwiftUI
import AppKit

// MARK: - Runner (drives Mole's selection TUI)

@MainActor
final class MoInteractiveRunner: ObservableObject {
    enum Phase: Equatable { case scanning, choosing, applying, done(Int32), failed(String) }

    @Published var phase: Phase = .scanning
    @Published var items: [MoTUIItem] = []
    @Published var resultText: String = ""
    /// Total Mole reported in its "[n/total]" header. When it exceeds
    /// `items.count`, Mole capped the visible rows and the UI says so.
    @Published var totalCount: Int = 0
    /// "Show all" pulled in every row past Mole's ≈50-row viewport cap.
    @Published var fullyLoaded = false
    /// Scroll-capture in progress (drives the "Loading all N…" affordance).
    @Published var loadingAll = false

    let title: String
    private let subcommand: String
    private var pty = PTYTask()
    private var screen = ""        // raw TUI output, pre-confirm
    private var result = ""        // output after the FINAL Enter (Mole's removal results)
    private var confirmed = false
    private var listReady = false
    private var pressedProceed = false   // first Enter sent → capturing Mole's "Remove N?" screen
    private var confirmScreen = ""       // output between the first and second Enter
    private var wantedCount = 0          // how many we intend to remove (verified on the confirm screen)
    private var viewportCount = 0        // rows in the FIRST frame — Mole's viewport cap (≈50)

    init(subcommand: String, title: String) {
        self.subcommand = subcommand; self.title = title
        // Writing a keystroke to a pty whose child already exited raises SIGPIPE,
        // which would kill the app (try? can't catch a signal). Ignore it
        // process-wide; writes then fail with EPIPE, which we swallow.
        signal(SIGPIPE, SIG_IGN)
    }

    /// (Re)start the scan from a clean slate by driving `mo <subcommand>` in a
    /// pseudo-terminal. Run as the user (never elevated): for Downloads/Desktop/
    /// project folders TCC is keyed on the app, not the uid, so root wouldn't
    /// dodge the prompts anyway — Full Disk Access is the real fix, gated by the
    /// view before we get here.
    func start() {
        guard let mo = MoleCLI.findExecutable() else { phase = .failed("mo not found"); return }
        // Fresh state for every (re)scan.
        pty.master?.readabilityHandler = nil
        pty.terminate()
        pty = PTYTask()
        screen = ""; result = ""; confirmScreen = ""
        confirmed = false; listReady = false; pressedProceed = false
        items = []; resultText = ""; totalCount = 0; wantedCount = 0
        viewportCount = 0; fullyLoaded = false; loadingAll = false
        phase = .scanning
        pty.onExit = { [weak self] in Task { @MainActor in self?.handleExit() } }
        do { try pty.launch(mo, [subcommand]) }
        catch { phase = .failed("Couldn't start `mo \(subcommand)`."); return }
        pty.master?.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingest(s) }
        }
    }

    func rescan() { start() }

    // MARK: - Show all (scroll past Mole's viewport cap)

    /// Pull in every row past Mole's ≈50-row viewport cap. Mole renders only a
    /// window of the list but the cursor scrolls through ALL of it, so we walk
    /// to the bottom one row at a time, stitching each overlapping frame into
    /// one ordered list, then return the cursor to the top so a later selection
    /// walk still starts at row 0. Append-only, so indices the user already
    /// selected stay valid. Validated against `mo purge --dry-run`.
    func loadAll() {
        guard phase == .choosing, !fullyLoaded, !loadingAll else { return }
        guard totalCount > items.count else { fullyLoaded = true; return }
        loadingAll = true
        scrollCapture(pressesLeft: totalCount + 20)
    }

    private func scrollCapture(pressesLeft: Int) {
        guard loadingAll, phase == .choosing else { loadingAll = false; return }
        let vp = MoTUI.parse(screen).items
        if !vp.isEmpty { items = MoTUI.mergeItems(items, vp) }
        if items.count >= totalCount || pressesLeft <= 0 {
            // Return cursor to the top (over-send; Mole clamps at row 0).
            for _ in 0..<(items.count + 5) { pty.send(MoTUI.up) }
            fullyLoaded = true
            loadingAll = false
            return
        }
        pty.send(MoTUI.down)
        if screen.count > 80_000 { screen = String(screen.suffix(40_000)) }  // keep parse cheap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.scrollCapture(pressesLeft: pressesLeft - 1)
        }
    }

    /// Apply selection: toggle the wanted rows, then poll the screen until the
    /// redraw settles and confirm ONLY if the checked rows match the wanted
    /// items BY NAME (not just by index) and the list didn't shift/scroll —
    /// otherwise quit without removing anything. Identity matching means a
    /// scrolled frame that happens to check the same index positions can't
    /// trick Mole into deleting the wrong files.
    func confirm(_ wanted: Set<Int>) {
        guard phase == .choosing, !wanted.isEmpty else { return }
        phase = .applying
        wantedCount = wanted.count
        let wantedNames = Set(wanted.compactMap { items.indices.contains($0) ? items[$0].name : nil })
        let wantedSigs = Set(wanted.compactMap { items.indices.contains($0) ? Self.sig(items[$0]) : nil })
        let expectedCount = items.count
        pty.send(MoTUI.keystrokesToSelect(wanted, count: items.count, confirm: false))
        if items.count > viewportCount {
            // Selection spans more rows than Mole renders at once (the user
            // pulled in everything via "Show all"). Verifying by re-reading a
            // single frame can't see them all, so we scroll through and confirm
            // the checked rows match BY IDENTITY before letting Mole proceed.
            scrollVerifyThenConfirm(wantedSigs: wantedSigs)
        } else {
            verifyThenConfirm(wanted: wanted, wantedNames: wantedNames, expectedCount: expectedCount, attempt: 0, last: nil)
        }
    }

    /// Row identity for safe comparison — full path/name plus size and location,
    /// so two projects sharing a basename can't be confused.
    private static func sig(_ i: MoTUIItem) -> String { "\(i.name)\u{1}\(i.size)\u{1}\(i.location)" }

    /// Verify a selection that spans more than one viewport: scroll from the
    /// top to the bottom accumulating the CHECKED rows, then proceed only if
    /// that set exactly equals what the user picked. Any mismatch or timeout →
    /// quit, remove nothing. Mole's own "Remove N?" count is the final backstop
    /// in `awaitFinalConfirm`.
    private func scrollVerifyThenConfirm(wantedSigs: Set<String>) {
        guard phase == .applying else { return }
        for _ in 0..<(items.count + 5) { pty.send(MoTUI.up) }   // back to the top
        screen = ""                                              // read only post-selection frames
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.scrollVerifyStep(wantedSigs: wantedSigs, checked: [], seen: [],
                                  pressesLeft: self.items.count + 20)
        }
    }

    private func scrollVerifyStep(wantedSigs: Set<String>, checked: Set<String>,
                                  seen: Set<String>, pressesLeft: Int) {
        guard phase == .applying else { return }
        var checked = checked, seen = seen
        for it in MoTUI.parse(screen).items {
            let s = Self.sig(it)
            seen.insert(s)
            if it.selected { checked.insert(s) }
        }
        if seen.count >= items.count || pressesLeft <= 0 {
            if checked == wantedSigs {
                pressedProceed = true
                confirmScreen = ""
                pty.send([0x0d])              // proceed to Mole's final "Remove N?" screen
                awaitFinalConfirm(attempt: 0)
            } else {
                pty.send(MoTUI.quit)
                phase = .failed("Couldn't verify the full selection safely (\(checked.count)/\(wantedSigs.count) confirmed). Nothing was removed — please try again.")
            }
            return
        }
        pty.send(MoTUI.down)
        if screen.count > 80_000 { screen = String(screen.suffix(40_000)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.scrollVerifyStep(wantedSigs: wantedSigs, checked: checked, seen: seen,
                                   pressesLeft: pressesLeft - 1)
        }
    }

    /// Re-read every 0.15s (up to ~2s) until the on-screen selection is stable
    /// across two reads, then verify by index AND name AND unchanged row count
    /// before pressing Enter. Any mismatch or timeout → quit, delete nothing.
    private func verifyThenConfirm(wanted: Set<Int>, wantedNames: Set<String>,
                                   expectedCount: Int, attempt: Int, last: Set<Int>?) {
        guard phase == .applying else { return }
        let screenNow = MoTUI.parse(screen)
        let onScreen = MoTUI.selectedIndices(screenNow)
        let maxAttempts = 14   // ~2.1s

        if attempt > 0, onScreen == last {          // settled
            let onScreenNames = Set(screenNow.items.filter { $0.selected }.map { $0.name })
            let safe = screenNow.items.count == expectedCount
                && onScreen == wanted
                && onScreenNames == wantedNames
            if safe {
                // Selection verified. Press Enter to PROCEED to Mole's final
                // "Remove N? Enter confirm, ESC cancel" screen, then answer it.
                pressedProceed = true
                confirmScreen = ""
                pty.send([0x0d])
                awaitFinalConfirm(attempt: 0)
            } else {
                pty.send(MoTUI.quit)
                phase = .failed("Couldn't confirm the selection safely (\(onScreen.count)/\(wanted.count) toggled). Nothing was removed — please try again.")
            }
            return
        }
        guard attempt < maxAttempts else {
            pty.send(MoTUI.quit)
            phase = .failed("The selection didn't settle in time. Nothing was removed — please try again.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.verifyThenConfirm(wanted: wanted, wantedNames: wantedNames,
                                    expectedCount: expectedCount, attempt: attempt + 1, last: onScreen)
        }
    }

    /// After the first Enter, Mole shows a SECOND screen — "Selected paths …
    /// Remove N artifact, X  Enter confirm, ESC cancel". Wait for it, verify
    /// the count matches what we picked, then send the final Enter to actually
    /// remove. Wrong count or no screen → ESC + quit, remove nothing. (Without
    /// this, the first Enter just lands on that prompt and the run hangs.)
    private func awaitFinalConfirm(attempt: Int) {
        guard phase == .applying, pressedProceed, !confirmed else { return }
        let txt = MoTUI.stripANSI(confirmScreen)
        // Only decide once BOTH the prompt ("Enter confirm, ESC cancel") AND a
        // parseable "Remove N" have rendered — mo draws the paths first, so a
        // premature read would see no count and wrongly bail (the old bug).
        if txt.localizedCaseInsensitiveContains("esc cancel"), let n = MoTUI.removalCount(txt) {
            if n == wantedCount {
                confirmed = true
                pty.send([0x0d])              // second Enter → mo executes the removal
            } else {
                pty.send([0x1b])              // ESC → back out
                pty.send(MoTUI.quit)
                phase = .failed("mo's confirm showed \(n) item\(n == 1 ? "" : "s"), but you picked \(wantedCount). Nothing was removed — please rescan and try again.")
            }
            return
        }
        guard attempt < 30 else {            // ~4.5s waiting for mo's confirm screen
            pty.send([0x1b]); pty.send(MoTUI.quit)
            phase = .failed("mo didn't reach its confirm screen in time. Nothing was removed — please try again.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.awaitFinalConfirm(attempt: attempt + 1)
        }
    }

    func cancel() {
        // Don't write to the child on teardown — if it already exited, a 'quit'
        // byte hits a dead pty (SIGPIPE/crash). terminate() tears it down cleanly.
        pty.master?.readabilityHandler = nil
        pty.terminate()
        switch phase { case .done, .failed: break; default: phase = .done(130) }
    }

    private func ingest(_ s: String) {
        if confirmed { result += s; return }
        if pressedProceed { confirmScreen += s; return }   // Mole's "Remove N?" screen
        screen += s
        if !listReady, screen.contains("Enter"), screen.contains("Confirm") {
            let parsed = MoTUI.parse(screen)
            if !parsed.items.isEmpty {
                listReady = true
                items = parsed.items
                viewportCount = parsed.items.count
                totalCount = max(MoTUI.totalCount(screen) ?? parsed.items.count, parsed.items.count)
                phase = .choosing
            }
        }
    }

    private func handleExit() {
        pty.master?.readabilityHandler = nil
        let status = pty.terminationStatus
        // Never override a failure/cancel we already decided on.
        if case .failed = phase { return }
        if case .done = phase { return }
        if confirmed || pressedProceed {
            // confirmed → `result` holds the removal log; if Mole exited right
            // after the first Enter (no second screen), fall back to what we saw.
            let raw = result.isEmpty ? confirmScreen : result
            resultText = MoTUI.stripANSI(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if resultText.isEmpty { resultText = "Done — mo finished." }
            phase = .done(status)
        } else if !listReady {
            // Exited before a list rendered — usually "nothing to remove".
            phase = .done(status)
        }
        // listReady && !confirmed → we're already in .failed; leave it.
    }
}

// MARK: - View

/// Per-tool wording/skin for the shared interactive checklist. Mole's
/// `installer` and `purge` are the same kind of selection TUI; only the
/// nouns and accents differ.
struct MoInteractiveConfig {
    let tool: Tool
    let subcommand: String      // "installer" / "purge"
    let noun: String            // singular: "installer" / "project"
    let itemIcon: String        // SF Symbol for each row
    let scanningText: String
    let removalNote: String     // first line of the confirm alert
    let emptyText: String       // shown when nothing is found

    static let installer = MoInteractiveConfig(
        tool: .installer, subcommand: "installer", noun: "installer",
        itemIcon: "shippingbox",
        scanningText: "Scanning for installers via Mole…",
        removalNote: "Mole will remove these installer files:",
        emptyText: "No leftover installers found.")

    static let purge = MoInteractiveConfig(
        tool: .purge, subcommand: "purge", noun: "project",
        itemIcon: "folder.badge.minus",
        scanningText: "Scanning projects for build artifacts via Mole…",
        removalNote: "Mole will remove the build artifacts (node_modules, .build, …) in these projects:",
        emptyText: "No project build artifacts found.")
}

/// Drives Mole's interactive selection TUI (installer/purge) as a native
/// checklist. Generic over `MoInteractiveConfig` so both tools share one
/// implementation — Mole still does every deletion.
struct MoInteractiveView: View {
    @StateObject private var runner: MoInteractiveRunner
    private let cfg: MoInteractiveConfig
    var isActive: Bool = true
    @State private var selected: Set<Int> = []
    @State private var scanRequested = false
    @State private var showFDAGate = false

    init(_ cfg: MoInteractiveConfig, isActive: Bool = true) {
        self.cfg = cfg
        self.isActive = isActive
        _runner = StateObject(wrappedValue: MoInteractiveRunner(subcommand: cfg.subcommand,
                                                                title: cfg.tool.title))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Scan only on an explicit tap. With Full Disk Access we scan directly;
    /// without it, the gate explains it (the ONLY way to scan Downloads/Desktop/
    /// project dirs without a per-folder prompt — root wouldn't help, since TCC
    /// is keyed on the app, not the uid).
    private func onScanTapped() {
        if Privacy.hasFullDiskAccess() { startScan() }
        else { showFDAGate = true }
    }
    private func startScan() {
        showFDAGate = false
        scanRequested = true
        runner.start()
    }
    /// Return to the tool's hero (same "Back" semantics as Clean/Optimize).
    private func backToHero() {
        runner.cancel()
        selected = []
        scanRequested = false
        showFDAGate = false
    }

    @ViewBuilder
    private var content: some View {
        if !scanRequested {
            if showFDAGate {
                FullDiskAccessRequired(
                    accent: cfg.tool.accent,
                    onRecheck: { if Privacy.hasFullDiskAccess() { startScan(); return true }; return false },
                    onCancel: { showFDAGate = false })   // no "Scan with admin": root can't dodge TCC here
            } else {
                ToolHero(tool: cfg.tool, title: cfg.tool.title, subtitle: cfg.tool.tagline) {
                    PillButton(title: "Scan") { onScanTapped() }
                }
            }
        } else {
            switch runner.phase {
            case .scanning:
                centered { ProgressView(cfg.scanningText).controlSize(.large)
                    .tint(cfg.tool.accent).font(Brand.mono(11)) }
            case .choosing:
                chooser
            case .applying:
                centered { ProgressView("Removing…").controlSize(.large)
                    .tint(cfg.tool.accent).font(Brand.mono(11)) }
            case .done(let code):
                doneView(code)
            case .failed(let m):
                messageView(icon: "exclamationmark.triangle", color: Brand.orange, text: m)
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(cfg.tool.title).font(Brand.serif(18, .medium)).foregroundStyle(Brand.textPrimary)
                Text(countLabel).font(Brand.mono(11)).foregroundStyle(Brand.textTertiary)
                Spacer()
                Button { runner.rescan(); selected = [] } label: {   // rescan() tears down the old PTY itself
                    Label("Rescan", systemImage: "arrow.clockwise").font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
            Rectangle().fill(Brand.hairline).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(runner.items.enumerated()), id: \.offset) { i, item in
                        MoItemRow(item: item, icon: cfg.itemIcon, accent: cfg.tool.accent, selected: selected.contains(i)) {
                            if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                        }
                        Rectangle().fill(Brand.hairline).frame(height: 1).padding(.leading, 48)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .scrollIndicators(.visible)

            if runner.loadingAll {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(cfg.tool.accent)
                    Text("Loading all \(runner.totalCount)… (\(runner.items.count) so far)")
                        .font(Brand.mono(9)).foregroundStyle(Brand.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.bottom, 4)
            } else if runner.totalCount > runner.items.count {
                HStack(spacing: 8) {
                    Text("Showing the \(runner.items.count) biggest of \(runner.totalCount).")
                        .font(Brand.mono(9)).foregroundStyle(Brand.textTertiary)
                    Button { runner.loadAll() } label: {
                        Text("Show all \(runner.totalCount)")
                            .font(Brand.mono(9, .semibold)).foregroundStyle(cfg.tool.accent)
                    }.buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.bottom, 4)
            }

            Rectangle().fill(Brand.hairline).frame(height: 1)
            HStack {
                Text(selectionLabel).font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                Spacer()
                Button { selected = (selected.count == runner.items.count) ? [] : Set(runner.items.indices) } label: {
                    Text(selected.count == runner.items.count ? "select none" : "select all")
                        .font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                }.buttonStyle(.plain).padding(.trailing, 8)
                Button { confirmRemoval() } label: {
                    Text("Remove\(selected.isEmpty ? "" : " (\(selected.count))")")
                        .font(Brand.sans(12, .semibold)).foregroundStyle(selected.isEmpty ? Brand.textTertiary : .white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(selected.isEmpty ? Color.white.opacity(0.06) : cfg.tool.accent))
                }.buttonStyle(.plain).disabled(selected.isEmpty)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
    }

    private var countLabel: String {
        runner.totalCount > runner.items.count ? "\(runner.items.count) of \(runner.totalCount)" : "\(runner.items.count) found"
    }

    private var selectionLabel: String {
        selected.isEmpty ? "\(runner.items.count) \(cfg.noun)\(runner.items.count == 1 ? "" : "s")" : "\(selected.count) selected"
    }

    private func confirmRemoval() {
        let targets = selected.sorted().compactMap { runner.items.indices.contains($0) ? runner.items[$0] : nil }
        guard !targets.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(targets.count) \(cfg.noun)\(targets.count == 1 ? "" : "s")?"
        alert.informativeText = cfg.removalNote + "\n\n"
            + targets.prefix(12).map { "• \($0.name)" }.joined(separator: "\n")
            + (targets.count > 12 ? "\n… and \(targets.count - 12) more" : "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runner.confirm(selected)
    }

    private func doneView(_ code: Int32) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: code == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(code == 0 ? cfg.tool.accent : Brand.orange)
                Text(runner.items.isEmpty && runner.resultText.isEmpty ? cfg.emptyText : "Done.")
                    .font(Brand.sans(14, .semibold)).foregroundStyle(Brand.textPrimary)
                Spacer()
                Button { backToHero() } label: {
                    Label("Back", systemImage: "chevron.left").font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Rectangle().fill(Brand.hairline).frame(height: 1)
            if !runner.resultText.isEmpty {
                ScrollView {
                    Text(runner.resultText).font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).textSelection(.enabled)
                }
            } else { Spacer() }
        }
    }

    private func messageView(icon: String, color: Color, text: String) -> some View {
        VStack(spacing: 12) { Spacer()
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(color)
            Text(text).font(Brand.sans(13)).foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Button { backToHero() } label: {
                Label("Back", systemImage: "chevron.left").font(Brand.mono(11)).foregroundStyle(cfg.tool.accent)
            }.buttonStyle(.plain)
            Spacer(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centered<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack { Spacer(); c(); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A selectable row backed by a parsed Mole TUI item.
struct MoItemRow: View {
    let item: MoTUIItem
    let icon: String
    let accent: Color
    let selected: Bool
    let onToggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Brand.textTertiary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(Brand.sans(13, .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Text("\(item.size)\(item.location.isEmpty ? "" : " · \(item.location)")")
                    .font(Brand.mono(10)).foregroundStyle(Brand.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17)).foregroundStyle(selected ? accent : Brand.textTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hover ? Brand.cardFillHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onToggle() }
    }
}
