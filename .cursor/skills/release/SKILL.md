---
name: release
description: Ship verified work — early draft PRs, merge on fast-gate green with the gated hash as the shipped hash, per-repo deploy policy, prepare-then-pause at the approval floor, revert-first rollback. Routing: flow.json release.* states.
---

# Release

The releaser executes (brief: `briefs.md#releaser`); you relay deploy approvals. The deterministic floor: the hook surfaces a Cursor **ask** on any push/merge to a protected branch (git or `gh pr merge`) and on declared deploy commands, and denies protected merges while `.orchestra/state.json`'s `gates.last_green_hash` ≠ HEAD. **That ask IS the merge approval** — merges are not additionally staged-and-paused. The floor covers protected-branch git/gh operations and the `deploy_commands` patterns declared in `.orchestra/delivery.json`; anything else relies on the releaser's discipline. The NEEDS-APPROVAL block remains the channel for deploys and other gated actions.

## Delivery declaration (per repo, required)

One line in the project's AGENTS.md plus `.orchestra/delivery.json`:

```json
{ "protected_branches": ["main"], "landing": "pr", "deploy": { "production": "approval", "staging": "auto" } }
```

Blast radius is a property of the repo, not the workflow — `deploy: auto` only for environments the user explicitly marks low-blast. **A diff containing migrations or schema changes never auto-deploys, regardless of policy.**

## Mechanics

1. **PRs are never blockers**: the draft PR opens at the first wave close, cheap, with evidence-so-far. Release flips it to ready with the final gate report.
2. **Merge**: fast-gate green at HEAD is the requirement. Bring the branch up to date by **merging main INTO the feature branch** (the guardrail blocks agent-run rebases), re-gate, then fast-forward main so the gated hash IS the new main HEAD; where that is impractical, merge and auto re-run the fast set at main HEAD (mechanical, non-approval) — only that green releases a deploy.
3. **Deploy**: per the declaration. Gated deploys: relay the NEEDS-APPROVAL block verbatim; approval is explicit, per action, in chat ("yes to the merge" does not approve the deploy); re-dispatch with the authorization block (`briefs.md#releaser`) — you are the trust anchor; never paste an approval the user did not say. A production deploy additionally requires the spec-axis audit green.
4. **Rollback**: failed health check or broken main → revert first, diagnose second. The releaser stages the revert of the merge commit (restoring a proven hash is auto-executable); verify the health check; then the failure evidence enters the bug lane.
5. After any approved action: verify the outcome (PR URL resolves, health check passes) and record evidence in the ledger. Deferred gated actions get a `deferred:` line in STATE.md that survives the idle reset.
