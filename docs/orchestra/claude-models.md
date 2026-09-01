# Claude Code model matrix — Orchestra workers

Cursor keeps `.cursor/skills/orchestrator/models.md` (Grok / Composer / Luna).
This file is the **Claude Code** matrix. The two are per-tool matrices, neither a
mirror of the other, so neither is generated from the other — both are edited by
hand. This one stays in `docs/orchestra/` rather than inside the orchestrator
skill so that loading the skill does not drag a table nobody asked for into
context; the skill points at it.

Claude workers live in `.claude/agents/`. Frontmatter `model` + `effort` is
what Claude Code honors. Aliases `fable` / `sonnet` resolve to the
current generation; Orchestra pins **generation 5**. Judgement's pinned id is
`claude-fable-5-1`; never the bare alias.

~~This file previously forbade adding `.claude/skills/orchestrator/` and
pointed Claude at `.cursor/skills/orchestrator/SKILL.md` instead — a second
orchestrator skill would fork the OS.~~ **Superseded 2026-09-02 (ruling U8,
`docs/plans/RULINGS-2026-09-01.md` in Equiti Hub; design
`docs/orchestra/SPEC-claude-native.md`).** `.claude/skills/orchestrator/` is
now the source of the constitution; `.cursor/skills/` is generated from it by
`docs/orchestra/sync-agent-config.py`.

## The ruling (user, 2026-09-02) — supersedes the earlier tiering

Two tiers, and the boundary is **what kind of thinking the role does**, never
the size of the task. There is no Opus row and no `[1m]` variant anywhere in
this matrix.

1. **Fable 5.1 at `low` holds every judgement role** — orchestrating, judging,
   advising, planning, red-teaming, adjudicating, reviewing. Fable never
   builds. Fable 5.1 at `low` also replaces Opus for the builder-max repair
   valve: the valve is a judgement pass applied to a build, never a bigger
   builder.
2. **Sonnet 5 carries execution and recon**, at whichever effort the role
   needs — never higher than `medium`, and a `high` justification must be
   written down. The work arrives already planned by Fable; Sonnet + a
   Fable-written brief is the efficient pair, which is the point of planning
   at the top tier.

**The repair valve — why builder-max exists in this matrix.** A Sonnet build
that comes back from review with findings does **not** get re-attempted by
Sonnet. builder-max, running Fable 5.1 at `low`, takes the repair: the same
judgement tier applied to a build rather than a bigger builder, so the pattern
behind the review's findings gets read before anything is rewritten.
Escalation is a role change, never a retry.

## The matrix

| Tier | Roles | Model | Effort | Why |
|---|---|---|---|---|
| **Judgement** | architect, planner, red-teamer, auditor, reviewer, pr-reviewer, builder-max | `claude-fable-5-1` | `low` | Design, plan, attack, adjudicate, per-ticket and inclusive merge review, and the repair valve. Every role whose output is a verdict, a brief, or a judged repair. |
| **Execution** | builder, gatekeeper, janitor, releaser, researcher | `claude-sonnet-5` | `medium` | Planned and directed work: implement one ticket, run named gates, hygiene, land/deploy, read primary sources. `high` only with a written justification; never higher. |
| **Recon** | scout | `claude-sonnet-5` | `low` | Read-only enumeration and lookup. No judgement in the output. |

The main session (orchestrator) is not a worker file. It inherits the Claude
session picker. Hold model and effort constant mid-session.

Workers set `disallowedTools: Agent` so they cannot nest. Fan-out stays on
the main session.
