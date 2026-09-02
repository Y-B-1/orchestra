# Model selection — policy, not hardcoding

Cursor meters two pools that reset monthly: **Cursor Models** (Grok 4.6, Composer 2.5) with far more included usage, and **Other Models** (Claude, GPT, Kimi) billed at raw API pass-through. There are **no multipliers and no automatic downgrade** — "Requests are never downgraded in quality or speed." When a pool runs out, work stops or costs on-demand money.

## The role tiering is fixed (user ruling, 2026-08-31)

Ladders below choose the MODEL inside a tier; they do not choose the tier. The
tiering itself is settled and identical on both hosts:

- **Judgement** (architect, planner, red-teamer, auditor, reviewer, pr-reviewer)
  — the top-intelligence tier at LOW effort. Judgement roles never build.
- **Repair** (builder-max) — the judgement tier applied to a build, at low.
  Fires only after a review returns findings. A cheap build that failed review
  is never retried at the same tier.
- **Execution** (builder, gatekeeper, janitor, releaser, researcher) and
  **Recon** (scout) — the cheap tiers, because Fable already planned the work.

On Claude Code that reads Fable 5.1 `low` / Sonnet 5 `medium` only — see
`docs/orchestra/claude-models.md`. Note that row 3 below still
lists `reviewer` under Build; on this repo reviewer is a JUDGEMENT role.

## What Cursor actually honors

1. **YAML `model:` on `.cursor/agents/<role>.md` is the owner** for that role. Put the picker slug (or `inherit`) there — not a competing session-start policy.
2. **Task `model` overrides YAML** unless the agent file sets `force-default-model: true`. Pinned roles (builder, reviewer, gatekeeper, releaser, scout, researcher, janitor) set that flag. **Omit** the Task `model` argument when dispatching them.
3. Judgement roles (architect, planner, red-teamer, auditor, reviewer, pr-reviewer) stay `model: inherit` so they ride the session ceiling. Do not set `force-default-model` on them.
4. An invalid YAML slug silently falls back to the parent. Confirm ids in the model picker; `install.sh` only checks that pinned roles are not `inherit`.
5. Record the chosen lineup in `.orchestra/state.json` under `models` (seed from `docs/orchestra/state.example.json` if missing) and **hold it constant** for the session (model and effort are part of the prompt-cache key).
6. When a tier's model becomes unavailable or its pool is exhausted, move down that tier's ladder, say so in chat, and record the change. Never silently upgrade a tier to a costlier pool.

`model: inherit` means "the parent's model," which for cheap high-volume roles is usually the wrong answer — that is why those roles are pinned.

## Ladders (first choice first)

| Tier | Roles | Ladder | Why |
|---|---|---|---|
| **Judgement** | architect, planner, red-teamer, auditor, reviewer, pr-reviewer | `claude-fable-5-1` → `grok-4.6[effort=xhigh]` | Fable 5.1 is the pinned judgement id — never the bare alias. Grok at xhigh is the cheap-pool escape hatch when Fable's pool is exhausted. Inclusive PR review sits here: it is a merge judgement, not a mechanical lint. |
| **Repair** | builder-max | `claude-fable-5-1[effort=low]` → `grok-4.6[effort=xhigh]` | The judgement tier applied to a build, fires only after a review returns findings — never a first attempt. Sonnet 5 at `medium` is the build ceiling; nothing higher, for any role. |
| **Build** | builder, reviewer | `grok-4.6[effort=high]` → `composer-2.5[fast=false]` → `gpt-5.6-sol` | Grok is in the roomy pool at $2/$6 and is built for long tool-using runs. High is the floor here; below it, review quality drops where it matters. |
| **Mechanical** | gatekeeper, janitor, releaser | `composer-2.5[fast=false]` → `grok-4.6[effort=medium]` | Cheapest option, tuned for tool use, file edits, and terminal work — exactly these roles. **`fast=false` matters: the fast variant costs 6x** ($3/$15 vs $0.5/$2.5) and buys latency these roles never need. |
| **Recon** | scout, researcher | `gpt-5.6-luna` → `composer-2.5[fast=false]` | Luna is $0.2/$1.2 and Cursor names it explicitly for "subagents and high-volume loops." Not frontier — which recon does not need. |

## Cost anchors (per 1M in → out)

Composer 2.5 $0.5 → $2.5 · Luna $0.2 → $1.2 · Grok 4.6 $2 → $6 · Sol $4 → $20 · **Fable 5 $10 → $50** (20x Composer). Fast variants bill roughly 2x, Composer-fast 6x.

## Caveats to verify per account

Only Grok 4.6 has a documented effort ladder (`xhigh` / `high` / `medium` / `low`). Whether Composer and Fable accept `effort=` is not documented — check the picker. Kimi K3 is hidden by default and may not appear. Cloud agents use a curated model list Cursor does not publish, so re-check the lineup when running there.
