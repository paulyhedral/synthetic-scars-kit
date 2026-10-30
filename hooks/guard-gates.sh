#!/usr/bin/env bash
# PreToolUse hook: harness-enforced human gates for irreversible actions,
# so they don't depend on the model following prompt rules.
#
# Rules live next to this script:
#   guard-gates.local.conf  (yours, never overwritten by install.sh, checked first)
#   guard-gates.conf        (kit defaults)
# First matching rule wins. Line format:
#   <allow|ask|deny> :: <bash|tool> :: <extended regex> :: <reason>
# In bash-scope patterns, {B} expands to a command-boundary class so
# "cd x && git push" matches but "grep 'git push'" does not.
#
# Fails open on parse errors so a broken hook can't wedge every tool call.
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null || true)
[ -z "$tool" ] && exit 0

if [ "$tool" = "Bash" ]; then
  scope=bash
  subject=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)
  [ -z "$subject" ] && exit 0
else
  scope=tool
  subject=$tool
fi

conf_dir=$(cd "$(dirname "$0")" && pwd)
boundary='(^|[;&|[:space:]`(])'
sep=' :: '

decide() { # $1=allow|ask|deny  $2=reason
  [ "$1" = allow ] && exit 0
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

for conf in "$conf_dir/guard-gates.local.conf" "$conf_dir/guard-gates.conf"; do
  [ -f "$conf" ] || continue
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    decision=${line%%"$sep"*}; rest=${line#*"$sep"}
    rule_scope=${rest%%"$sep"*}; rest=${rest#*"$sep"}
    pattern=${rest%%"$sep"*}; reason=${rest#*"$sep"}
    case "$decision" in allow | ask | deny) ;; *)
      echo "guard-gates: skipping malformed rule in $conf: $line" >&2
      continue ;;
    esac
    [ "$rule_scope" = "$scope" ] || continue
    pattern=${pattern//\{B\}/$boundary}
    if grep -Eq -- "$pattern" <<<"$subject"; then
      decide "$decision" "$reason"
    fi
  done <"$conf"
done

exit 0
