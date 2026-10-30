## Task state ledger (`.state/`)
Skip for ad-hoc Q&A. For multi-step tasks, keep state on disk in `<project-root>/.state/` (globally git-ignored). If the repo already has its own task ledger (a spec tool's task list, say), use that instead.
- `00_governance.md` (write once): task scope and which steps need my approval.
- `10_ticket.md` (write once): ticket/issue link, branch, acceptance criteria.
- `20_plan_approved.md` (write once, after I approve the plan): approved files and invariants.
- `30_review.md` (append only): each review round's blockers, fixes, false positives.
- `99_next_action.md` (overwrite at each step): done / current / next permitted action.
A SessionStart hook prints these on startup, resume and compaction. Trust them over the compaction summary. Don't rewrite `99_next_action.md` while a background subagent is still running.

## Synthetic scars
Write corrective rules (rules files, feedback memories) as scars, never as bare "DON'T" rules that quote the bad pattern:
1. **Wound**: the concrete failure that happened.
2. **Trap**: the tempting shortcut that leads there, named so you recognise it.
3. **Circuit breaker**: explicit permission to stop and push back or counter-offer instead of forcing it.
4. **Reflex**: the ordered steps to do instead.
Run `/scar` at the end of a non-trivial task if I had to correct you or a review caught something.
