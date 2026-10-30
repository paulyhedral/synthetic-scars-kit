# synthetic-scars-kit

A small Claude Code setup based on Randal L. Schwartz's [*Synthetic Scars*](https://dev.to/randalschwartz/series/44156) series, adapted from his Antigravity/Gemini workflow to Claude Code's native hooks, skills and memory.

It installs three things:

| Piece | What it does | Mechanism |
|---|---|---|
| **Task state ledger** | Multi-step tasks keep their state in `<project>/.state/*.md`, which gets re-injected into context on startup, resume and **after compaction**, so progress doesn't depend on chat history. | `SessionStart` hook + CLAUDE.md convention |
| **Human gates** | `git push`, `terraform apply`, `kubectl delete` and similar trigger a permission prompt (or are blocked) regardless of what the prompt says. | `PreToolUse` hook + editable rules file |
| **Scars** | Corrections are written as 4-vector *scars* (Wound → Trap → Circuit breaker → Reflex) instead of "DON'T" rules, and `/scar` harvests them at the end of a task. | CLAUDE.md convention + `/scar` skill |

## Install

Requirements: `bash` (3.2+ is fine), `jq`, Claude Code.

```bash
./install.sh --dry-run   # show what would change
./install.sh             # install into $CLAUDE_CONFIG_DIR or ~/.claude
./install.sh --uninstall # remove (keeps your local rules and any scars you wrote)
```

Options: `--claude-dir DIR`, `--gitignore-file FILE`, `--no-gitignore`.

The installer is idempotent and only touches what it owns:
- `settings.json`: adds two hook entries and leaves your existing hooks and settings alone.
- `CLAUDE.md`: adds one block between `synthetic-scars:begin/end` markers.
- Global gitignore: appends `.state/` (uses `core.excludesFile`, else `~/.config/git/ignore`).
- Every modified file is backed up as `<file>.bak-<timestamp>` first.

Hooks load at session start, so **open a new session** after installing.

## Customising the gates

Rules live in `~/.claude/hooks/`:
- `guard-gates.conf` holds the kit defaults (overwritten on reinstall).
- `guard-gates.local.conf` holds **your** rules. It's checked first and never overwritten.

```text
<allow|ask|deny> :: <bash|tool> :: <extended regex> :: <reason>

deny  :: bash :: {B}terraform[[:space:]]+(apply|destroy) :: Applies run in CI only.
allow :: bash :: {B}git[[:space:]]+push[[:space:]]+origin[[:space:]]+scratch :: scratch is fine
ask   :: tool :: ^mcp__myserver__(delete|update)_.* :: Mutating MCP call.
```

- First match wins. `{B}` is a command boundary, so `cd x && git push` matches and `grep 'git push'` doesn't.
- `tool` rules match tool names, which is how you gate MCP servers. They never go through Bash.
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

## Tests

```bash
test/run-tests.sh                       # sandboxed; never touches ~/.claude
BASH_BIN=/bin/bash test/run-tests.sh    # check macOS bash 3.2 compatibility
```
