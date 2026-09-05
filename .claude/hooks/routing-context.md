<!-- ORCHESTRA-ROUTE-V1 — injected verbatim by orchestra-session-start.py into
     SessionStart additionalContext. This IS the routing channel, not a
     pointer to one: keep it accurate and ≤40 lines, or a session reads a
     stale rule with no other check to catch it. -->

Load the `orchestrator` skill — `.claude/skills/orchestrator/SKILL.md` — before
any multi-file change, spec, plan, ticket wave, gate, PR review, merge, deploy,
or bug hunt.

**Lane table** (size the ITEM, not the message — split, size each, escalate
only the complex ones):

| Change shape | How to run it |
| --- | --- |
| Question, explanation, doc read | Answer directly. No skill, no branch, no gates. |
| ≤3 files, no cross-cutting risk | Inline. Gates + the e2e specs the change touches. |
| Multi-file, engine/permission/data, or uncertain | Orchestra (`flow.json`). |
| Any bug | Orchestra `bug.feedback-loop` — root cause before fix, always. |

**Autonomy invocation (not inferred):** `orchestra autonomy`, `run overnight`,
`unattended until the ledger is done`, or `ralph` (alias). Requires a ledger.
Ordinary "keep going" is not it.

Path-scoped rules load on touch: `.claude/rules/pipeline.md`, `e2e.md`,
`migrations.md`, `engine-boundary.md`. A rule that constrains a sub-agent must
be restated INLINE in that sub-agent's brief — path-scoped rules do not travel
across a delegation boundary.
