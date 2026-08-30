# Orchestra routing — Claude Code main session

This file is **not** a skill. Cursor must not treat it as one.

SUB-AGENT STOP: if you are a sub-agent executing a dispatched brief (your
prompt is a pasted brief naming your role — scout, researcher, architect,
planner, red-teamer, builder, builder-max, reviewer, pr-reviewer, auditor,
gatekeeper, janitor, releaser), ignore this file and execute your brief.

Main session: read `.cursor/skills/orchestrator/SKILL.md` and route via
`.cursor/skills/orchestrator/flow.json`. Announce every transition
(`flow: <from> -> <to> (<matched if>)`). Claude workers are
`.claude/agents/`. Models: `docs/orchestra/claude-models.md`.

- OPEN run in `docs/orchestra/STATE.md`: reconcile stamp vs HEAD vs tree first.
- After intake the only user-facing stop is unanswered frontier questions.
- Maximize parallelism: dispatch every unblocked ticket whose files do not
  overlap, in one message — including current waves from independent plans.
  Serial only on a blocking edge, shared file ownership, or a failed
  worktree proof.
- Evidence is a command plus exit code. Terminal states are honest.
