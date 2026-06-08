# Burrow 0.5.1

A maintenance release. The headline fix: **Full Disk Access actually works now.**

## Fixes
- **Full Disk Access grants now take effect.** Earlier builds shipped with
  only the linker's stub signature, which macOS treats as unsigned — so the
  TCC system couldn't bind a Full Disk Access grant to the app, and granting
  it appeared to do nothing. Releases are now **ad-hoc signed** with a real,
  stable code identity, so the grant sticks. The Full Disk Access screen also
  gained a "Quit & Reopen" path, since macOS only applies a fresh grant at
  the next launch.
- **Lower energy use in Software.** Dropped a per-app Spotlight
  (`kMDItemLastUsedDate`) query that was waking `mds`/`mdworker`; the
  "recent" sort now uses the filesystem access date instead.

## New
- **Two more MCP tools** for agents (read-only): `burrow_cleanup_history`
  (itemised clean/optimize/uninstall sessions — when, item count, bytes freed)
  and `burrow_deleted_files` (the exact paths Mole removed or trashed,
  newest first). Answers "what did the last cleanup actually delete?"

## Install
```
brew install --cask caezium/tap/burrow
```
Pulls in the `mole` engine and clears the Gatekeeper quarantine for you.
Still unsigned/pre-1.0 (ad-hoc only) — not yet notarized.

---
Older releases: see the
[Releases page](https://github.com/caezium/Burrow/releases).
