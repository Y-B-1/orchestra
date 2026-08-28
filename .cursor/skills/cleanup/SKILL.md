---
name: cleanup
description: Main session only. Workers never load this. Close a batch — janitor inspection, orchestrator-executed removals, memory, STATE.md. Routing: flow.json execute.wave-close and cleanup.final.
disable-model-invocation: true
---

# Cleanup

The janitor proposes (brief: `briefs.md#janitor` — paste the ledger excerpt; it has no other context); you dispose. Dispatch it when worktrees exist or the batch spanned 2+ tickets; tiny batches get your own memory line instead.

## Your half (non-delegable)

1. **RESCUE NEEDED** → commit the rescue to its named branch, or confirm with the user the work is disposable. Never remove a dirty worktree; never leave a rescue on detached HEAD.
2. Execute `git worktree remove` for SAFE TO REMOVE paths, in the same turn the wave closes.
3. Commit the memory draft **in the batch-closing commit** — never separate, never skipped. Prune what the janitor marked stale.
4. **Adherence findings** (missing review verdicts, unmerged ticket branches, absent redteam record, stale gate hash, hook-failure log lines, missing AGENTS.md / memory-index headings) are process defects: fix the gap or report it honestly to the user — never tidy it away.
5. Job end (`cleanup.final`): zero live worktrees (`git worktree list`, including Cursor-managed paths and branches in `.orchestra/subagent-children.json`), ledger stamped CLOSED, STATE.md rewritten to idle keeping any `deferred:` line, expired RESEARCH.md deleted.

"Job is finished" is only sayable after this completes.
