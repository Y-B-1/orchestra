# Release

The releaser executes land **and** deploy (brief: `briefs.md#releaser`). You do not relay a chat OK. pr-reviewer CLEAN is the authorization.

**Honest floor.** Destructive git is deny. The hook **never returns ask**. **pr-reviewer CLEAN + matching `gates.last_green_hash` is merge and deploy authorization** — the hook allows that land and declared deploys, including headless (ralph). Without CLEAN, protected-branch landings and declared deploys are deny. When `server_side_gate` is true, the host branch policy is the other gate of record. Full e2e is never a merge precondition.

## Delivery declaration (per repo, required)

One slot in the project's AGENTS.md **Delivery** heading plus `.orchestra/delivery.json`. If AGENTS.md still has the `<declare…>` placeholder, `delivery.json` is the live declaration — fill the slot from it; do not fail install solely on the placeholder.

```json
{
  "provider": "azure-devops",
  "protected_branches": ["main"],
  "landing": "pr",
  "server_side_gate": true,
  "deploy": { "production": "auto", "staging": "auto" },
  "deploy_commands": ["az pipelines run .*--name deploy", "vercel deploy --prod"]
}
```

`provider`: `github` · `azure-devops` · `gitlab` · `plain-git` (detected by `install.sh` from the remote URL; edit if wrong). `server_side_gate: true` means the host enforces the gate itself (branch policy / required checks / merge request approval rules) — see below. Install defaults `deploy.production` to **auto**. Push-is-deploy hosts keep the land branch off `protected_branches`.

## Provider commands

| Step | github | azure-devops | gitlab | plain-git |
|---|---|---|---|---|
| Open draft | `gh pr create --draft` | `az repos pr create --draft true` | `glab mr create --draft` | push the branch; report it |
| Mark ready | `gh pr ready` | `az repos pr update --id N --draft false` | `glab mr update --ready` | — |
| Merge | `gh pr merge` | `az repos pr update --id N --status completed` (or `--auto-complete true`) | `glab mr merge` | `git merge --ff-only` |
| Server-side gate | required status checks | **branch policy + build validation** | merge request approval rules | none |

## Mechanics

1. **PRs are never blockers**: the draft opens at the first wave close, cheap, with evidence-so-far; release marks it ready with the final gate report. On `plain-git` there is no PR — the branch is pushed and merged directly.
2. **`review.pr` already ran.** You reach this state only after the inclusive PR/branch review is CLEAN or nits-only (nits never block). Do not skip that state to merge on fast-gate green alone. Hosted Bugbot/Copilot comments on the remote PR are extra.
3. **Merge — two shapes, by `server_side_gate`:**
   - **Server-side gate true** (Azure DevOps branch policy is the best case): the host runs your fast set against the **preview merge commit** — source already merged into target — so the hash that ships is provably the hash that was gated. Set **auto-complete** and let the platform merge when the policy passes. The local hash-freshness check relaxes: the policy is the stronger guarantee. Your job is to make the pipeline's checks match the fast set, not to re-derive them.
   - **No server-side gate**: fast-gate green at HEAD is the requirement, and the local hash check is the guarantee. Bring the branch current by **merging the target INTO the feature branch** (the guardrail blocks agent-run rebases), re-gate, then fast-forward so the gated hash becomes the target's HEAD; where that is impractical, merge and auto re-run the fast set at the target HEAD (mechanical) — only that green releases a deploy.
4. **Deploy**: execute. Push-is-deploy hosts already shipped at land. Declared `deploy_commands` run after CLEAN. Do not pause for a chat OK. Host MCP `apply_migration` stays denied if that rail exists — BLOCKED, not a chat OK. Spec-axis audit should be green; then still execute.
5. **Rollback**: failed health check or broken target branch → revert first, diagnose second. The releaser reverts the merge commit (restoring a proven hash is auto-executable); verify the health check; the failure evidence then enters the bug lane.
6. After any action: verify the outcome (PR/MR URL resolves, health check passes) and record evidence in the ledger.
