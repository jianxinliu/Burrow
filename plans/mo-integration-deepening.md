# Plan: Deepen the `mo` integration (testable selection driver + runner/client/snapshot stack)

> Source PRD: [caezium/Burrow#29](https://github.com/caezium/Burrow/issues/29)

Eight tracer-bullet slices across the PRD's four phases. Each slice cuts through the new interface + at least one real caller + boundary tests, is independently mergeable, and **leaves the app behaving identically to the user** — the deliverable is test coverage and a narrower interface, not new behavior.

## Architectural decisions

Durable decisions that apply across all phases:

- **Module stack** (top depends on the one below): `SnapshotStore` → `MoleClient` → `MoleProcess`; `SelectionSession` → PTY port (later satisfied by `MoleProcess`'s pty mode without changing the session's interface). Each module has a narrow interface hiding a large implementation.
- **Selection reducer contract**: `reduce(state, event) -> (state, [effect])`, a **pure function** — no I/O, no clock, no SwiftUI inside it.
  - **Events** (host → reducer): output-arrived (raw frame text), process-exited (status), scan-requested, show-all-requested, confirm-requested (chosen index set), and **tick** (a counted logical pulse).
  - **Effects** (reducer → host): launch-process, send-keystrokes (bytes), terminate, state-changed.
  - **Clock**: settle/timeout decisions are driven by counting `tick` events, **never wall-clock time**, so tests advance time by feeding ticks.
- **PTY port**: a minimal boundary — launch (executable + args), send (bytes), terminate, plus an output callback and an exit callback. **Production adapter** wraps the real pseudo-terminal; **test adapter** is a scripted fake that maps received keystrokes to the next canned frame(s).
- **Process port** (Phase 2+): the OS-process boundary is injectable. The runner exposes explicit modes — capture, stream, pseudo-terminal, elevated — and there is exactly **one** ANSI-stripping function in the codebase.
- **Reused pure vocabulary**: the existing tested helpers (frame parse, item merge/stitch by full identity, keystroke planning, confirm-count across `Remove|Delete|…`, total-count from the `[n/total]` header) become the reducer's internal vocabulary; their behavior is unchanged.
- **Testing principle**: boundary tests assert **observable outcomes** — the effects produced by a sequence of events, or the typed result of canned `mo` output — never internal fields or timing. **Replace, don't layer**: delete a shallow-module test once a boundary test covers the behavior. Substitutes: the scripted **fake PTY** (Phases 1–4/6) and a **temporary database** (Phase 8). A single optional `--dry-run` integration smoke may remain, but it is **not** the primary safety net.
- **Dependency categories**: Phases 1, 2 (and the pty/elevated parts of 6) are **ports & adapters**; Phases 7 and 8 are **local-substitutable** (canned output / temp DB).
- **Invariant**: after every slice the installer, purge, uninstall, trackers, MCP, and HTTP surfaces behave identically to the user.

---

## Phase 1: Selection reducer skeleton + scan path + PTY port

**User stories**: 1, 2, 8, 9, 21

### What to build

Introduce the `SelectionSession` reducer with its state / event / effect vocabulary and the logical-tick clock, and implement the **smallest complete path only**: launch the selection process through the PTY port, feed terminal output and ticks in as events, and drive to the `choosing` state carrying the parsed item list and reported total. Convert the existing installer/purge runner into a thin **host** that owns the real PTY adapter and a repeating timer, translates pty bytes and timer fires into events, runs the reducer, applies `launch`/`send-keystrokes` effects, and republishes reducer state for the SwiftUI list. Add the scripted **fake PTY** to the test target. Both installer and purge use the same session with their existing per-tool wording.

### Acceptance criteria

- [ ] Installer and purge still scan and render the item list identically to today.
- [ ] The selection flow's decision logic is a pure reducer with no I/O, clock, or SwiftUI inside it.
- [ ] The pseudo-terminal is reached only through the PTY port; production uses the real adapter.
- [ ] A scripted fake PTY exists in the test target and can feed canned frames and capture emitted keystrokes.
- [ ] A boundary test feeds canned scan frames + ticks and asserts the reducer reaches `choosing` with the expected parsed items and total.
- [ ] No wall-clock time is used in any Phase-1 test.

---

## Phase 2: Confirm path + confirm-screen safety

**User stories**: 3, 4, 7, 10, 12, 22, 24

### What to build

Extend the reducer to handle a **single-viewport** selection through `applying → verifying → confirming`: plan the toggle keystrokes for the chosen indices, settle the screen via ticks, verify the on-screen selection matches the choice **by identity**, proceed to `mo`'s final confirm, parse the confirm count across `mo`'s wording variants, and either emit the confirming keystroke (count + identity match) or **abort** (quit + `failed`) on any mismatch. The host applies the emitted keystrokes to the real pty.

### Acceptance criteria

- [ ] Removing a viewport-sized selection in installer and purge works end-to-end (dry-run / real).
- [ ] A boundary test drives select→confirm with a "Delete N installers" confirm frame and asserts the confirming keystroke is emitted only when count and identities match.
- [ ] A boundary test asserts a confirm frame whose count disagrees with the selection yields an abort (quit effect, `failed` state) and never the confirming keystroke.
- [ ] A boundary test asserts an empty selection never produces a confirming keystroke.
- [ ] A test would fail if the confirm-verb match regressed to "Remove"-only (the installer "Delete" regression).

---

## Phase 3: Scroll-capture ("Show all")

**User stories**: 5, 11

### What to build

Add the show-all events/effects so the reducer, on request, walks the cursor to the bottom and stitches the overlapping frames into one ordered item list (dedup by full identity), stopping at the reported total, then returns the cursor to the top. The host pumps the resulting scroll keystrokes and frames; the UI shows the full list with a progress affordance.

### Acceptance criteria

- [ ] "Show all N" in purge pulls in the complete list and the UI renders every item, as today.
- [ ] A boundary test feeds a scripted scroll sequence and asserts the reducer accumulates all N items in order with stable indices.
- [ ] A boundary test asserts duplicate basenames are kept as distinct items (dedup by full identity, not name).
- [ ] A boundary test asserts capture stops at the reported total and returns the cursor to the top.
- [ ] Indices selected before "Show all" remain valid after it (append-only ordering).

---

## Phase 4: Scroll-verify gate

**User stories**: 6, 12, 23, 24

### What to build

Add the **larger-than-one-viewport** confirm path: after the selection walk, scroll from the top through every viewport accumulating the checked rows, and proceed to `mo`'s final confirm **only when** the checked identity set exactly equals the selection; otherwise abort. This completes the PRD's Phase 1 — the entire selection driver is now a tested pure reducer. Retire reliance on the out-of-process harness (optionally keep one `--dry-run` integration smoke).

### Acceptance criteria

- [ ] Removing a selection that spans more than one viewport works end-to-end (dry-run validated).
- [ ] A boundary test asserts the reducer proceeds only when the checked rows across all frames exactly equal the selection.
- [ ] A boundary test asserts a mismatch (an unselected row checked, or a selected row not checked) aborts with quit + `failed` and no confirming keystroke.
- [ ] The scenarios previously validated out-of-process (≈54-item capture, selection spanning the viewport boundary, count-mismatch abort) run in the in-suite tests.
- [ ] Shallow-module tests made redundant by the new boundary tests are deleted.

---

## Phase 5: Subprocess runner (capture mode) + one ANSI stripper

**User stories**: 13, 14, 15

### What to build

Introduce the `MoleProcess` runner with a **capture** mode (blocking; stdout/stderr/exit; stdin feed; timeout-kill; PATH discovery) behind an injectable process port, plus a single ANSI-stripping function. Migrate the plain-capture callers (status sampling, installed-app list, cleanup history, disk analyze, version, uninstall execution) onto it and delete the duplicate strippers.

### Acceptance criteria

- [ ] All plain-capture `mo` invocations route through one runner; no caller constructs its own process for capture.
- [ ] Exactly one ANSI-stripping function remains in the codebase.
- [ ] The process boundary is injectable; a fake process is used in tests.
- [ ] Boundary tests cover timeout behavior, stdin reaching the child, stdout/stderr capture, and a table of ANSI cases.
- [ ] Trackers, app list, history, analyze, and uninstall behave unchanged.

---

## Phase 6: Runner stream / pty / elevated modes

**User stories**: 13, 15

### What to build

Add **stream** (line-coalesced), **pseudo-terminal** (Phase 1's pty adapter relocated here under the same port), and **elevated** (osascript / Touch ID) modes; migrate clean/optimize streaming, the selection session's pty access, the touchid path, and the Homebrew calls onto the runner. The clean/optimize report model and markers are unchanged.

### Acceptance criteria

- [ ] Clean, optimize, touchid, brew, and the selection session all spawn through the one runner.
- [ ] The selection session's PTY port is satisfied by the runner's pty mode with **no change** to the Phase 1 reducer interface.
- [ ] Streaming output and the elevated log-tail behavior are unchanged for the user.
- [ ] Boundary tests cover the stream-coalescing and pty modes via the fake process/pty.

---

## Phase 7: Typed `mo` client

**User stories**: 16, 17, 25

### What to build

Introduce `MoleClient`, which turns each `mo` subcommand into a typed result **exactly once** (status snapshot, history sessions, installed apps, analyze tree), built on the runner. Migrate the SwiftUI views and the MCP server to consume it; MCP tool responses become projections of the typed results. Remove the ad-hoc per-consumer parsers.

### Acceptance criteria

- [ ] Each `mo` subcommand is parsed in exactly one place.
- [ ] The views and the MCP server consume the same typed client for the same command.
- [ ] Boundary tests assert that captured real `mo` output yields the expected typed values, including empty/malformed handling.
- [ ] App and MCP outputs are unchanged.

---

## Phase 8: Snapshot store

**User stories**: 18, 19, 20

### What to build

Introduce `SnapshotStore`, which owns the metrics lifecycle — sample on a cadence (with foreground/background control), patch in natively-read metrics where `mo` reports holes, persist, and answer **typed** queries (latest snapshot; sampled range as decoded snapshots or projected series). Migrate the dashboard, history, popup, AI lens, MCP, and HTTP query server to the store's typed API; remove the per-view raw-JSON decode loops and direct database access.

### Acceptance criteria

- [ ] No consumer decodes raw snapshot JSON or queries the snapshot database directly; all use the store's typed API.
- [ ] The range decode-and-project logic exists in exactly one place.
- [ ] Boundary tests with a temporary database assert sample→typed-query behavior, including native-metric patching and cadence.
- [ ] Dashboard, history, popup, AI lens, MCP, and the HTTP endpoints render identical data to today.
