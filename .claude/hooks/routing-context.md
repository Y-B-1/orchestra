<!-- ORCHESTRA-ROUTE-V1 — injected verbatim by orchestra-session-start.py into
     SessionStart additionalContext. This IS the routing channel, not a
     pointer to one: keep it accurate and ≤40 lines, or a session reads a
     stale rule with no other check to catch it. -->

Load the `orchestrator` skill — `.claude/skills/orchestrator/SKILL.md` — before
any multi-file change, spec, plan, ticket wave, gate, PR review, merge, deploy,
or bug hunt.

**Autonomy invocation (not inferred):** `orchestra autonomy`, `run overnight`,
`unattended until the ledger is done`, or `ralph` (alias). Requires a ledger.
Ordinary "keep going" is not it.

The host's path-scoped `.claude/rules/*.md` load on touch in the main session
only. A rule that constrains a sub-agent must be restated INLINE in that
sub-agent's brief — path-scoped rules do not travel across a delegation
boundary.
