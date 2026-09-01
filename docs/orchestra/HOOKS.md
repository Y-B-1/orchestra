# Orchestra hooks — what to install, what to keep, what not to add

Orchestra ships **Cursor hooks** and **Claude adapters**. That is the OS.
Everything else is a **host rail**. Install merges; it never deletes host hooks.

## Orchestra must install (the OS)

| Event | Script | Job |
|---|---|---|
| `beforeShellExecution` | `block-dangerous.py` | Deny force-push / stash / rebase / hard-reset / bulk discard. Never returns ask. Protected landings and declared deploys **allow** only with pr-reviewer CLEAN + matching `gates.last_green_hash` (including headless); otherwise **deny**. Deny protected landings while `gates.last_green_hash` ≠ HEAD unless `server_side_gate` is true. Speaks `git`, `gh`, `az repos`, `glab`. |
| `subagentStart` | `block-nested-subagents.py` | Deny nested Task spawns (`subagent_id` + `parent_conversation_id`). Fan-out is orchestrator-owned. |
| `sessionStart` | `session-start.py` → `heal-orchestra-docs.py` | Heal missing charter/memory headings; keep `AGENTS.md` → project `CLAUDE.md` (never `~/.claude/CLAUDE.md`); seed `state.json` from the example; surface `hook-failures.log`. Never overwrite filled host slots. |

Claude Code hooks, source in `.claude/hooks/` (each with its own `.test.sh`; `.cursor/hooks/heal-orchestra-docs.py` and `.cursor/hooks/block-dangerous.py` are thin shims onto the Claude source, not separate implementations): `block-dangerous.py` (PreToolUse Bash), `orchestra-block-nested.py` (PreToolUse Agent — deny when `agent_type` is set), `orchestra-session-start.py` + `routing-context.md` (heal + inject the Claude orchestrator skill path), `orchestra-block-worker-skill.py` (deny a worker loading the orchestrator skill), `orchestra-worker-context.py` (tell a dispatched worker not to load it), `heal-orchestra-docs.py`. Install upserts those into `.claude/settings.json` and never wipes host Claude hooks. ~~Do **not** add `.claude/skills/orchestrator/`.~~ **Superseded 2026-09-02 (U8).**

`install.sh` copies the Cursor scripts (`ORCHESTRA_HOOKS`) and **upserts** those commands in `.cursor/hooks.json` by basename. Host entries with other basenames stay — **except** `block-pr-merge.sh`, which the installer **strips**. Cursor never-merge is incompatible with ralph / pr-reviewer CLEAN land.

`failClosed: true` on the two guardrails. Payload surprises inside a script fail-open and append `.orchestra/hook-failures.log`.

## Orchestra must not ship

These stay out of the package. They are product or Claude-harness policy:

- Port locks (Equiti `guard-port-4173`)
- `git add` path discipline (`guard-git-add` — never `-A`)
- MCP `apply_migration` deny
- “Cursor never merges” / session YOLO env bypasses (installer **strips** `block-pr-merge.sh`; do not re-add it)
- Claude `Stop` prompt hooks, `.claude/.bypass-guards`
- ~~A second orchestrator skill under `.claude/skills/` (Cursor also loads that directory)~~ **Superseded 2026-09-02 (U8):** `.claude/skills/orchestrator/` is now the source; `.cursor/skills/orchestrator/` is generated from it.

If a host needs any of those, they stay as **host rails** next to Orchestra, not inside the package.

## Host rails — keep when they already exist

On install into a living repo, **keep** host hooks that encode product physics:

- Occupied ports, live-DB migrators, SPA fallback rules
- Staging discipline (`git add <path>`)
- Memory-stale / branch-size **warnings** (warn, don’t deny)
- Path-scoped `.cursor/rules` generated from the host’s own sources

## Conflicts to resolve in chat, not by deleting the host

Two policies can both fire. Name the conflict; pick one; put the winner in `.orchestra/delivery.json` and the host `AGENTS.md` **Project rails**. Do not silently drop either hook — **except** the Cursor never-merge rail, which install strips.

| Host (Equiti Hub today) | Orchestra | Resolve |
|---|---|---|
| Pushes to `azure-migration` are **unblocked** (push *is* the deploy trigger) | Protected-branch push **denies** without CLEAN+fresh (or on stale gate hash) | Keep `azure-migration` **off** Orchestra `protected_branches` so overnight land can push. Protect `main` only. Gate-hash still applies to listed protected names. |
| ~~Cursor **never merges**~~ — **lifted** | Releaser **does** merge and deploy after pr-reviewer CLEAN | Installer strips `block-pr-merge.sh`. CLEAN + matching `last_green_hash` is merge and deploy authorization (hook allows, including headless). Full e2e is not in the chain. |
| `block-dangerous-git.sh` (Claude payload, no stash in the snippet; pushes allowed) | `block-dangerous.py` (Cursor payload; stash/rebase deny; protected land/deploy deny unless CLEAN+fresh) | Keep **both** only if they don’t contradict. Prefer Orchestra’s Python hook for Cursor sessions; leave the Claude script for Claude Code. Same folder can host both runtimes. |

## Dual runtime (Cursor + Claude) in one folder

Allowed. Cursor reads `.cursor/hooks.json`; Claude Code reads `.claude/settings.json`. Orchestra's installer **does** touch `.claude/`: it merges the agent bodies (preserving a host's own `skills:` preloads), copies `.claude/hooks/` + tests, copies the two `.claude/skills/` (`orchestrator`, `orchestra-rails`), then runs `docs/orchestra/sync-agent-config.py` to regenerate every `.cursor/**` mirror. Do not delete `.claude/` to "make it Cursor-only" — several Cursor files are generated from it and a host's own path rules may wrap `.claude/hooks/`.

## After Cursor updates

Re-run `install.sh`. Hook payload schemas change. Check `.orchestra/hook-failures.log`.
