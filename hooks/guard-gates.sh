#!/usr/bin/env bash
# PreToolUse hook: harness-enforced human gates for irreversible actions,
# so they don't depend on the model following prompt rules.
#
# Rules live next to this script, checked in this order:
#   guard-gates.local.conf  (yours, never overwritten by install.sh)
#   guard-gates.d/*.conf    (optional modules, e.g. fernrohr.conf)
#   guard-gates.conf        (kit defaults)
# First matching rule wins. Line format:
#   <allow|ask|deny> :: <bash|tool>[@<project-dir-glob>] :: <extended regex> :: <reason>
# In bash-scope patterns, {B} expands to a command-boundary class so
# "cd x && git push" matches but "grep 'git push'" does not.
# A scope like bash@~/code/myrepo limits the rule to sessions whose project
# dir is that path or below it (glob, ~ expanded). Project-scoped rules are
# only meaningful in your local conf; repos can't ship them.
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

project=${CLAUDE_PROJECT_DIR:-}
[ -n "$project" ] || project=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)

in_project() { # $1 = glob; true if $project is the glob's dir or below it
  local glob=${1/#\~/$HOME}
  [ -n "$project" ] || return 1
  # shellcheck disable=SC2053  # unquoted RHS is intentional: glob match
  [[ $project == $glob || $project == $glob/* ]]
}

conf_dir=$(cd "$(dirname "$0")" && pwd)
boundary='(^|[;&|[:space:]`(])'
sep=' :: '

decide() { # $1=allow|ask|deny  $2=reason
  [ "$1" = allow ] && exit 0
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

shopt -s nullglob
confs=("$conf_dir/guard-gates.local.conf" "$conf_dir"/guard-gates.d/*.conf "$conf_dir/guard-gates.conf")
for conf in "${confs[@]}"; do
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
    case "$rule_scope" in
      "$scope") ;;
      "$scope@"*) in_project "${rule_scope#*@}" || continue ;;
      *) continue ;;
    esac
    pattern=${pattern//\{B\}/$boundary}
    if grep -Eq -- "$pattern" <<<"$subject"; then
      decide "$decision" "$reason"
    fi
  done <"$conf"
done

exit 0
