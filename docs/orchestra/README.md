# Orchestra document frameworks

These files are **shells**, not a second constitution.

| File | Role |
|---|---|
| `AGENTS.framework.md` | Charter template copied only when the host has no `AGENTS.md`. |
| `AGENT-MEMORY.framework.md` | Memory-index template copied only when no index exists. |
| `state.example.json` | Schema for gitignored `.orchestra/state.json`. Cloud clones start empty; copy this locally or commit what the next role needs. |
| `STATE.template.md` | Lives next to the orchestrator skill; working memory for one run. |
| `generate-flow-html.py` | Builds `docs/flow.html` from `flow.json` so the two cannot drift. |
| `HOOKS.md` | What Orchestra installs vs what a host keeps. Merge, never wipe host hooks. |

**Heal** (`.cursor/hooks/heal-orchestra-docs.py`, run from `sessionStart`): create missing files from the frameworks; append a missing `## Orchestra` block; prepend a missing **How to fill** on the memory index. Never overwrite filled project slots.

**Agent file = the role.** `.cursor/agents/<role>.md` is the empty-context job (system prompt). Cursor does **not** auto-bind `skills/<role>/SKILL.md` by name. Do not add a duplicate skill per worker. Phase skills under `.cursor/skills/` are hire playbooks for the **main session** only (`disable-model-invocation: true`). Briefs in `briefs.md` are extra payload per dispatch.

**Steward**: the **janitor** checks headings, prunes memory, and surfaces `.orchestra/hook-failures.log`. Charter hygiene is still that role — not a separate agent. (`pr-reviewer` is the inclusive pre-merge review, not a charter steward.) The orchestrator commits the janitor's draft at batch close.
