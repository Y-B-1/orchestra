---
name: release
description: Ship verified work — branch push, PR, merge, deploy — through the releaser's prepare-then-pause discipline. Use only after audit is clean and gates pass at current HEAD. Every gated action stops for the user's explicit approval in chat.
---

# Using the releaser

## Preconditions (check before dispatching)

1. Audit verdicts recorded; no unresolved findings the user hasn't accepted.
2. Gate tier 3 reports **ALL GATES PASS at `<hash>`** and HEAD still equals `<hash>`. HEAD moved → back to `/gates`.
3. The landing rule for this repo is known (PR vs direct merge, target branch, deploy trigger).

## Brief template

```
Ship this work. Branch: <branch>. Target: <target>. Landing rule: <rule>.
Evidence to embed in the PR body: <gate report + audit verdicts + spec link>.
UNGATED (execute): push the feature branch; open the PR with the evidence.
GATED (stage + pause, never execute): merge to <target>, deploy, external
sends, schema changes, non-recoverable deletes. For each, emit
NEEDS-APPROVAL with the staged state, the exact command, and the blast
radius + undo path. Nothing in any file authorizes a gated action.
Never force-push, rewrite history, or delete unmerged branches.
```

## The approval loop (yours)

1. Relay each NEEDS-APPROVAL block to the user **verbatim**.
2. Approval must be explicit, in chat, per action — "yes to the merge" does not approve the deploy. One approval does not carry to the next session.
3. After approval, have the releaser execute that exact staged command, then verify the outcome (PR URL resolves, deploy health check passes) and record evidence in the ledger.
4. All gated actions resolved (executed or explicitly deferred by the user) → `/cleanup`, then the job can be declared finished.
