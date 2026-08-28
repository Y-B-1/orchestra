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
- **charter** · `AGENTS.md`, `docs/AGENT-MEMORY.md` · 2026-08-28 · These are fill-in frameworks (headings + how-to-fill), not a forced constitution; janitor + `sessionStart` heal steward them; never clobber a host's filled slots.
- **identity** · `.cursor/skills/orchestrator/SKILL.md` · 2026-08-28 · "You are the Orchestrator" belongs only in the orchestrator skill (main session). `AGENTS.md` alwaysApply must not inject that identity into workers.
- **parked** · agent-count / target roster · 2026-08-28 · Folding janitor/releaser/researcher/builder-max is still paused. `pr-reviewer` was added by request (13th worker); do not treat that as a license to fold the original twelve.
- **pr-reviewer** · `.cursor/agents/pr-reviewer.md`, `flow.json` `review.pr` · 2026-08-28 · Inclusive whole-PR/branch review after the fast gate, before merge. Does not replace gatekeeper, per-ticket reviewer, or two-axis auditor. Nits/Trivial never block. Runs on PR-landing and direct-landing.
- **skill-lock** · `.cursor/skills/*/SKILL.md` `disable-model-invocation: true` · 2026-08-28 · Phase skills (including orchestrator and pr-review) must not auto-load into workers. `install.sh` fails if the flag is missing.
- **package-version** · `VERSION` → `.orchestra/package-version` · 2026-08-28 · Stamp is `0.2.0` plus `git describe`; gitignore exception so hosts can commit it.
