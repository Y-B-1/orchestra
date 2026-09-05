# Model selection — policy, not hardcoding

MOVED 2026-09-02 from `.cursor/skills/orchestrator/models.md`, which was deleted when Cursor was
demoted to a worker runtime. A Cursor worker does not choose its own model — the coordinator picks
it with `orca orchestration worker-start --model`, from the chain in `docs/orchestra/orca-runtimes.json`.
These pools are what makes that choice affordable; Claude's own matrix is `docs/orchestra/claude-models.md`.

Cursor meters two pools that reset monthly: **Cursor Models** (Grok 4.6, Composer 2.5) with far more included usage, and **Other Models** (Claude, GPT, Kimi) billed at raw API pass-through. There are **no multipliers and no automatic downgrade** — "Requests are never downgraded in quality or speed." When a pool runs out, work stops or costs on-demand money.

## The role tiering is fixed (user ruling, 2026-08-31)

Ladders below choose the MODEL inside a tier; they do not choose the tier. The
tiering itself is settled and identical on both hosts:

- **Judgement** (architect, planner, red-teamer, auditor, reviewer, pr-reviewer)
  — the top-intelligence tier at LOW effort. Judgement roles never build.
- **Repair** (builder-max) — Opus 5 `medium`, the one Opus (U15). No Cursor route.
  Fires only after a review returns findings. A cheap build that failed review
  is never retried at the same tier.
- **Execution** (builder, gatekeeper, janitor, releaser, researcher) and
  **Recon** (scout) — the cheap tiers, because Fable already planned the work.

On Claude Code that reads Fable 5 `low` / Sonnet 5 `medium` only — see
`docs/orchestra/claude-models.md`. On this repo reviewer is a JUDGEMENT role;
its Cursor rung (`grok-4.6[effort=high]`) is the cheap-pool fallback the Orca
chain uses, not a tier change.

## What Cursor actually honors

1. **YAML `model:` on `.cursor/agents/<role>.md` names the default** for that role. The files are GENERATED (`scripts/generate-runtimes.py`) for Cursor-routed lanes only: red-teamer, auditor, reviewer, builder, builder-frontend, builder-speed, scout. Never hand-edit them.
2. **`worker-start --model` (or Task `model`) overrides YAML** — that is how the coordinator walks a fallback chain. The generated files do NOT set `force-default-model`, on purpose.
3. `model: inherit` appears in no generated file — every routed lane carries an explicit slug from `orca-runtimes.json`. A role with no Cursor step (architect, planner, pr-reviewer, builder-max, gatekeeper, janitor, releaser, researcher) has NO `.cursor/agents/` file and never runs on Cursor.
4. An invalid YAML slug silently falls back to the parent. Confirm ids in the model picker.
5. Record the chosen lineup in `.orchestra/state.json` under `models` (seed from `docs/orchestra/state.example.json` if missing) and **hold it constant** for the session (model and effort are part of the prompt-cache key).
6. When a tier's model becomes unavailable or its pool is exhausted, move down that tier's ladder, say so in chat, and record the change. Never silently upgrade a tier to a costlier pool.

`model: inherit` means "the parent's model," which for cheap high-volume roles is usually the wrong answer — that is why those roles are pinned.

## Ladders (first choice first)

| Tier | Roles | Ladder | Why |
|---|---|---|---|
| **Judgement** | architect, planner, red-teamer, auditor, reviewer, pr-reviewer | `claude-fable-5` → `grok-4.6[effort=xhigh]` | Fable 5 is the pinned judgement id — never the bare alias. Grok at xhigh is the cheap-pool escape hatch when Fable's pool is exhausted. Inclusive PR review sits here: it is a merge judgement, not a mechanical lint. |
| **Repair** | builder-max | **Claude only** — `claude-opus-5` at `medium` (U15, the one Opus); no Cursor rung | Fires only after a review returns findings — never a first attempt. Sonnet 5 at `medium` stays the build ceiling for first attempts. |
| **Build** | builder, builder-frontend, builder-speed, reviewer | `grok-4.6[effort=high]` → `gpt-5.6-sol` (via Codex step) | Grok is in the roomy pool at $2/$6 and is built for long tool-using runs. High is the floor here. **Luna and Composer never build** (`orca-model-matrix.md` standing ban) — Composer left this ladder 2026-09-03. |
| **Mechanical** | gatekeeper, janitor, releaser | **Claude only** — no Cursor rung (`orca-model-matrix.md`: these roles never leave Claude) | Verification and release honesty stay on the host that carries the hooks. |
| **Recon** | scout | `grok-4.6[effort=high]` (fast lane at dispatch) → `composer-2.5[fast=false]` | Recon reads, never builds, so Composer is permitted here. Researcher routes Codex/OpenCode, not Cursor. |

## Cost anchors (per 1M in → out)

Composer 2.5 $0.5 → $2.5 · Luna $0.2 → $1.2 · Grok 4.6 $2 → $6 · Sol $4 → $20 · **Fable 5 $10 → $50** (20x Composer). Fast variants bill roughly 2x, Composer-fast 6x.

## Caveats to verify per account

Only Grok 4.6 has a documented effort ladder (`xhigh` / `high` / `medium` / `low`). Whether Composer and Fable accept `effort=` is not documented — check the picker. Kimi K3 is hidden by default and may not appear. Cloud agents use a curated model list Cursor does not publish, so re-check the lineup when running there.
