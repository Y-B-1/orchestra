# Orchestra Roster for Cursor

A complete multi-agent operating system for Cursor: nine named sub-agent roles, thirteen skills, a machine-readable if/then routing graph, git guardrail hooks, and an orchestrator constitution — a translation of the charge chain (design → plan → execute → audit → gates → release → cleanup) into Cursor's native mechanisms.

## What's in the box

```
AGENTS.md                          Orchestrator constitution (main session; copy to project root)
.cursor/
  agents/                          Nine sub-agent personas (clean-context system prompts)
    scout.md  researcher.md  red-teamer.md  builder.md  reviewer.md
    auditor.md  gatekeeper.md  janitor.md  releaser.md
  skills/                          Callable processes (/name in Cursor)
    orchestrator/  SKILL.md + flow.json   ← the normative if/then routing graph
    design/  plan/  execute/              ← the chain phases
    scout-recon/  research/  red-team/  build-wave/  review-gate/
    audit/  gates/  cleanup/  release/    ← per-role briefing cards
  rules/orchestra-router.mdc       alwaysApply rule — makes the router mandatory in every session
  hooks.json + hooks/              beforeShellExecution git guardrails
docs/flow.html                     Human-readable visualization of flow.json
```

## Why each layer exists (Cursor mechanics)

- **`.cursor/agents/*.md`** — Cursor sub-agents. Frontmatter (`name`, `description`, `model`, `readonly`, `is_background`); the body is the sub-agent's entire system prompt. Sub-agents start with a **clean context**: no chat history, and rule/AGENTS.md inheritance is undocumented — so every rule a role must obey is written into its own file AND restated in the brief the orchestrator pastes at dispatch. Sub-agents cannot spawn sub-agents (one nesting level) and cannot talk to the user — which is why the orchestrator is the main session, not an agent file.
- **`.cursor/skills/*/SKILL.md`** — invoked automatically by description relevance or explicitly via `/name`. The chain skills carry the process; the role skills carry the exact brief template to paste at dispatch.
- **`flow.json`** — the normative router. States, `if/then` routes, named dispatches, and global invariants. The orchestrator SKILL.md declares it law; the always-apply rule makes consulting it mandatory.
- **`.cursor/rules/orchestra-router.mdc`** — `alwaysApply: true` injects the routing mandate into every main-session context. This is the only Cursor mechanism that guarantees presence on every prompt; hooks observe and block, but cannot inject instructions into the model.
- **`hooks.json`** — deterministic guardrails: blocks force-push, hard reset, clean, stash (repo-wide danger with worktrees), rebase/amend, bulk discards. Deny-by-hook beats deny-by-prompt.
- **`AGENTS.md`** — the constitution Cursor loads for the main session: roster table, role vocabulary (advisor/judge/reviewer/auditor/critic), the ten iron rules, model routing, memory homes. Capped at 120 lines.

## Install into a project

```bash
cp -R <this-repo>/.cursor <project>/ && cp <this-repo>/AGENTS.md <project>/AGENTS.md
chmod +x <project>/.cursor/hooks/block-dangerous-git.sh
```

If the project already has an AGENTS.md, merge the roster section in rather than overwriting. User-level install (all projects): agents can also live in `~/.cursor/agents/`, skills in `~/.cursor/skills/` — but keep `flow.json`, rules, and hooks per-project so repos can diverge.

## Worktree policy (decided, with reasons)

Worktrees are used **only when 2+ builders edit concurrently** — one shared tree means one shared git index, and no staging discipline fixes that. A lone builder works in the main tree: a worktree there costs a checkout, a dependency install, and a toolchain proof, and buys nothing. Cursor's native per-agent worktrees satisfy the same rule; either way the orchestrator creates them, proves the toolchain in each before dispatch, and removes them in the wave-closing turn after the janitor's directory inspection (never trusting "branch merged"). `git stash` is banned repo-wide while worktrees exist — the hook enforces it.

## Role vocabulary

| Term | Meaning here |
|---|---|
| Advisor | Red-teamer consulted before a decision |
| Judge | Red-teamer with a comparison brief, picks between finished alternatives |
| Reviewer | Per-ticket diff-vs-ticket check during execution |
| Auditor | Whole-change-set review (Standards axis + Spec axis) after execution |
| Critic | Same as auditor — do not coin new role names |

## Memory

One `docs/AGENT-MEMORY.md` per project, owned by the orchestrator, updated and pruned in the batch-closing commit (janitor drafts, orchestrator commits). Sub-agents keep no memory — they are fresh by design; anything durable they learn travels through the janitor's draft.
