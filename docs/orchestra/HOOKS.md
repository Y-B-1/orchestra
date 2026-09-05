# Orchestra hooks — what to install, what to keep, what not to add

Orchestra ships **Cursor hooks** and **Claude adapters**. That is the OS.
Everything else is a **host rail**. Install merges; it never deletes host hooks.

## Orchestra must install (the OS)

| Event | Script | Job |
|---|---|---|
| `beforeShellExecution` | `block-dangerous.py` | Deny force-push / stash / rebase / hard-reset / bulk discard. Never returns ask. Protected landings and declared deploys **allow** only with pr-reviewer CLEAN + matching `gates.last_green_hash` (including headless); otherwise **deny**. Deny protected landings while `gates.last_green_hash` ≠ HEAD unless `server_side_gate` is true. Speaks `git`, `gh`, `az repos`, `glab`. |
| `subagentStart` | `block-nested-subagents.py` | Deny nested Task spawns (`subagent_id` + `parent_conversation_id`). Fan-out is orchestrator-owned. |
| `sessionStart` | `session-start.py` → `heal-orchestra-docs.py` | Heal missing charter/memory headings; keep `AGENTS.md` → project `CLAUDE.md` (never `~/.claude/CLAUDE.md`); seed `state.json` from the example; surface `hook-failures.log`. Never overwrite filled host slots. |

Claude Code (same jobs, different payload): `.claude/hooks/block-dangerous.py` (PreToolUse Bash), `orchestra-block-nested.py` (PreToolUse Agent — deny when `agent_type` is set), `orchestra-session-start.py` (heal + point at the orchestrator skill). Install upserts those into `.claude/settings.json` and never wipes host Claude hooks.

The UPSTREAM package's `install.sh` (Y-B-1/orchestra — not present on this hand-configured host) copies the Cursor scripts (`ORCHESTRA_HOOKS`) and **upserts** those commands in `.cursor/hooks.json` by basename. Host entries with other basenames stay — **except** `block-pr-merge.sh`, which the installer **strips**. Cursor never-merge is incompatible with ralph / pr-reviewer CLEAN land.

`failClosed: true` on the two guardrails. Payload surprises inside a script fail-open and append `.orchestra/hook-failures.log`.

## Orchestra must not ship

Do **not** add these to the package. They are product or Claude-harness policy:

- Dev-server port locks (e.g. a host's `guard-port-4173`)
- `git add` path discipline (`guard-git-add` — never `-A`)
- MCP `apply_migration` deny
- “Cursor never merges” / session YOLO env bypasses (installer **strips** `block-pr-merge.sh`; do not re-add it)
- Claude `Stop` prompt hooks, `.claude/.bypass-guards`

If a host needs any of those, they stay as **host rails** next to Orchestra, not inside the package.


## Host rails — keep when they already exist

On install into a living repo, **keep** host hooks that encode product physics:

- Occupied ports, live-DB migrators, SPA fallback rules
- Staging discipline (`git add <path>`)
- Memory-stale / branch-size **warnings** (warn, don’t deny)
- Path-scoped `.cursor/rules` generated from the host’s own sources

## Conflicts to resolve in chat, not by deleting the host

Two policies can both fire. Name the conflict; pick one; put the winner in `.orchestra/delivery.json` and the host `AGENTS.md` **Project rails**. Do not silently drop either hook — **except** the Cursor never-merge rail, which install strips.

| Host | Orchestra | Resolve |
|---|---|---|
| Pushes to `main` are the deploy trigger (a common host policy) | Protected-branch push **denies** without CLEAN+fresh (or on stale gate hash) | `main` stays on `protected_branches`. Land via PR, or push `main` only with CLEAN+fresh. Overnight land is a CLEAN push, not an unprotected working line. |
| ~~Cursor **never merges**~~ — **lifted** | Releaser **does** merge and deploy after pr-reviewer CLEAN | Installer strips `block-pr-merge.sh`. CLEAN + matching `last_green_hash` is merge and deploy authorization (hook allows, including headless). Full e2e is not in the chain. |
| `block-dangerous-git.sh` (Claude payload, no stash in the snippet; pushes allowed) | `block-dangerous.py` (Cursor payload; stash/rebase deny; protected land/deploy deny unless CLEAN+fresh) | Keep **both** only if they don’t contradict. Prefer Orchestra’s Python hook for Cursor sessions; leave the Claude script for Claude Code. Same folder can host both runtimes. |

## The orchestrator seat

**Claude Code and Codex are the only orchestrator runtimes.** Cursor and OpenCode are
worker runtimes: they take a dispatched brief and execute it, and are never offered the
routing graph. The package ships no `.cursor/skills/orchestrator/`, no
`orchestra-router.mdc`, and no OpenCode orchestrator; `sync-agent-config.py --check`
arm 13 fails if any of them reappears. Codex gets its own seat through
`.agents/skills/codex-orchestrator` plus `.codex/hooks.json`.

## Multi-runtime (Cursor + Claude + Codex + OpenCode) in one folder

Allowed. Cursor reads `.cursor/hooks.json`; Claude Code reads `.claude/settings.json`. Orchestra’s installer does not touch `.claude/`. Do not delete `.claude/` to “make it Cursor-only” — the host's path rules and several Cursor hooks **are wrappers around** `.claude/hooks/`.

## After Cursor updates

Re-sync from the Claude sources (`scripts/generate-runtimes.py`; upstream hosts re-run `install.sh`). Hook payload schemas change. Check `.orchestra/hook-failures.log`.
