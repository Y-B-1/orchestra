# Orchestra Roster

This file is the **project charter**. Claude Code reads `CLAUDE.md`. Cursor
reads `AGENTS.md`, which **must** be a symlink to this file — never to
`~/.claude/CLAUDE.md` or any path outside this repo. Orchestra does not own a
host's filled copy. Keep every `##` heading.

## How to fill (do not delete)

- **Who you are**: what this repo *is*. Never "You are the Orchestrator" — that
  identity lives only in `.cursor/skills/orchestrator/SKILL.md`, and only for
  the main session.
- **Memory**: one index. If the project already has `docs/AGENT-MEMORY.md` (or
  another cap/test), use that path.
- **Delivery**: one line plus `.orchestra/delivery.json`.
- **Project rails**: ports, evidence rules, hooks this repo already had.
  Orchestra merges into them; it does not wipe them.
- The `sessionStart` heal hook and the **janitor** keep headings present and
  append a missing `## Orchestra` block. They never overwrite filled slots.

## Who you are (project)

This repository is the Orchestra Roster package: a portable Cursor multi-agent
operating system (thirteen named worker roles, a routing graph, guardrail hooks).
It is not an application product. Copy or merge it into a host repo; do not
overwrite that host's charter.

## Orchestra

When the **orchestrator skill** is loaded (pin it as a Custom Mode so it stays
on every turn), the **main session** is the orchestrator: it talks to the user,
dispatches named roles in `.cursor/agents/`, and declares terminal states.
Workers are those roles. They are not the orchestrator.

Routing: `.cursor/skills/orchestrator/flow.json`. Briefs:
`.cursor/skills/orchestrator/briefs.md`. Do not implement product code when a
builder can. Evidence is a command plus exit code, not a success report.

This graph is the only process in an Orchestra host. After intake the only
user-facing stop is unanswered frontier questions. Specs, plans, reviews,
merges, and deploys do not wait. Maximize parallel waves: hire every
non-overlapping unblocked ticket in one message.

Claude Code is a second runtime: workers in `.claude/agents/`, models in
`docs/orchestra/claude-models.md`. The constitution stays
`.cursor/skills/orchestrator/SKILL.md` — never a second skill under
`.claude/skills/`.

## Memory

Long-term index: `docs/AGENT-MEMORY.md`. Fill it using that file's **How to
fill** section. Prune stale entries in the same commit as the work. Git is the
history.

## Delivery

Delivery: GitHub (`Y-B-1/orchestra`); `main` is protected; landing is
direct; no product deploy. Hosts on Azure DevOps or GitHub set `provider` in
`.orchestra/delivery.json` (`gh` or `az repos`). Host repos replace this line.

## Project rails (optional)

- Work in this package (GitHub: `Y-B-1/orchestra`). The sibling
  `orchestra-roster` folder is a frozen Claude snapshot — do not edit it.
- Keep the original twelve worker roles until the parked agent-count discussion
  reopens. `pr-reviewer` was added by request (inclusive pre-merge review) —
  that is a thirteenth role, not a fold of the twelve.
- Merge into living hosts; never `cp -R` over an existing charter or host
  hooks. What Orchestra installs vs keeps: `docs/orchestra/HOOKS.md`.
- `AGENTS.md` → `CLAUDE.md` (this file). Heal refuses a link to
  `~/.claude/CLAUDE.md`.
