# Burrow 0.5.5

A big feature release: two new cleanup tools, an AI "Explain" lens, and
agent-driven cleanups over MCP.

## New tools
- **Purge** — find and remove old project build artifacts (`node_modules`,
  `target/`, `build/`, …) via `mo purge`. Scan, then tick exactly which
  artifacts to clear; Mole does the deletion.
- **Installers** — find leftover installer files (`.dmg`, `.pkg`, `.iso`,
  `.xip`, `.zip`) via `mo installer`, with the same pick-what-to-remove flow.

## Explain (AI) — experimental
A small, opt-in lens on the Status tab that reads your latest snapshot and
explains it in plain English, optionally suggesting one safe next step
(Clean / Purge / Installers). It only ever reads one snapshot and never acts
on its own.
- **Local by default** — runs against a local **Ollama** model; nothing
  leaves the Mac.
- **LM Studio / OpenAI-compatible APIs** — switch the backend in Settings and
  point it at LM Studio (load a model → Developer ▸ Start Server) or any
  OpenAI-compatible endpoint. Local servers need no key.

## Agents can now *do*, not just read (MCP)
The MCP server gains action tools so coding agents can drive Mole's commands:
`burrow_clean`, `burrow_optimize`, `burrow_uninstall`, `burrow_analyze`,
`burrow_list_apps`, plus `burrow_purge` / `burrow_installer` previews.
**Safe by default:** every tool runs `--dry-run` unless the call passes
`confirm:true` **and** you've enabled "Let agents run cleanups for real" in
Settings. Without both, nothing is deleted. (Read-only metrics + cleanup
history tools are unchanged.)

## Install
```
brew install --cask caezium/tap/burrow
```
Pulls in the `mole` engine and clears the Gatekeeper quarantine for you.
Ad-hoc signed (so Full Disk Access grants stick); not yet notarized.

---
Older releases: see the
[Releases page](https://github.com/caezium/Burrow/releases).
