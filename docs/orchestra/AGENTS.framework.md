# Project charter (CLAUDE.md)

This file is the **host project's** charter. Orchestra does not own it and must
not replace a filled copy. Keep every `##` heading. Fill the slots. Delete
nothing that is already project-specific.

Claude Code reads `CLAUDE.md`. Cursor reads `AGENTS.md`, which **must** be a
symlink to this file (`ln -sfn CLAUDE.md AGENTS.md`). Never symlink `AGENTS.md`
to `~/.claude/CLAUDE.md` or any path outside this repo.

A session that finds this file still full of `<angle-bracket slots>` should
fill them from the repo (README, remotes, existing conventions) — not invent
a second constitution.

## How to fill (do not delete)

- **Who you are**: what this repo *is* (product, line, stack). Never "You are
  the Orchestrator" — that identity lives only in the orchestrator skill, and
  only for the main session.
- **Memory**: point at this repo's long-term index. If the project already has
  `docs/AGENT-MEMORY.md` (or another cap/test), use that path. Do not start a
  second index.
- **Delivery**: one line plus `.orchestra/delivery.json`. Slots may stay as
  `<declare…>` until install writes the JSON; then replace the slot with the
  real landing rule.
- **Project rails**: ports, evidence rules, hooks this repo already had.
  Orchestra merges *into* them; it does not wipe them.
- **Janitor** (batch close) and the `sessionStart` heal hook keep headings
  present and append a missing `## Orchestra` block. They never overwrite
  filled slots.

## Who you are (project)

<one short paragraph: this repository's product and working line>

## Orchestra

When the **orchestrator skill** is loaded (pin it as a Custom Mode so it stays
on every turn), the **main session** is the orchestrator: it talks to the user,
dispatches named roles in `.cursor/agents/`, and declares terminal states.
Workers are those roles. They are not the orchestrator.

Routing: `.claude/skills/orchestrator/references/flow.json`. Briefs:
`.claude/skills/orchestrator/references/briefs.md`. Do not implement product code when a
builder can. Evidence is a command plus exit code, not a success report.

This graph is the only process in an Orchestra host. After intake the only
user-facing stop is unanswered frontier questions. Specs, plans, reviews,
merges, and deploys do not wait. Maximize parallel waves. Claude workers
live in `.claude/agents/`; the constitution is
`.claude/skills/orchestrator/SKILL.md`; `.cursor/` is generated from it.

If this heading is missing, the heal hook appends this section. It will not
touch **Who you are**, **Memory**, **Delivery**, or **Project rails**.

## Memory

Long-term index: `docs/AGENT-MEMORY.md` (or the path this project already
uses). Fill it using that file's **How to fill** section. Prune stale entries
in the same commit as the work. Git is the history.

## Delivery

Delivery: <declare per repo at install — provider, protected branches, landing
rule, server_side_gate, deploy policy per environment>

## Project rails (optional)

<repo-specific standing rails — ports, push policy, test commands, things a
generic orchestra must not clobber>
