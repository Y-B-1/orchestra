# Orchestra hooks — what to install, what to keep, what not to add

Orchestra ships **four scripts** and **three hook events**. That is the OS.
Everything else is a **host rail**. Install merges; it never deletes host hooks.

## Orchestra must install (the OS)

| Event | Script | Job |
|---|---|---|
| `beforeShellExecution` | `block-dangerous.py` | Deny force-push / stash / rebase / hard-reset / bulk discard. Ask (local) or deny (headless) on protected landings and declared deploys. Deny protected landings while `gates.last_green_hash` ≠ HEAD unless `server_side_gate` is true. Speaks `git`, `gh`, `az repos`, `glab`. |
| `subagentStart` | `block-nested-subagents.py` | Deny nested Task spawns (`subagent_id` + `parent_conversation_id`). Fan-out is orchestrator-owned. |
| `sessionStart` | `session-start.py` → `heal-orchestra-docs.py` | Heal missing charter/memory headings; seed `state.json` from the example; surface `hook-failures.log`. Never overwrite filled host slots. |

`install.sh` copies exactly those files (`ORCHESTRA_HOOKS`) and **upserts** those commands in `.cursor/hooks.json` by basename. Host entries with other basenames stay.

`failClosed: true` on the two guardrails. Payload surprises inside a script fail-open and append `.orchestra/hook-failures.log`.

## Orchestra must not ship

Do **not** add these to the package. They are product or Claude-harness policy:

- Port locks (Equiti `guard-port-4173`)
- `git add` path discipline (`guard-git-add` — never `-A`)
- MCP `apply_migration` deny
- “Cursor never merges” / YOLO bypass / `CHARGE_YOLO`
- Claude `Stop` prompt hooks, `.claude/.bypass-guards`
- A second destructive-git script that uses Claude’s `tool_input.command` JSON (Orchestra’s hook reads Cursor `command`)

If a host needs any of those, they stay as **host rails** next to Orchestra, not inside the package.

## Host rails — keep when they already exist

On install into a living repo, **keep** host hooks that encode product physics:

- Occupied ports, live-DB migrators, SPA fallback rules
- Staging discipline (`git add <path>`)
- Memory-stale / branch-size **warnings** (warn, don’t deny)
- Path-scoped `.cursor/rules` generated from the host’s own sources

## Conflicts to resolve in chat, not by deleting the host

Two policies can both fire. Name the conflict; pick one; put the winner in `.orchestra/delivery.json` and the host `AGENTS.md` **Project rails**. Do not silently drop either hook.

| Host (Equiti Hub today) | Orchestra | Resolve |
|---|---|---|
| Pushes to `azure-migration` are **unblocked** (push *is* the deploy trigger) | Protected-branch push **asks** / **denies** on stale gate hash | Prefer Orchestra’s hash check **or** set `server_side_gate: true` if Azure Pipelines already is the gate of record. Do not run both “always allow push” and “deny stale hash” as if they agreed. |
| Cursor **never merges** (`block-pr-merge.sh`) | Releaser **does** merge via `az repos` / `gh` | Keep the host deny if humans merge; or remove it when Orchestra’s releaser is the lander. One lander. |
| `block-dangerous-git.sh` (Claude payload, no stash in the snippet; pushes allowed) | `block-dangerous.py` (Cursor payload; stash/rebase deny; protected ask) | Keep **both** only if they don’t contradict. Prefer Orchestra’s Python hook for Cursor sessions; leave the Claude script for Claude Code. Same folder can host both runtimes. |

## Dual runtime (Cursor + Claude) in one folder

Allowed. Cursor reads `.cursor/hooks.json`; Claude Code reads `.claude/settings.json`. Orchestra’s installer does not touch `.claude/`. Do not delete `.claude/` to “make it Cursor-only” — Equiti’s path rules and several Cursor hooks **are wrappers around** `.claude/hooks/`.

## After Cursor updates

Re-run `install.sh`. Hook payload schemas change. Check `.orchestra/hook-failures.log`.
