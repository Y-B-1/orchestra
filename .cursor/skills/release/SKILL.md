---
name: release
description: Ship verified work on any host — GitHub, Azure DevOps, GitLab, or plain git. Early draft PRs, merge on fast-gate green with the gated hash as the shipped hash, per-repo deploy policy, prepare-then-pause at the approval floor, revert-first rollback. Routing: flow.json release.* states.
---

# Release

The releaser executes (brief: `briefs.md#releaser`); you relay deploy approvals. The deterministic floor: the hook surfaces a Cursor **ask** on any push/merge to a protected branch — plain `git`, `gh pr merge`, `az repos pr` completion, or `glab mr merge` — and on declared deploy commands, and denies protected merges while `.orchestra/state.json`'s `gates.last_green_hash` ≠ HEAD. **That ask IS the merge approval** — merges are not additionally staged-and-paused. The floor covers protected-branch git/CLI operations and the `deploy_commands` patterns in `.orchestra/delivery.json`; anything else relies on the releaser's discipline. The NEEDS-APPROVAL block remains the channel for deploys and other gated actions.

## Delivery declaration (per repo, required)

One line in the project's AGENTS.md plus `.orchestra/delivery.json`:

```json
{
  "provider": "azure-devops",
  "protected_branches": ["main"],
  "landing": "pr",
  "server_side_gate": true,
  "deploy": { "production": "approval", "staging": "auto" },
  "deploy_commands": ["az pipelines run .*--name deploy", "vercel deploy --prod"]
}
```

`provider`: `github` · `azure-devops` · `gitlab` · `plain-git` (detected by `install.sh` from the remote URL; edit if wrong). `server_side_gate: true` means the host enforces the gate itself (branch policy / required checks / merge request approval rules) — see below. Blast radius is a property of the repo: `deploy: auto` only for environments you explicitly mark low-blast, and **a diff containing migrations or schema changes never auto-deploys, regardless of policy.**

## Provider commands

| Step | github | azure-devops | gitlab | plain-git |
|---|---|---|---|---|
| Open draft | `gh pr create --draft` | `az repos pr create --draft true` | `glab mr create --draft` | push the branch; report it |
| Mark ready | `gh pr ready` | `az repos pr update --id N --draft false` | `glab mr update --ready` | — |
| Merge | `gh pr merge` | `az repos pr update --id N --status completed` (or `--auto-complete true`) | `glab mr merge` | `git merge --ff-only` |
| Server-side gate | required status checks | **branch policy + build validation** | merge request approval rules | none |

## Mechanics

1. **PRs are never blockers**: the draft opens at the first wave close, cheap, with evidence-so-far; release marks it ready with the final gate report. On `plain-git` there is no PR — the branch is pushed and merged directly.
2. **Merge — two shapes, by `server_side_gate`:**
   - **Server-side gate true** (Azure DevOps branch policy is the best case): the host runs your fast set against the **preview merge commit** — source already merged into target — so the hash that ships is provably the hash that was gated. Set **auto-complete** and let the platform merge when the policy passes. The local hash-freshness check relaxes: the policy is the stronger guarantee. Your job is to make the pipeline's checks match the fast set, not to re-derive them.
   - **No server-side gate**: fast-gate green at HEAD is the requirement, and the local hash check is the guarantee. Bring the branch current by **merging the target INTO the feature branch** (the guardrail blocks agent-run rebases), re-gate, then fast-forward so the gated hash becomes the target's HEAD; where that is impractical, merge and auto re-run the fast set at the target HEAD (mechanical, non-approval) — only that green releases a deploy.
3. **Deploy**: per the declaration. Gated deploys: relay the NEEDS-APPROVAL block verbatim; approval is explicit, per action, in chat ("yes to the merge" does not approve the deploy); re-dispatch with the authorization block (`briefs.md#releaser`) — you are the trust anchor; never paste an approval the user did not say. A production deploy additionally requires the spec-axis audit green. On Azure DevOps, a **Pipelines environment approval check** is the natural home for this gate — when one exists, say so and let the platform hold the pause.
4. **Rollback**: failed health check or broken target branch → revert first, diagnose second. The releaser stages the revert of the merge commit (restoring a proven hash is auto-executable); verify the health check; the failure evidence then enters the bug lane.
5. After any approved action: verify the outcome (PR/MR URL resolves, health check passes) and record evidence in the ledger. Deferred gated actions get a `deferred:` line in STATE.md that survives the idle reset.
