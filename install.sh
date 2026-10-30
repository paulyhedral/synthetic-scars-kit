#!/usr/bin/env bash
# install.sh: install (or remove) the Synthetic Scars kit for Claude Code.
#
# Installs into the Claude config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude):
#   hooks/state-bootloader.sh   SessionStart: re-inject <project>/.state/*.md
#   hooks/guard-gates.sh+.conf  PreToolUse: ask/deny gates for risky commands
#   skills/scar/SKILL.md        /scar: turn corrections into 4-vector scars
#   CLAUDE.md                   marked block with ledger + scar conventions
#   settings.json               hook registrations (merged, existing hooks kept)
# and adds `.state/` to your global gitignore.
#
# Idempotent: re-running updates in place. Never touches guard-gates.local.conf.
# Every modified file is backed up as <file>.bak-<timestamp> first.
#
# Usage: ./install.sh [--dry-run] [--uninstall] [--claude-dir DIR]
#                     [--gitignore-file FILE] [--no-gitignore]
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
GITIGNORE_FILE=""
DO_GITIGNORE=1
DRY_RUN=0
MODE=install
BEGIN_MARK='<!-- synthetic-scars:begin (managed by synthetic-scars-kit/install.sh) -->'
END_MARK='<!-- synthetic-scars:end -->'
STAMP=$(date +%Y%m%d-%H%M%S)

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --uninstall) MODE=uninstall ;;
    --claude-dir) CLAUDE_DIR=${2:?--claude-dir needs a value}; shift ;;
    --gitignore-file) GITIGNORE_FILE=${2:?--gitignore-file needs a value}; shift ;;
    --no-gitignore) DO_GITIGNORE=0 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null || { echo "error: jq is required (brew install jq / apt install jq)" >&2; exit 1; }

say() { printf '%s\n' "$*"; }
run() { # print, and execute unless dry-run
  say "  + $*"
  [ "$DRY_RUN" -eq 1 ] || "$@"
}
backup() {
  [ -f "$1" ] || return 0
  run cp -p "$1" "$1.bak-$STAMP"
}

HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILL_DIR="$CLAUDE_DIR/skills/scar"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
BOOT_CMD="\"$HOOKS_DIR/state-bootloader.sh\""
GUARD_CMD="\"$HOOKS_DIR/guard-gates.sh\""

