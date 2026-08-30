# Claude Code model matrix — Orchestra workers

Cursor keeps `.cursor/skills/orchestrator/models.md` (Grok / Composer / Luna).
This file is the **Claude Code** matrix. Do not put it under `.claude/skills/` —
Cursor also loads that directory, and a second orchestrator skill would fork
the OS.

Claude workers live in `.claude/agents/`. Frontmatter `model` + `effort` is
what Claude Code honors. Aliases `fable` / `opus` / `sonnet` resolve to the
current generation; Orchestra pins **generation 5**.

| Tier | Roles | Model | Effort | Why |
|---|---|---|---|---|
| **Highest intelligence** | architect, planner, red-teamer, auditor, builder-max, pr-reviewer | `claude-fable-5` | `low` | Design, plan, attack, adjudicate, inclusive merge review. Fable 5 at low is the ceiling this host asked for. |
| **Middle ground** | scout, researcher, reviewer | `claude-opus-5` | `medium` | Recon, primary-source checks, per-ticket review — directed, not speculative. |
| **Execution** | builder, gatekeeper, janitor, releaser | `claude-sonnet-5` | `medium` | Planned and directed work: implement one ticket, run named gates, hygiene, land/deploy. |

The main session (orchestrator) is not a worker file. It inherits the Claude
session picker. Hold model and effort constant mid-session.

Workers set `disallowedTools: Agent` so they cannot nest. Fan-out stays on
the main session.

Do not add `.claude/skills/orchestrator/`. Claude reads the constitution at
`.cursor/skills/orchestrator/SKILL.md` (injected on SessionStart).
