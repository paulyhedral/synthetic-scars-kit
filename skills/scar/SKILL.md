---
name: scar
description: Turn this session's corrections, review catches and near-misses into 4-vector Synthetic Scars (Wound, Trap, Circuit breaker, Reflex) saved as path-scoped rules or feedback memories. Use at the end of a non-trivial task, when the user says "scar this", "remember this mistake", "/scar", or after a reviewer or the user had to correct the agent.
---

# /scar: consolidate this session's failures into scars

A scar replaces a "DON'T" rule. Quoting the bad pattern in a prohibition primes the model to repeat it; a scar names the failure, recognises the temptation, grants permission to stop, and supplies the replacement steps.

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
