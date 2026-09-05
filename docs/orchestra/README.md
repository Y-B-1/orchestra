# Orchestra document frameworks

These files are **shells**, not a second constitution.

| File | Role |
|---|---|
| `AGENTS.framework.md` | Charter template written to `CLAUDE.md` when the host has none. `AGENTS.md` is a symlink to that file. |
| `AGENT-MEMORY.framework.md` | Memory-index template copied only when no index exists. |
| `reviews/` | **The ONE home for PR-review records** (top-level copies moved in, 2026-09-03). |
| `RUN-RECORD.md` | **How a session opens, stamps and closes a run** — the two record files, who writes each, and at which flow transition. Read this before writing either. |
| `STATE.md` | The live run record for **this** repo's current run. Rewritten at wave/batch close; committed only inside batch-closing commits. |
| `state.example.json` | Schema for gitignored `.orchestra/state.json`. Cloud clones start empty; copy this locally or commit what the next role needs. |
| `STATE.template.md` | Lives next to the orchestrator skill; working memory for one run. |
| `SPEC-claude-native.md` | The contract for `.claude/` as source and `.cursor/` as generated. |
| `RESEARCH-*.md` | Cached primary-source findings. Expire them with the batch or they mislead. |
| `generate-flow-html.py` | Builds `docs/flow.html` from `flow.json` so the two cannot drift. |
| `claude-models.md` | Claude Code matrix (Fable 5 low / Sonnet 5 medium). |
| `codex-models.json` / `codex-models.md` | Native Codex child-role model contract and its human explanation; separate from Orca fallback chains. |
| `codex-native.md` | Source/generated ownership, worker versus explicit coordinator modes, hook trust, and validation receipts. |
| `codex-cloud.md` | Cloud setup and the credential boundary: cloud can return a verified branch/PR, but setup-only secrets do not authorize Azure land/deploy. |
| `claude-settings.fragment.json` | Hook upserts for `.claude/settings.json`. |
| `HOOKS.md` | What Orchestra installs vs what a host keeps. Merge, never wipe host hooks. |
| `claude-version.stamp` | Last-seen `claude --version`. SessionStart compares and prints a `claude doctor` reminder on mismatch (Part 8.4). Update it after running doctor. |

**Upstream push** (Part 7.3): portable Orchestra changes — anything under
`.claude/agents/` or `.claude/skills/orchestrator/` that is not a host-specific
delta — ride in the batch-closing commit **and** are pushed to
`orchestra-roster-next` in that same close. Host-specific deltas (this repo's
own rules, project vocabulary, Azure-only wiring) stay here. SessionStart's
`[upstream-drift]` line counts files that differ from the upstream checkout so
the push is prompted every session instead of forgotten.

**Heal** (`.claude/hooks/heal-orchestra-docs.py`, source — `.cursor/hooks/` carries a thin adapter; run from `sessionStart`): create missing `CLAUDE.md` from the framework; make `AGENTS.md` a symlink to it; refuse a link to `~/.claude/CLAUDE.md`; append a missing `## Orchestra` block; prepend a missing **How to fill** on the memory index. Never overwrite filled project slots.

**Agent file = the role.** `<role>.md` is the job (system prompt), and `.claude/agents/` is now the source side of it. Do not add a duplicate skill per worker: one consumer plus an agent body that already loads is a wrapper, not a skill. Phase playbooks are hire notes for the **main session**; briefs in `briefs.md` are extra payload per dispatch. "Sub-agents start empty" is **false** — `CLAUDE.md` and project rules load for every worker; what does not travel is the path-scoped `.claude/rules/*.md`, and that is the only thing a brief must restate inline.

**Codex is dual-mode and additive.** `scripts/generate-runtimes.py` renders
`.codex/agents/*.toml` from the Claude role sources for native Codex dispatch;
every generated worker disables its own agent tools. Claude/Orca-dispatched
Codex workers still rely on their self-contained brief and do not need the
coordinator adapter. A primary Codex session loads
`.agents/skills/codex-orchestrator/` only after the user explicitly selects
Codex as the Orchestra coordinator. Project hooks in `.codex/hooks.json` must
be reviewed and trusted on each host; static tests prove their payload logic,
not that a local or cloud host enabled them.

**Steward**: the **janitor** checks headings, prunes memory, and surfaces `.orchestra/hook-failures.log`. Charter hygiene is still that role — not a separate agent. (`pr-reviewer` is the inclusive pre-merge review, not a charter steward.) The orchestrator commits the janitor's draft at batch close.
