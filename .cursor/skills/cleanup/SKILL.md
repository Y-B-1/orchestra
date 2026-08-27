---
name: cleanup
description: Close a batch safely — janitor inspects worktrees and drafts the memory update; the orchestrator executes removals and lands the memory in the batch-closing commit. Use at every wave/batch close and at job end.
---

# Using the janitor

The janitor proposes; you dispose. It cannot know which work is truly finished — you hold that context.

## Brief template

```
Batch closing: <wave/batch id>. Inspect and report, execute nothing destructive.
1. WORKTREES: for each of <paths / `git worktree list`>: check the DIRECTORY
   (`git -C <path> status --porcelain`), not the refs. Dirty → RESCUE NEEDED
   with files + exact rescue commands (commit to a NAMED branch, never detached
   HEAD, never git stash). Clean+merged → SAFE TO REMOVE + exact command.
2. MEMORY: draft the update to docs/AGENT-MEMORY.md for this batch — decisions,
   traps, proving commands — and PRUNE entries the batch made stale. Write the
   draft to the file; do not commit.
3. SWEEP: list (don't delete) expired RESEARCH.md, [DEBUG-] log lines left in
   code, harvested throwaway branches, dead subagent state files.
```

## Your half (non-delegable)

1. **RESCUE NEEDED** → decide: commit the rescue to its named branch, or confirm with the user that the work is disposable. Never remove a dirty worktree.
2. Execute `git worktree remove` for SAFE TO REMOVE paths — in the same turn the wave closes. You created them; you remove them.
3. Commit the memory draft **in the same commit that closes the batch** — never a separate "update memory" commit, never skipped.
4. Sweep items: delete what you can verify is dead; anything uncertain gets one line to the user instead.

"Job is finished" is only sayable after this skill completes.
