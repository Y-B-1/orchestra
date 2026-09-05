# Claude Code model matrix — Orchestra workers

Cursor's own pools live at `docs/orchestra/cursor-models.md` (Grok / Composer / Luna).
This file is the **Claude Code** matrix. The two are per-tool matrices, neither a
mirror of the other, so neither is generated from the other — both are edited by
hand. This one stays in `docs/orchestra/` rather than inside the orchestrator
skill so that loading the skill does not drag a table nobody asked for into
context; the skill points at it.

Claude workers live in `.claude/agents/`. Frontmatter `model` + `effort` is
what Claude Code honors. Aliases `fable` / `sonnet` resolve to the
current generation; Orchestra pins **generation 5**. Judgement's pinned id is
`claude-fable-5`; never the bare alias.

## The ruling (user, 2026-09-02) — supersedes the earlier tiering

Two tiers, and the boundary is **what kind of thinking the role does**, never
the size of the task. Only these two model ids, no `[1m]` variant anywhere.

1. **Fable 5 at `low` holds every judgement role** — orchestrating, judging,
   advising, planning, red-teaming, adjudicating and reviewing. Fable never
   builds. The repair valve (builder-max) is the exception to the two tiers:
   Opus 5 at `medium`, and the only Opus in the system (U15).
2. **Sonnet 5 at `medium` is the build ceiling. Strictly nothing higher**
   (`high` only with a written justification beside it). Sonnet carries the
   majority of the work, because the work arrives already planned by Fable.
   Sonnet + a Fable-written brief is the efficient pair; that is the point of
   planning at the top tier.

**The repair valve — the reason builder-max exists in this matrix.** A Sonnet
build that comes back from review with findings does **not** get re-attempted
by Sonnet. **builder-max on Opus 5 at `medium`** takes the repair (U15): a
different model reading the same ticket, not a bigger attempt by the one that
review caught and the same class of miss does not recur. Escalation is a tier
change, never a retry.

## The matrix


| Tier | Roles | Model | Effort | Why |
|---|---|---|---|---|
| **Judgement** | architect, founder-mind, planner, red-teamer, auditor, reviewer, pr-reviewer | `claude-fable-5` | `low` | Design, plan, attack, adjudicate, per-ticket and inclusive merge review. Every role whose output is a verdict or a brief. |
| **Repair** | builder-max | `claude-opus-5` | `medium` | The ONE Opus in the system (U15). Fires only after a Sonnet build returns findings — never a first attempt, never for a fresh ticket. |
| **Execution** | builder, gatekeeper, janitor, releaser, researcher | `claude-sonnet-5` | `medium` | Planned and directed work: implement one ticket, run named gates, hygiene, land/deploy, read primary sources. |
| **Recon** | scout | `claude-sonnet-5` | `low` | Read-only enumeration and lookup. No judgement in the output. |

The main session (orchestrator) is not a worker file. It inherits the Claude
session picker. Hold model and effort constant mid-session.

Workers set `disallowedTools: Agent` so they cannot nest. Fan-out stays on
the main session.

**Reversed by the user, 2026-09-01** (this file previously forbade it): the
orchestrator skill is now **`.claude/skills/orchestrator/`** — a real Claude skill
that the session can load, not a hook message pointing at a Cursor path. **Cursor is a worker runtime and only a worker runtime** (2026-09-02): it takes a dispatched
ticket and executes its brief. It never routes and is never offered the orchestrator. Only
`.cursor/agents/<role>.md` for the five Cursor-routed worker lanes are generated; there is no
`.cursor/skills/orchestrator/` and no `orchestra-router.mdc`, and `sync-agent-config.py --check`
arm 13 fails if either reappears. The same holds for OpenCode. **The orchestrator seat is Claude
Code or Codex.** `docs/orchestra/RUN-RECORD.md` is where a run is opened and closed.

## Fallback: when a judgement model is exhausted

The matrix's own escape: *only when the judgement model's usage is exhausted do the
judgement roles fall back to the strongest available model.* Apply it by editing the
`model:` line in the affected `.claude/agents/*.md` frontmatter — **the guard's own remedy
is to fix the agent's frontmatter, never to pass a dispatch override**, because YAML owns
the matrix and an override silently disables the repair valve. Build roles never move:
Sonnet 5 `medium` is the build ceiling regardless.

Record the fallback with its date and its trigger, and restore the matrix model when usage
resets. A fallback is a temporary state of one host, not a re-ruling — it does not belong
in this package's table.
