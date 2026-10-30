#!/usr/bin/env bash
# run-tests.sh: sandboxed tests for the kit. Never touches your real ~/.claude.
# Usage: test/run-tests.sh   (optionally: BASH_BIN=/bin/bash test/run-tests.sh)
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
BASH_BIN=${BASH_BIN:-bash}
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
CD="$SANDBOX/claude"
IGN="$SANDBOX/gitignore"
pass=0; fail=0

check() { # $1=description $2=expected $3=actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
  fi
}
CJ="$SANDBOX/claude.json"   # stand-in for ~/.claude.json (absent unless a test writes it)
inst() { "$BASH_BIN" "$KIT_DIR/install.sh" --claude-dir "$CD" --claude-json "$CJ" --gitignore-file "$IGN" "$@" </dev/null >/dev/null; }

# --- pre-existing user config that must survive ---
mkdir -p "$CD"
cat >"$CD/settings.json" <<'EOF'
{"model":"opus","hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"echo stop"}]}],
 "SessionStart":[{"matcher":".*","hooks":[{"type":"command","command":"echo existing"}]}]}}
EOF
printf '# My rules\n\n- be concise\n' >"$CD/CLAUDE.md"
cp "$CD/settings.json" "$SANDBOX/settings.orig"
cp "$CD/CLAUDE.md" "$SANDBOX/claude.orig"

# --- install twice: must be idempotent ---
inst --without fernrohr,openspec; inst --without fernrohr,openspec
s="$CD/settings.json"
check "SessionStart entries (existing + ours)" 2 "$(jq '.hooks.SessionStart | length' "$s")"
check "PreToolUse entries" 1 "$(jq '.hooks.PreToolUse | length' "$s")"
check "unrelated Stop hook kept" '"echo stop"' "$(jq '.hooks.Stop[0].hooks[0].command' "$s")"
check "unrelated key kept" '"opus"' "$(jq '.model' "$s")"
check "CLAUDE.md block appears once" 1 "$(grep -c 'synthetic-scars:begin' "$CD/CLAUDE.md")"
check "CLAUDE.md original content kept" 1 "$(grep -c 'be concise' "$CD/CLAUDE.md")"
check ".state/ in gitignore once" 1 "$(grep -cxF '.state/' "$IGN")"
check "skill installed" yes "$([ -f "$CD/skills/scar/SKILL.md" ] && echo yes)"
check "local conf seeded" yes "$([ -f "$CD/hooks/guard-gates.local.conf" ] && echo yes)"

# --- guard decisions ---
G="$CD/hooks/guard-gates.sh"
gate() { # $1=tool $2=command -> allow|ask|deny
  local out
  out=$(jq -n --arg t "$1" --arg c "$2" '{tool_name:$t,tool_input:{command:$c}}' | "$BASH_BIN" "$G" 2>/dev/null)
  if [ -z "$out" ]; then echo allow; else jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"; fi
}
while IFS='|' read -r want tool cmd; do
  check "gate: $cmd" "$want" "$(gate "$tool" "$cmd")"
done <<'EOF'
allow|Bash|git status
allow|Bash|git commit -m 'feat: x'
ask|Bash|cd repo && git push -u origin feat/x
ask|Bash|git push --force-with-lease origin x
ask|Bash|git push origin +main
ask|Bash|git commit --no-verify -m x
ask|Bash|git reset --hard HEAD~1
allow|Bash|grep -r 'git push' .
allow|Bash|terraform plan
ask|Bash|terraform apply -auto-approve
ask|Bash|tofu destroy
allow|Bash|kubectl get pods -A
ask|Bash|kubectl --context prod delete pod x
ask|Bash|kubectl rollout restart deploy/x
allow|Bash|kubectl rollout status deploy/x
allow|Bash|gcloud compute instances list
ask|Bash|gcloud run deploy svc
ask|Bash|aws ec2 terminate-instances --instance-ids i-1
allow|Bash|aws s3 ls
allow|Read|
allow|mcp__x__delete_thing|
EOF

# --- local conf overrides defaults (first match wins) ---
printf '%s\n' \
  'deny :: bash :: {B}terraform[[:space:]]+apply :: CI only.' \
  'allow :: bash :: {B}git[[:space:]]+push[[:space:]]+origin[[:space:]]+scratch :: scratch ok' \
  'ask :: tool :: ^mcp__x__delete_.* :: mutating MCP' \
  'garbage line without separators' >"$CD/hooks/guard-gates.local.conf"
check "local deny beats default ask" deny "$(gate Bash 'terraform apply')"
check "local allow whitelists" allow "$(gate Bash 'git push origin scratch')"
check "tool-scope rule" ask "$(gate mcp__x__delete_thing '')"
out=$(echo "not json" | "$BASH_BIN" "$G" 2>/dev/null); check "malformed input fails open (no output)" "" "$out"

