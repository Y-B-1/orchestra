---
name: gates
description: How to brief the gatekeeper for each verification tier — fast per-wave, scoped e2e per unit, derived pre-merge set, full suite only on explicit order. Gate evidence is exit codes at a named commit; any later commit voids it.
---

# Using the gatekeeper

Match the tier to the blast radius. Never escalate a tier out of anxiety; never skip one out of optimism.

| Tier | When | Contents |
|---|---|---|
| 1 Fast | every wave close | lint + typecheck + unit tests scoped to changed surface |
| 2 Scoped e2e | per work unit with a user-facing flow | the e2e specs covering changed flows, isolated port |
| 3 Derived pre-merge | before release prep | changed-surface specs + smoke core, derived from the actual diff |
| 4 Full suite | ONLY on the user's explicit order | everything; run in a quiet worktree or as a background run, never on the critical path |

## Brief template

```
TIER <n>. Commit under test: <hash>. Run exactly:
1. <command>
2. <command>
For tier 3: derive the spec set from this diff file list and state your mapping:
<files>
Report per command: verbatim command, exit code, PASS/FAIL/FLAKY, failure
excerpt. Run every command as `cmd > /tmp/gate-N.log 2>&1; echo exit:$?`;
never pipe through grep/tail. Do not fix anything, even trivially. A named
command that doesn't exist is a finding. End: ALL GATES PASS at <hash> or
BLOCKED: <gate>.
```

## Consuming the report

- FAIL → findings loop to a builder; then **re-run the tier** (the old green is void).
- FLAKY → a finding in its own right; ticket it, do not loop-until-green.
- ALL GATES PASS at `<hash>` → record hash + report in the ledger; HEAD must still equal that hash when `/release` stages the merge.
