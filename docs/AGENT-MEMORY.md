# Agent memory — Orchestra Roster

> Index, not a transcript. Path- and topic-tagged. Prune when stale. Git is
> the history — no "superseded by" markers.

## How to fill (do not delete)

- One entry = **topic** · **path or symbol** · **as-of date** · **one-line lesson**.
- Write in the same commit as the work the lesson came from.
- Load on demand (by path/topic). Never dump the whole file into a prompt.
- When an entry is wrong or obsolete, **delete it**. Git remembers.
- Cap: keep this index short enough to read cold.
- Janitor at wave/batch close: add lessons from the ledger excerpt, prune what
  the batch made stale, report what it changed. The orchestrator commits the
  draft in the batch-closing commit.
- Heal hook: if this file is missing, copy the framework. If **How to fill** is
  missing, prepend it. Never wipe **Current**.

## Current

- **snapshot** · sibling `../orchestra-roster` · 2026-08-28 · Frozen Claude original; living package is GitHub `Y-B-1/orchestra`.
- **charter** · `CLAUDE.md` + `AGENTS.md` → `CLAUDE.md` · 2026-08-28 · Fill-in frameworks; janitor + `sessionStart` heal steward them; never clobber filled slots; never symlink to `~/.claude/CLAUDE.md`.
- **independence** · Orchestra package · 2026-08-28 · Orchestra does not inherit Charge. Hosts that run Orchestra use `flow.json` only.
- **autonomy** · `flow.json` `autonomy.loop` · 2026-08-30 · Named invocation only. After pr-reviewer CLEAN the releaser lands **and deploys**; full e2e is never in the chain. Do not halt for deploy.
- **a-to-z** · Orchestra A-to-Z · 2026-08-30 · After intake the only user-facing stop is unanswered frontier questions. Specs, plans, reviews, merges, and deploys do not wait. The hook never returns ask.
- **claude-runtime** · `.claude/agents/`, `docs/orchestra/claude-models.md` · 2026-08-30 · Second harness beside Cursor. Fable 5 low / Opus 5 medium / Sonnet 5 medium. No `.claude/skills/orchestrator/`.
- **parallel-waves** · planner + `flow.json` · 2026-08-30 · Maximize concurrent builders; exclusive file lists; independent plans' current waves run together; serial only on collision or failed isolation.
- **identity** · `.cursor/skills/orchestrator/SKILL.md` · 2026-08-28 · "You are the Orchestrator" belongs only in the orchestrator skill (main session). `AGENTS.md` alwaysApply must not inject that identity into workers.
- **parked** · agent-count / target roster · 2026-08-28 · Folding janitor/releaser/researcher/builder-max is still paused. `pr-reviewer` was added by request (13th worker); do not treat that as a license to fold the original twelve.
- **pr-reviewer** · `.cursor/agents/pr-reviewer.md`, `flow.json` `review.pr` · 2026-08-28 · Inclusive whole-PR/branch review after the fast gate, before merge. Does not replace gatekeeper, per-ticket reviewer, or two-axis auditor. Nits/Trivial never block. Runs on PR-landing and direct-landing.
- **skill-lock** · `.cursor/skills/*/SKILL.md` `disable-model-invocation: true` · 2026-08-28 · Phase skills (including orchestrator and pr-review) must not auto-load into workers. `install.sh` fails if the flag is missing.
- **hooks** · `docs/orchestra/HOOKS.md` · 2026-08-30 · Orchestra ships four scripts / three events. Host rails stay except `block-pr-merge.sh`, which install strips. Hook never returns ask. pr-reviewer CLEAN + matching gate hash is merge and deploy authorization (hook allows headless). Full e2e is never in the chain.
