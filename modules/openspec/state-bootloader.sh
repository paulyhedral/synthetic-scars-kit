#!/usr/bin/env bash
# Module: openspec. Bootloader plugin that prints the tasks.md of every active
# (non-archived) OpenSpec change, since that file is the task ledger in OpenSpec
# repos. Installed as hooks/state-bootloader.d/openspec.sh.
# Usage (called by state-bootloader.sh): openspec.sh <project-root>
set -euo pipefail

root=${1:?project root required}
max_lines=150

shopt -s nullglob
tasks=("$root"/openspec/changes/*/tasks.md)
[ ${#tasks[@]} -eq 0 ] && exit 0

echo
echo "## Active OpenSpec changes (${root}/openspec/changes)"
echo "Each change's tasks.md is its ledger: [x] done, [ ] open. Continue with the first open task of the change you're working on."
for f in "${tasks[@]}"; do
  change=$(basename "$(dirname "$f")")
  [ "$change" = archive ] && continue
  echo
  echo "### ${change}/tasks.md"
  head -n "$max_lines" "$f"
  total=$(wc -l <"$f" | tr -d ' ')
  if [ "$total" -gt "$max_lines" ]; then
    echo "... (truncated: ${total} lines, read the file for the rest)"
  fi
done
