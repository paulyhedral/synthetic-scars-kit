# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `scar-mine.sh` and `/scar mine`: mine a repo's git history for "rapid regret" commit pairs (same author, fix shortly after, same files/lines) and draft scars from them.
- Project-scoped gate rules (`bash@<dir>`, `tool@<dir>`) to relax gates where a command is routine; only honoured from your own local conf.

## [0.1.0] - 2026-10-30

### Added
- `install.sh`: idempotent installer with `--dry-run`, `--uninstall`, timestamped backups and exact-restore uninstall.
- Task state ledger: `SessionStart` hook re-injects `<project>/.state/*.md` on startup, resume and compaction.
- Human gates: `PreToolUse` hook with `allow`/`ask`/`deny` rules in `guard-gates.conf`, plus a never-overwritten `guard-gates.local.conf`.
- `/scar` skill for turning session corrections into 4-vector scars.
- Optional modules, chosen by flag, detection or interactive prompt:
  - `fernrohr`: gates for cluster-mutating Fernrohr MCP tools.
  - `openspec`: prints active OpenSpec changes' `tasks.md` and adds CLAUDE.md guidance.
- Sandboxed test suite, run under bash 3.2 and 5.x in CI on Linux and macOS.
