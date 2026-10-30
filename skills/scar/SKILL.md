---
name: scar
description: Turn this session's corrections, review catches and near-misses into 4-vector Synthetic Scars (Wound, Trap, Circuit breaker, Reflex) saved as path-scoped rules or feedback memories. Use at the end of a non-trivial task, when the user says "scar this", "remember this mistake", "/scar", or after a reviewer or the user had to correct the agent. `/scar mine` instead mines a repo's git history for "rapid regret" commit pairs (a commit quickly fixed by the same author) and drafts scars from them; use it when onboarding to a repo or when asked to mine, harvest or seed scars from history.
---

# /scar: consolidate this session's failures into scars

A scar replaces a "DON'T" rule. Quoting the bad pattern in a prohibition primes the model to repeat it; a scar names the failure, recognises the temptation, grants permission to stop, and supplies the replacement steps.

If invoked as `/scar mine` (or asked to mine git history), follow **Mining mode** at the end instead of step 1, then continue with steps 2–4.

## 1. Harvest

Scan this session (and `.state/30_review.md` if present) for:
- times the user corrected, redirected or nudged you (including Socratic questions like "what happens if…?")
- blockers raised by a reviewer subagent or `/code-review`
- commands or tests that failed because of a wrong assumption
- PR bot findings that were valid

Ignore one-off typos and anything already covered by an existing scar (grep `~/.claude/rules/scars-*.md`, the project's `.claude/rules/scars-*.md`, and the memory index first; update an existing scar instead of duplicating it).

If there is nothing worth scarring, say so in one line and stop.

## 2. Draft each scar

```markdown
### SCAR-<AREA>-<NN>: <short title>
- **Wound**: <what actually broke or nearly broke: command, error, consequence>
- **Trap**: <the plausible shortcut that leads there, phrased as the thought you had: "the test needs a DB, so mock it to return true">
- **Circuit breaker**: <when you notice the trap, you may stop and push back, ask, or counter-offer instead of forcing it through>
- **Reflex**:
  1. <first concrete step>
  2. <…>
  3. <how to verify it held>
```

Rules for drafting:
- AREA is a short subsystem tag (`GIT`, `TF`, `K8S`, `GCP`, `OBS`, `PROC`, `SHELL`…). NN increments within the destination file.
- The Wound must be concrete, not aesthetic ("pods restarted because exec probe exceeded 1s timeout", not "probes were wrong").
- Describe the Trap; don't paste a code block of the bad pattern.
- The Reflex is positive, ordered and verifiable. Keep it to 5 steps or fewer.

## 3. Choose the destination

| Scope | Destination |
|---|---|
| Specific to one repo/stack | `<repo>/.claude/rules/scars-<area>.md` with `paths:` frontmatter scoping it to the affected files |
| Cross-project technical | `~/.claude/rules/scars-<area>.md` (add `paths:` if it only applies to certain file types) |
| About how to collaborate with the user | a `feedback` memory (Why = Wound, How to apply = Reflex) |

New rules files start with:
```markdown
---
paths:
  - "<glob>"
---
```

## 4. Confirm, then write

Show all drafted scars with their destinations in chat and wait for the user's OK; these files change future sessions. After approval, write them, then append a one-line entry per scar to `.state/30_review.md` if a ledger exists.

## Mining mode (`/scar mine [repo-dir] [extra scar-mine.sh options]`)

Seeds scars from mistakes the team already made and fixed. `scar-mine.sh` sits next to this SKILL.md.

1. **Check the merge style first.** Compare `git log --first-parent --merges --since="1 year ago" --oneline | wc -l` with the non-merge count.
   - If the repo squash-merges (subjects ending in `(#123)`, few merges), quick fixes never reach the default branch. Re-run with `--window 1440` to catch follow-up PRs instead.
   - Show the user the mode you picked and why, in one line.
2. **Run the miner:** `<skill-dir>/scar-mine.sh -C <repo> --limit 30 [options]`. Output is TSV: `score, minutes, trap_sha, fix_sha, author, files, trap_subject, fix_subject`.
   - Add `-- <pathspec>` to focus on a subsystem.
   - If there are no candidates, say so and stop.
3. **Triage in a subagent.** Reading 30 diff pairs is bulky, mechanical work, so delegate it. Give the subagent the TSV and the repo path, and ask it to:
   - run `git show --stat -p <trap_sha>` and `git show -p <fix_sha>` for each pair, truncating large diffs;
   - classify each pair as **REGRET** (the fix corrects a wrong assumption the trap made, one that would plausibly recur) or **ITERATION** (planned follow-up, version bump, formatting, scope split);
   - group REGRET pairs that share a root cause;
   - return one line per group: the theme, the pair SHAs, what the trap assumed, what the fix changed. No full diffs.
4. **Draft scars from the groups (step 2 format), ten at most.** Git history shows the Trap and the Reflex but rarely the Wound.
   - Infer the Wound from the fix subject, body and diff, and mark it `(inferred)` when the history doesn't state it.
   - Cite the fix SHA in the Wound so the user can check it.
5. **Continue with steps 3–4** (destination, confirm, write). Mined scars are usually repo-specific, so prefer the repo's `.claude/rules/scars-<area>.md`, scoped with `paths:` to the files the pairs touched.
