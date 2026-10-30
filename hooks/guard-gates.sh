#!/usr/bin/env bash
# PreToolUse hook: harness-enforced human gates for irreversible actions,
# so they don't depend on the model following prompt rules.
#
# Rules live next to this script, checked in this order:
#   guard-gates.local.conf  (yours, never overwritten by install.sh)
#   guard-gates.d/*.conf    (optional modules, e.g. fernrohr.conf)
#   guard-gates.conf        (kit defaults)
# First matching rule wins (per simple command; see below). Line format:
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

shopt -s nullglob
confs=("$conf_dir/guard-gates.local.conf" "$conf_dir"/guard-gates.d/*.conf "$conf_dir/guard-gates.conf")
rule_dec=(); rule_pat=(); rule_why=()   # rules applying to this tool + project, in order
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
    rule_dec+=("$decision"); rule_pat+=("${pattern//\{B\}/$boundary}"); rule_why+=("$reason")
  done <"$conf"
done
[ ${#rule_dec[@]} -eq 0 ] && exit 0

# Judge each simple command of a compound Bash command on its own, so an
# allow for one part can't wave through another ("git push && kubectl delete").
# First matching rule wins within a part; the strictest part wins overall.
segments=()
if [ "$scope" = bash ]; then
  # shellcheck disable=SC2020  # each of ; & | becomes a newline, char for char
  while IFS= read -r seg; do segments+=("$seg"); done < <(printf '%s\n' "$subject" | tr ';&|' '\n\n\n')
else
  segments=("$subject")
fi

worst=0; worst_dec=""; worst_why=""
for seg in "${segments[@]}"; do
  [ -n "${seg//[[:space:]]/}" ] || continue
  i=0
  while [ "$i" -lt ${#rule_dec[@]} ]; do
    if [[ $seg =~ ${rule_pat[$i]} ]]; then
      case "${rule_dec[$i]}" in deny) rank=3 ;; ask) rank=2 ;; *) rank=1 ;; esac
      if [ "$rank" -gt "$worst" ]; then worst=$rank; worst_dec=${rule_dec[$i]}; worst_why=${rule_why[$i]}; fi
      break
    fi
    i=$((i + 1))
  done
done

if [ "$worst" -ge 2 ]; then
  jq -n --arg d "$worst_dec" --arg r "$worst_why" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
fi
exit 0
