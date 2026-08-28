---
name: plan
description: Main session only. Workers never load this. Spec to red-teamed ticketed plan — planner plus three red-team lenses. Routing: flow.json plan.* states.
disable-model-invocation: true
---

# Plan

Goal: `docs/plans/YYYY-MM-DD-<feature>.md`, red-teamed and committed, plus its separate ledger file created at execution setup. The planner drafts and repairs; you review, dispatch skeptics, adjudicate, and record.

## Mechanics

1. **Recon only for gaps**: dispatch a scout when design recon left questions open, when ticket briefs need the path-rule harvest (`.cursor/rules` + AGENTS.md excerpts for touched paths, quoted verbatim), or when design happened in another session. Otherwise carry design's recon forward and say so in the plan.
2. **Research join**: version-sensitive tickets cite `RESEARCH.md` on disk. The planner marks tickets BLOCKED-ON-RESEARCH rather than guessing; check the file exists before red team.
3. **Draft**: planner (brief: `briefs.md#planner`) from spec + recon + research. On return: review the ticket summary table, diff quoted rulings against your record, resolve Open questions with the user before red team.
4. **Red team, always**: three lenses in parallel, fresh context (briefs: `briefs.md#red-teamer`). Repairs route to the planner (rounds 1–3, only the failed lens's findings); round 4+ you adjudicate. Spec-contradicting findings go to the user. Suspicion rule: only **READY with zero findings** on round 1 of a large/irreversible plan triggers a tightened rerun; READY-with-minor-findings is a normal, accepted outcome.
5. **Record**: verdicts, rounds, and run ids into `.orchestra/state.json` — the plan is not executable without its redteam record. Commit the plan.
