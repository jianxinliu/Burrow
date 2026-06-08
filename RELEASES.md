# Burrow 0.6.0

A fix-and-polish release: the Installers and Uninstall flows now actually
complete, the system trackers show real data, and there's more to track.

## Cleanup flows that now work
- **Installers** — the removal step used to time out at the confirm screen
  ("didn't reach its confirm screen in time"). Mole renames its confirm verb
  per tool ("Delete N installers" vs "Remove N artifact"); Burrow now reads
  either, so installer cleanup completes.
- **Uninstall** — selecting an app and pressing Uninstall did nothing: Mole's
  `uninstall` waits for a `[y/N]` confirmation that a windowed app couldn't
  answer, so it hung. Burrow now drives the full `mo uninstall` flow to
  completion (still gated behind its own confirm sheet; files go to the Trash).
- **Purge → Show all** — Mole only renders its ~50 biggest finds at a time.
  A new **Show all N** button pulls in the complete list so you can pick from
  everything it found, not just the largest, with the same verify-before-delete
  safety.

## Trackers that actually track
- **Disk I/O** and **GPU usage** are now read natively (Mole reports them as
  0 / unavailable on Apple Silicon), so the charts and tiles show real numbers.
- **Thermal** now plots a temperature instead of "No samples".
- New **Battery**, **GPU**, and **Fans** history charts.
- **Top Processes** can rank by **CPU or RAM**.
- Live metrics sample faster while you're watching them, so short network and
  disk spikes land on the chart instead of being missed.

## Other
- Settings (menu-bar toggle, history retention, …) are flushed immediately so
  a change made right before an update isn't lost.

## Install
```
brew install --cask caezium/tap/burrow
```
Pulls in the `mole` engine and clears the Gatekeeper quarantine for you.
Ad-hoc signed (so Full Disk Access grants stick); not yet notarized.

---
Older releases: see the
[Releases page](https://github.com/caezium/Burrow/releases).
