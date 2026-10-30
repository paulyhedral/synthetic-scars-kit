
## OpenSpec
In repos with an `openspec/` directory, run non-trivial work as OpenSpec changes (propose → apply → archive) instead of a `.state/` ledger. The active change's `tasks.md` is the ledger: tick tasks as they complete, and the SessionStart hook prints open changes on startup, resume and compaction. Approving the proposal counts as plan approval. Run `/scar` before archiving if the change needed corrections.
