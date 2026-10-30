# synthetic-scars-kit

[![CI](https://github.com/paulyhedral/synthetic-scars-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/paulyhedral/synthetic-scars-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A small Claude Code setup based on Randal L. Schwartz's [*Synthetic Scars*](https://dev.to/randalschwartz/series/44156) series, adapted from his Antigravity/Gemini workflow to Claude Code's native hooks, skills and memory.

It installs three things:

| Piece | What it does | Mechanism |
|---|---|---|
| **Task state ledger** | Multi-step tasks keep their state in `<project>/.state/*.md` (or an OpenSpec change's `tasks.md`, with the module), which gets re-injected into context on startup, resume and **after compaction**, so progress doesn't depend on chat history. | `SessionStart` hook + CLAUDE.md convention |
| **Human gates** | `git push`, `terraform apply`, `kubectl delete` and similar trigger a permission prompt (or are blocked) regardless of what the prompt says. | `PreToolUse` hook + editable rules file |
| **Scars** | Corrections are written as 4-vector *scars* (Wound → Trap → Circuit breaker → Reflex) instead of "DON'T" rules. `/scar` harvests them at the end of a task, and `/scar mine` seeds them from a repo's git history. | CLAUDE.md convention + `/scar` skill + `scar-mine.sh` |

## Install

Requirements: `bash` (3.2+ is fine), `jq`, Claude Code. Tested on macOS and Linux.

```bash
git clone https://github.com/paulyhedral/synthetic-scars-kit.git
cd synthetic-scars-kit
./install.sh --dry-run   # show what would change
./install.sh             # install into $CLAUDE_CONFIG_DIR or ~/.claude
./install.sh --uninstall # remove (keeps your local rules and any scars you wrote)
```

Other options: `--claude-dir DIR`, `--claude-json FILE`, `--gitignore-file FILE`, `--no-gitignore`.

### Optional modules

| Module | Installs | Detected when |
|---|---|---|
| `fernrohr` | `hooks/guard-gates.d/fernrohr.conf`: asks before Fernrohr MCP tools that mutate a cluster (`delete_pods`, `scale`/`restart`/`rollback_workload`, `set_configmap_value`, `trigger_cronjob`…). Read-only tools aren't gated. | A `fernrohr` MCP server is registered in `~/.claude.json` (user or any project scope), or `/Applications/Fernrohr.app` exists |
| `openspec` | `hooks/state-bootloader.d/openspec.sh`: the SessionStart hook also prints `tasks.md` of every active (non-archived) change. Adds an OpenSpec section to the CLAUDE.md block. | `openspec` is on `PATH`, or `openspec-*` skills are installed |

A module defaults to **on** if it's already installed or detected, and **off** otherwise.
- In a terminal, the installer asks about each module and shows that default; `--yes` accepts the defaults without asking.
- `--with fernrohr,openspec` forces modules on, and `--without …` forces them off (and removes them if they were installed).
- Reinstalling keeps whatever you chose last time.

```bash
./install.sh --yes                       # unattended, detection decides
./install.sh --with openspec --without fernrohr
```

The installer is idempotent and only touches what it owns:
- `settings.json`: adds two hook entries and leaves your existing hooks and settings alone.
- `CLAUDE.md`: adds one block between `synthetic-scars:begin/end` markers.
- Global gitignore: appends `.state/` (uses `core.excludesFile`, else `~/.config/git/ignore`).
- Every modified file is backed up as `<file>.bak-<timestamp>` first.

Hooks load at session start, so **open a new session** after installing.

## Customising the gates

Rules live in `~/.claude/hooks/` and are checked in this order:
1. `guard-gates.local.conf`: **your** rules, never overwritten.
2. `guard-gates.d/*.conf`: module rules (e.g. `fernrohr.conf`), managed by the installer.
3. `guard-gates.conf`: the kit defaults, overwritten on reinstall.

```text
<allow|ask|deny> :: <bash|tool>[@<project-dir>] :: <extended regex> :: <reason>

deny  :: bash :: {B}terraform[[:space:]]+(apply|destroy) :: Applies run in CI only.
allow :: bash :: {B}git[[:space:]]+push[[:space:]]+origin[[:space:]]+scratch :: scratch is fine
ask   :: tool :: ^mcp__myserver__(delete|update)_.* :: Mutating MCP call.
allow :: bash@~/code/infra :: {B}git[[:space:]]+push([[:space:]]|$) :: Pushing is routine in this repo.
```

- First match wins. `{B}` is a command boundary, so `cd x && git push` matches and `grep 'git push'` doesn't.
- `tool` rules match tool names, which is how you gate MCP servers. They never go through Bash.
- **Project-scoped rules** (`bash@<dir>`, `tool@<dir>`) apply only when the session's project directory is `<dir>` or below it. The directory comes from `CLAUDE_PROJECT_DIR`, else the hook input's `cwd`. Globs and `~` work. Use them to remove friction where a gated command is routine, e.g. a repo where you always push directly.
  - Keep them in your local conf. A repo can't ship one, so cloning a repo can never loosen your gates.
  - Matching is by path component: `bash@~/code/infra` covers `~/code/infra/modules`, not `~/code/infra-old`.
- `deny` is enforced before any permission prompt. `ask` defers to whatever client is in front (CLI dialog, IDE, ACP client).
- The guard **fails open** on malformed input, so a broken rule can't block every tool call.

## Using the ledger

Tell Claude to "use a `.state/` ledger for this task", or just start a multi-step task. The CLAUDE.md block describes the files (`00_governance`, `10_ticket`, `20_plan_approved`, `30_review`, `99_next_action`). For ad-hoc questions nothing happens, and the hook stays silent in folders without `.state/`.

## Writing scars

At the end of a task where you had to correct Claude, run `/scar`. It drafts scars like:

```markdown
### SCAR-GIT-01: Skipping hooks to get a commit through
- **Wound**: pre-commit lint failure was bypassed with --no-verify; broken formatting landed on main.
- **Trap**: "the hook is just formatting, I'll skip it and fix later."
- **Circuit breaker**: if a hook blocks the commit, stop and report it; you may refuse to bypass.
- **Reflex**:
  1. Read the hook output.
  2. Fix the cause (run the formatter/linter it names).
  3. Re-stage and commit normally; confirm the hook passes.
```

It asks for your OK before writing to `.claude/rules/scars-<area>.md` (path-scoped) or a memory file.

### Mining scars from git history

`/scar mine` (after Randal's *Rapid-Regret Miner*) looks for commits that the same author fixed soon afterwards. The first commit is the Trap, and the follow-up is the Reflex. It's the quickest way to give a repo its first scars before an agent has made any mistakes in it.

```bash
~/.claude/skills/scar/scar-mine.sh -C ~/code/myrepo                # last year, ≤60 min apart
~/.claude/skills/scar/scar-mine.sh -C ~/code/myrepo --window 1440  # squash-merge repos
~/.claude/skills/scar/scar-mine.sh -C ~/code/myrepo -- k8s/        # one subsystem
```

Pairs are scored by:
- whether the fix rewrites **lines** the trap just wrote (stronger than sharing a file);
- fix-like wording ("fix", "revert", "oops", "missing"…);
- how short the gap was.

Bots are excluded, and so are very large commits. The output is ranked TSV.

Inside Claude, `/scar mine` runs the script, has a subagent read the top diff pairs and separate real regrets from plain iteration, and drafts scars only for recurring themes. The Wound is marked `(inferred)` where the history doesn't state it.

## Tests

```bash
test/run-tests.sh                       # sandboxed; never touches ~/.claude
BASH_BIN=/bin/bash test/run-tests.sh    # check macOS bash 3.2 compatibility
```

## Repository layout

```text
install.sh                      installer / uninstaller
claude-md-snippet.md            core block written into CLAUDE.md
hooks/
  state-bootloader.sh           SessionStart hook (+ runs state-bootloader.d/*.sh)
  guard-gates.sh                PreToolUse hook (reads *.conf rule files)
  guard-gates.conf              default gate rules
  guard-gates.local.conf.example  seed for your own rules
skills/scar/SKILL.md            the /scar skill (incl. mining mode)
skills/scar/scar-mine.sh        git-history miner for candidate scars
modules/<name>/                 optional modules (files installed into *.d/)
test/run-tests.sh               sandboxed test suite
```

Adding a module means adding a directory under `modules/`, plus its entries in the `module_*` functions in `install.sh` and tests in `test/run-tests.sh`.

## Credits

The ideas come from Randal L. Schwartz: the [*Synthetic Scars* series](https://dev.to/randalschwartz/series/44156) on DEV and his [public workflow Gist](https://gist.github.com/RandalSchwartz/598a1f2b5760a23c1d70b57e9e85393f). His version targets Google Antigravity and Dart/Flutter repos. This kit is an independent reimplementation for Claude Code and doesn't reuse his files. If you want the full ticket-lifecycle DAG, read his originals.

## License

[MIT](LICENSE)
