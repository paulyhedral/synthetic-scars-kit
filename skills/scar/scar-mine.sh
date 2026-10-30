#!/usr/bin/env bash
# scar-mine.sh: find "rapid regret" commit pairs in a repo's history, i.e.
# candidate scars (after Randal L. Schwartz's Rapid-Regret Miner).
#
# A pair is an author's commit (the Trap) followed by that same author's next
# commit within --window minutes (the Fix) that touches the same files.
# Pairs score higher when the fix rewrites lines the trap just wrote, when the
# fix subject reads like a fix, and when the gap is short.
#
# Output: TSV sorted by score, one pair per line:
#   score  minutes  trap_sha  fix_sha  author  files  trap_subject  fix_subject
#
# Usage: scar-mine.sh [-C DIR] [--rev REV] [--since WHEN] [--window MIN]
#                     [--limit N] [--min-score N] [--max-files N]
#                     [--exclude-authors REGEX] [-- PATHSPEC...]
#   --rev       history to scan (default HEAD)
#   --since     git date, e.g. "1 year ago" (default "1 year ago")
#   --window    max minutes between trap and fix (default 60; try 1440 on
#               squash-merge repos, where fixes arrive as follow-up PRs)
#   --limit     max pairs printed (default 30)
#   --min-score drop weaker pairs (default 3)
#   --max-files skip commits touching more files than this (default 40)
#   --exclude-authors  extended regex on author email
#                      (default: bots, dependabot, renovate, github-actions)
set -euo pipefail

repo=.
rev=HEAD
since="1 year ago"
window=60
limit=30
min_score=3
max_files=40
exclude='\[bot\]|dependabot|renovate|github-actions'
paths=()

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -C) repo=${2:?-C needs a dir}; shift ;;
    --rev) rev=${2:?}; shift ;;
    --since) since=${2:?}; shift ;;
    --window) window=${2:?}; shift ;;
    --limit) limit=${2:?}; shift ;;
    --min-score) min_score=${2:?}; shift ;;
    --max-files) max_files=${2:?}; shift ;;
    --exclude-authors) exclude=${2:?}; shift ;;
    -h | --help) usage; exit 0 ;;
    --) shift; paths=("$@"); break ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for n in "$window" "$limit" "$min_score" "$max_files"; do
  case "$n" in '' | *[!0-9]*) echo "error: numeric option expected, got '$n'" >&2; exit 2 ;; esac
done
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "error: $repo is not a git repository" >&2; exit 1; }

printf 'score\tminutes\ttrap_sha\tfix_sha\tauthor\tfiles\ttrap_subject\tfix_subject\n'

# Newest-first stream: a \036 record per commit, then its -U0 hunk headers.
git -C "$repo" -c core.quotePath=false log --no-merges --no-color --no-ext-diff \
  --since="$since" --format='%x1e%h%x1f%ae%x1f%at%x1f%s' -U0 "$rev" \
  -- ${paths[@]+"${paths[@]}"} |
  SCAR_EXCLUDE="$exclude" awk -v window="$window" -v min_score="$min_score" -v max_files="$max_files" '
    # exclude comes via ENVIRON: -v would eat the regex backslashes
    BEGIN { exclude = ENVIRON["SCAR_EXCLUDE"]; SL = 3 }   # SL: line slack when comparing ranges
    function flush(   a, prev) {
      if (sha == "") return
      if (nfiles <= max_files && tolower(author) !~ exclude) {
        prev = last[author]
        if (prev != "") {
          consider(prev)
          delete c_at[prev]; delete c_sub[prev]; delete c_minus[prev]; delete c_plus[prev]; delete c_files[prev]
        }
        last[author] = sha
        c_at[sha] = at; c_sub[sha] = subj; c_minus[sha] = minus; c_plus[sha] = plus; c_files[sha] = files
      }
      sha = ""
    }
    # Pair: the current (older) commit is the trap, prev (newer, same author) the fix.
    function consider(fix,   dt, shared, lines, score, n, i, f) {
      dt = c_at[fix] - at
      if (dt < 0 || dt > window * 60) return
      shared = ""
      n = split(files, fl, "\034")
      for (i = 1; i <= n; i++) {
        f = fl[i]
        if (f != "" && index("\034" c_files[fix] "\034", "\034" f "\034")) shared = shared (shared == "" ? "" : ",") f
      }
      if (shared == "") return
      lines = overlap(c_minus[fix], plus)
      score = (lines ? 3 : 1)
      if (tolower(c_sub[fix]) ~ /(^|[^a-z])(fix|fixes|fixed|fixup|oops|revert|typo|missing|forgot|correct|hotfix|rollback|broken|actually)/) score += 2
      if (dt <= 15 * 60) score += 2; else if (dt <= 60 * 60) score += 1
      if (score < min_score) return
      printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", score, int(dt / 60), sha, fix, author, shared, subj, c_sub[fix]
    }
    # Ranges are "file\034start\034end" records joined by \035.
    function overlap(fixminus, trapplus,   na, nb, i, j, ra, rb) {
      na = split(fixminus, A, "\035"); nb = split(trapplus, B, "\035")
      for (i = 1; i <= na; i++) {
        if (split(A[i], ra, "\034") < 3) continue
        for (j = 1; j <= nb; j++) {
          if (split(B[j], rb, "\034") < 3) continue
          if (ra[1] == rb[1] && ra[2] - SL <= rb[3] && rb[2] - SL <= ra[3]) return 1
        }
      }
      return 0
    }
    function range(start, count,   e) {   # "a,b" -> start\034end (pure insert/delete -> 2-line span)
      e = (count == 0) ? start + 1 : start + count - 1
      return file "\034" start "\034" e
    }
    /^\036/ {
      flush()
      split(substr($0, 2), h, "\037")
      sha = h[1]; author = h[2]; at = h[3] + 0; subj = h[4]
      gsub(/\t/, " ", subj)
      minus = ""; plus = ""; files = ""; nfiles = 0; file = ""
      next
    }
    /^--- / { oldp = substr($0, 5); sub(/^a\//, "", oldp); next }
    /^\+\+\+ / {
      p = substr($0, 5)
      if (p == "/dev/null") p = oldp; else sub(/^b\//, "", p)
      file = p; nfiles++; files = files "\034" p
      next
    }
    /^@@ / {
      # @@ -a[,b] +c[,d] @@
      split($0, parts, " ")
      split(substr(parts[2], 2), m, ","); split(substr(parts[3], 2), q, ",")
      mc = (m[2] == "") ? 1 : m[2] + 0; pc = (q[2] == "") ? 1 : q[2] + 0
      minus = minus "\035" range(m[1] + 0, mc)
      plus = plus "\035" range(q[1] + 0, pc)
      next
    }
    END { flush() }
  ' |
  sort -t "$(printf '\t')" -k1,1nr -k2,2n |
  awk -v limit="$limit" 'NR <= limit'   # not head: early exit + pipefail = SIGPIPE
