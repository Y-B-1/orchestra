# Model selection — policy, not hardcoding

Cursor meters two pools that reset monthly: **Cursor Models** (Grok 4.6, Composer 2.5) with far more included usage, and **Other Models** (Claude, GPT, Kimi) billed at raw API pass-through. There are **no multipliers and no automatic downgrade** — "Requests are never downgraded in quality or speed." When a pool runs out, work stops or costs on-demand money. So model choice is the orchestrator's job at session start, not a value frozen in a file.

## The policy

1. **At session start**, check what the account actually offers (the model picker, or `Cursor.models.list()` in the SDK). Pick one id per tier from the ladders below — first available wins.
2. **Record the chosen lineup** in `.orchestra/state.json` under `models`, and **hold it constant for the session** (model and effort are part of the prompt-cache key).
3. **When a tier's model becomes unavailable or its pool is exhausted**, move down that tier's ladder, say so in chat, and record the change. Never silently upgrade a tier to a costlier pool.
4. Sub-agents may run a different model than the parent — that is the point of the ladders. `model: inherit` means "the parent's model," which for cheap high-volume roles is usually the wrong answer.

## Ladders (first choice first)

| Tier | Roles | Ladder | Why |
|---|---|---|---|
| **Judgement** | architect, planner, red-teamer, auditor, builder-max | `claude-opus-5[effort=high]` → `claude-fable-5` → `grok-4.6[effort=xhigh]` | Opus 5 lands "on par with Fable 5 on CursorBench at Opus pricing" and often finishes faster — half the cost for the same bench. Reach for Fable 5 only when a decision is genuinely hard. Grok at xhigh is the cheap-pool escape hatch. |
| **Build** | builder, reviewer | `grok-4.6[effort=high]` → `composer-2.5[fast=false]` → `gpt-5.6-sol` | Grok is in the roomy pool at $2/$6 and is built for long tool-using runs. High is the floor here; below it, review quality drops where it matters. |
| **Mechanical** | gatekeeper, janitor, releaser | `composer-2.5[fast=false]` → `grok-4.6[effort=medium]` | Cheapest option, tuned for tool use, file edits, and terminal work — exactly these roles. **`fast=false` matters: the fast variant costs 6x** ($3/$15 vs $0.5/$2.5) and buys latency these roles never need. |
| **Recon** | scout, researcher | `gpt-5.6-luna` → `composer-2.5[fast=false]` | Luna is $0.2/$1.2 and Cursor names it explicitly for "subagents and high-volume loops." Not frontier — which recon does not need. |

## Cost anchors (per 1M in → out)

Composer 2.5 $0.5 → $2.5 · Luna $0.2 → $1.2 · Grok 4.6 $2 → $6 · Sol $4 → $20 · Opus 5 $5 → $25 · **Fable 5 $10 → $50** (20x Composer). Fast variants bill roughly 2x, Composer-fast 6x.

## Caveats to verify per account

Only Grok 4.6 has a documented effort ladder (`xhigh` / `high` / `medium` / `low`); `claude-opus-5[effort=high]` is documented by example. Whether Composer and Fable accept `effort=` is not documented — check the picker. Kimi K3 is hidden by default and may not appear. Cloud agents use a curated model list Cursor does not publish, so re-check the lineup when running there.
