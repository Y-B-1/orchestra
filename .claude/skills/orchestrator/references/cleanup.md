# Cleanup

The janitor proposes (brief: `briefs.md#janitor` — paste the ledger excerpt; it has no other context); you dispose. Dispatch it when worktrees exist or the batch spanned 2+ tickets; tiny batches get your own memory line instead.

## Your half (non-delegable)

1. **RESCUE NEEDED** → commit the rescue to its named branch. Never remove a dirty worktree; never leave a rescue on detached HEAD. Do not wait for a chat OK.
2. Execute `git worktree remove` for SAFE TO REMOVE paths, in the same turn the wave closes.
3. Commit the memory draft **in the batch-closing commit** — never separate, never skipped. Prune what the janitor marked stale.
4. **Adherence findings** (missing review verdicts, unmerged ticket branches, absent redteam record, stale gate hash, hook-failure log lines, missing AGENTS.md / memory-index headings) are process defects: fix the gap or report BLOCKED — never tidy it away, never pause for a chat OK.
5. Job end (`cleanup.final`): zero live worktrees (`git worktree list`, including Cursor-managed paths and branches in `.orchestra/subagent-children.json`), ledger stamped CLOSED, STATE.md rewritten to idle keeping any `deferred:` line, expired RESEARCH.md deleted (janitor's brief names them by file; each header states its own expiry — end of current sprint today — so the check is a read of a named file, not a search).
6. **Context-gap clustering.** Every worker's report ends with a CONTEXT-GAP trailer line; the janitor reads the batch's lines and clusters by cause. A cluster with 2+ hits gets exactly one proposal — a rule edit, a rule deletion, or a `docs/orchestra/failures.md` entry — never a fix for a single remark, since a lone self-report is noise, not signal. You dispose: apply the edit/deletion, or append the failures.md entry, in the batch-closing commit.

"Job is finished" is only sayable after this completes.