if [ -z "$GITIGNORE_FILE" ]; then
  GITIGNORE_FILE=$(git config --global core.excludesFile 2>/dev/null || true)
  GITIGNORE_FILE=${GITIGNORE_FILE/#\~/$HOME}
  [ -n "$GITIGNORE_FILE" ] || GITIGNORE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
fi

# jq filter: drop our hook entries (by exact command string), then prune empties.
# shellcheck disable=SC2016  # $boot/$guard are jq variables
JQ_STRIP='
  def strip: map(.hooks |= map(select(.command != $boot and .command != $guard)))
             | map(select(.hooks | length > 0));
  .hooks //= {}
  | .hooks.SessionStart = ((.hooks.SessionStart // []) | strip)
  | .hooks.PreToolUse   = ((.hooks.PreToolUse   // []) | strip)'
# shellcheck disable=SC2016
JQ_ADD='
  | .hooks.SessionStart += [{matcher: "startup|resume|compact",
                             hooks: [{type: "command", command: $boot, timeout: 10}]}]
  | .hooks.PreToolUse   += [{matcher: "Bash|mcp__.*",
                             hooks: [{type: "command", command: $guard, timeout: 10}]}]'
JQ_PRUNE='
  | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
  | if (.hooks.PreToolUse   | length) == 0 then del(.hooks.PreToolUse)   else . end
  | if (.hooks | length) == 0 then del(.hooks) else . end'

update_settings() { # $1 = jq filter
  local src tmp
  src=$SETTINGS
  [ -f "$src" ] || src=/dev/null
  tmp=$(mktemp)
  if [ "$src" = /dev/null ]; then echo '{}'; else cat "$src"; fi |
    jq --arg boot "$BOOT_CMD" --arg guard "$GUARD_CMD" "$1" >"$tmp"
  if [ -f "$SETTINGS" ] && cmp -s "$SETTINGS" "$tmp"; then
    say "  = settings.json already up to date"; rm -f "$tmp"; return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  ~ settings.json diff:"
    diff <(jq -S . "$src" 2>/dev/null || echo '{}') <(jq -S . "$tmp") | sed 's/^/      /' || true
    rm -f "$tmp"; return
  fi
  backup "$SETTINGS"
  mv "$tmp" "$SETTINGS"
  say "  + updated $SETTINGS"
}

strip_claude_md_block() { # prints CLAUDE.md without our managed block
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    !skip' "$CLAUDE_MD"
}

update_claude_md() { # $1 = install|uninstall
  local tmp
  tmp=$(mktemp)
  if [ -f "$CLAUDE_MD" ]; then strip_claude_md_block >"$tmp"; fi
  if [ "$1" = install ]; then
    # trim trailing blank lines, then append the managed block
    if [ -s "$tmp" ]; then
      awk 'NF{for(i=0;i<n;i++)print "";n=0;print;next}{n++}' "$tmp" >"$tmp.t" && mv "$tmp.t" "$tmp"
      printf '\n' >>"$tmp"
    fi
    { say "$BEGIN_MARK"; cat "$KIT_DIR/claude-md-snippet.md"; say "$END_MARK"; } >>"$tmp"
  fi
  if [ -f "$CLAUDE_MD" ] && cmp -s "$CLAUDE_MD" "$tmp"; then
    say "  = CLAUDE.md already up to date"; rm -f "$tmp"; return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  ~ would update $CLAUDE_MD"; rm -f "$tmp"; return
  fi
  backup "$CLAUDE_MD"
  mv "$tmp" "$CLAUDE_MD"
  say "  + updated $CLAUDE_MD"
}

install_kit() {
  say "Installing Synthetic Scars kit into $CLAUDE_DIR$( [ "$DRY_RUN" -eq 1 ] && echo ' (dry run)')"
  run mkdir -p "$HOOKS_DIR" "$SKILL_DIR"
  run install -m 0755 "$KIT_DIR/hooks/state-bootloader.sh" "$HOOKS_DIR/state-bootloader.sh"
  run install -m 0755 "$KIT_DIR/hooks/guard-gates.sh" "$HOOKS_DIR/guard-gates.sh"
  run install -m 0644 "$KIT_DIR/hooks/guard-gates.conf" "$HOOKS_DIR/guard-gates.conf"
  if [ ! -f "$HOOKS_DIR/guard-gates.local.conf" ]; then
    run install -m 0644 "$KIT_DIR/hooks/guard-gates.local.conf.example" "$HOOKS_DIR/guard-gates.local.conf"
  else
    say "  = keeping existing guard-gates.local.conf"
  fi
  run install -m 0644 "$KIT_DIR/skills/scar/SKILL.md" "$SKILL_DIR/SKILL.md"
  update_settings "$JQ_STRIP $JQ_ADD"
  update_claude_md install
  if [ "$DO_GITIGNORE" -eq 1 ]; then
    if [ -f "$GITIGNORE_FILE" ] && grep -qxF '.state/' "$GITIGNORE_FILE"; then
      say "  = .state/ already in $GITIGNORE_FILE"
    else
      run mkdir -p "$(dirname "$GITIGNORE_FILE")"
      say "  + append .state/ to $GITIGNORE_FILE"
      [ "$DRY_RUN" -eq 1 ] || printf '.state/\n' >>"$GITIGNORE_FILE"
    fi
  fi
  say "Done. Hooks load at session start, so open a new Claude Code session to pick them up."
}

uninstall_kit() {
  say "Removing Synthetic Scars kit from $CLAUDE_DIR$( [ "$DRY_RUN" -eq 1 ] && echo ' (dry run)')"
  update_settings "$JQ_STRIP $JQ_PRUNE"
  update_claude_md uninstall
  for f in state-bootloader.sh guard-gates.sh guard-gates.conf; do
    [ -f "$HOOKS_DIR/$f" ] && run rm -f "$HOOKS_DIR/$f"
  done
  [ -f "$SKILL_DIR/SKILL.md" ] && run rm -rf "$SKILL_DIR"
  say "  = left in place: $HOOKS_DIR/guard-gates.local.conf (yours), .state/ in $GITIGNORE_FILE, any scars you wrote"
  say "Done."
}

if [ "$MODE" = install ]; then install_kit; else uninstall_kit; fi