# --- bootloader ---
B="$CD/hooks/state-bootloader.sh"
P="$SANDBOX/proj"; mkdir -p "$P/.state"
printf 'Next: run critic\n' >"$P/.state/99_next_action.md"
out=$(echo '{"source":"compact"}' | CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$B")
check "bootloader prints ledger" 1 "$(grep -c 'Next: run critic' <<<"$out")"
check "bootloader reports source" 1 "$(grep -c 'session source: compact' <<<"$out")"
check "bootloader silent without .state" "" "$(echo '{}' | CLAUDE_PROJECT_DIR="$SANDBOX" "$BASH_BIN" "$B")"

# --- module: fernrohr (detection, persistence, removal) ---
printf '{"projects":{"/x":{"mcpServers":{"fernrohr":{"command":"fernrohr-mcp"}}}}}' >"$CJ"
inst --without openspec
FC="$CD/hooks/guard-gates.d/fernrohr.conf"
check "fernrohr detected via project MCP entry" yes "$([ -f "$FC" ] && echo yes)"
check "gate: fernrohr delete_pods" ask "$(gate mcp__fernrohr__delete_pods '')"
check "gate: fernrohr scale_workload" ask "$(gate mcp__fernrohr__scale_workload '')"
check "gate: fernrohr list_resources" allow "$(gate mcp__fernrohr__list_resources '')"
rm -f "$CJ"; inst --without openspec
check "fernrohr kept when already installed" yes "$([ -f "$FC" ] && echo yes)"
inst --without fernrohr,openspec
check "fernrohr removed by --without" no "$([ -f "$FC" ] && echo yes || echo no)"
check "empty guard-gates.d removed" no "$([ -d "$CD/hooks/guard-gates.d" ] && echo yes || echo no)"
check "fernrohr gate gone after removal" allow "$(gate mcp__fernrohr__delete_pods '')"

# --- module: openspec ---
inst --with openspec --without fernrohr
check "openspec plugin installed" yes "$([ -f "$CD/hooks/state-bootloader.d/openspec.sh" ] && echo yes)"
check "openspec CLAUDE.md section added" 1 "$(grep -c '^## OpenSpec' "$CD/CLAUDE.md")"
O="$SANDBOX/osproj"
mkdir -p "$O/openspec/changes/add-thing" "$O/openspec/changes/archive/2026-01-01-old"
printf -- '- [x] 1.1 done\n- [ ] 1.2 open task\n' >"$O/openspec/changes/add-thing/tasks.md"
printf -- '- [ ] archived\n' >"$O/openspec/changes/archive/2026-01-01-old/tasks.md"
out=$(echo '{"source":"resume"}' | CLAUDE_PROJECT_DIR="$O" "$BASH_BIN" "$B")
check "bootloader shows active change" 1 "$(grep -c 'add-thing/tasks.md' <<<"$out")"
check "bootloader shows open task" 1 "$(grep -c '1.2 open task' <<<"$out")"
check "bootloader skips archived change" 0 "$(grep -c 'archived' <<<"$out" || true)"
check "bootloader silent without .state or openspec" "" "$(echo '{}' | CLAUDE_PROJECT_DIR="$SANDBOX" "$BASH_BIN" "$B")"
inst --with openspec --without fernrohr
check "openspec section still once after reinstall" 1 "$(grep -c '^## OpenSpec' "$CD/CLAUDE.md")"
inst --without openspec,fernrohr
check "openspec section removed by --without" 0 "$(grep -c '^## OpenSpec' "$CD/CLAUDE.md" || true)"
check "openspec plugin removed" no "$([ -f "$CD/hooks/state-bootloader.d/openspec.sh" ] && echo yes || echo no)"

# --- bad module name ---
rc=0; inst --with nosuch 2>/dev/null || rc=$?
check "unknown module rejected" 2 "$rc"

# --- uninstall (with both modules on) restores original config ---
inst --with fernrohr,openspec
inst --uninstall
check "settings restored" "$(jq -S . "$SANDBOX/settings.orig")" "$(jq -S . "$CD/settings.json")"
check "CLAUDE.md restored" "$(cat "$SANDBOX/claude.orig")" "$(cat "$CD/CLAUDE.md")"
check "hooks removed" no "$([ -f "$G" ] && echo yes || echo no)"
check "local conf kept" yes "$([ -f "$CD/hooks/guard-gates.local.conf" ] && echo yes)"

# --- fresh install onto an empty dir ---
rm -rf "$CD"; inst
check "fresh install creates valid settings" 1 "$(jq '.hooks.PreToolUse | length' "$CD/settings.json")"

# shellcheck disable=SC2016  # expanded by the inner shell
printf '%d passed, %d failed (%s)\n' "$pass" "$fail" "$("$BASH_BIN" -c 'echo $BASH_VERSION')"
[ "$fail" -eq 0 ]
