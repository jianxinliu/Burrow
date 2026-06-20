# Burrow 0.8.0

A top-to-bottom visual redesign, a wave of new tools, a deeper agent surface,
and an early Windows preview. Still local-first — no new always-on network.

## Redesigned
- A warm, tactile new look — a warm-coffee adaptive palette, film grain over a
  soft gradient, a **floating icon rail** (replacing the top tabs), borderless
  cards, and the Geist / Cal Sans type system.
- **Overview** — Health pulled into an open hero band over a cleaner 3-up
  vitals grid.
- **History** — a focal hero chart with a selectable metric strip (tap to swap),
  plus drag-select on a chart to surface the top processes for that spike.
- **Menu-bar HUD** — borderless tiles on the same warm ground. Doctor and
  Restore reskinned to match; edge-fade scrollers throughout.

## New & improved tools
- **Ports** — live connections, bandwidth, reverse-DNS peers, service labels,
  conflicts, sortable columns, and a detail view.
- **Get Online / Connectivity** — MDM + gateway checks, active-interface IP,
  captive-portal and device-side rescue, one-click fixes.
- **Tune-Up** — a Smart-Care flow (scan → results → run) that auto-scans on entry.
- **Homebrew** — Services (start / stop / restart), Brewfile snapshots
  (export / restore), and live `brew upgrade` progress in Updates.
- **Menu bar** — customizable popup, Stats-depth widgets, a RunCat-style runner,
  and live metric widgets in the status item.
- **Disk** gains a "Full in ~N" forecast; **Doctor** gains SMART-health and
  backup-awareness checks, with backup-overdue / SMART-failing reminders;
  multi-select bulk reclaim; a git purge-safety badge.

## For your AI agent
- A deeper MCP surface: a token-gated `/events` **SSE stream** and `burrow_diff`
  (e.g. login-item churn), so an agent can watch and compare your machine over
  time.

## Windows preview (new)
- An early native **WinUI 3 / .NET 8** app now lives under `windows/` — Status,
  History, Analyze, Apps, a tray HUD, local telemetry/history, and an MCP stdio
  bridge. Build from source; unsigned preview.

## Performance & stability
- Killed several main-thread app-hangs (process table, sort, ICU on the render
  path, app icons, clean reports, the software list). Onboarding now
  auto-detects `mo`.

## Under the hood
- The repo is now a monorepo (`macos/` + `windows/`), with inside-out framework
  signing for notarization and an automated upstream `mo` release watcher.
