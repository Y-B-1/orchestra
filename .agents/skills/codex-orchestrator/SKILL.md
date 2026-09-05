---
name: codex-orchestrator
description: Activate only when the user explicitly selects $codex-orchestrator or explicitly asks Codex to be the main Orchestra coordinator. Never activate for ordinary implementation, review, keep-going requests, or a dispatched worker brief.
---

# Codex Orchestra coordinator adapter

This is an opt-in adapter for a **primary Codex session**. It does not replace
the shared Orchestra constitution and it is never a worker preload.

## Identity gate — run this before reading flow or state

Evaluate these checks in order. On the first match, stop this skill without
reading Orchestra state, opening a run, dispatching an agent, or changing a
file.

1. **Dispatched worker.** If `ORCHESTRA_CODEX_WORKER` is set, or the current
   prompt is a ticket/role brief naming a generated role present under
   `.codex/agents/`, execute that brief as a worker. Do not coordinate, route,
   hire, merge, or deploy.
2. **Orca worker.** If `ORCA_WORKTREE_ID` is set and `ORCA_WORKSPACE_ID` is not,
   this is an Orca-dispatched worker. Execute the injected brief and report to
   its coordinator. Do not continue this skill.
3. **No explicit Codex selection.** Continue only when the user's current
   request explicitly says one of the following or an unambiguous equivalent:
   `$codex-orchestrator`, “use Codex as the Orchestra coordinator”, “run
   Orchestra with Codex as the main coordinator”, or “Codex orchestrate this
   through Orchestra”. The existence of this skill, an open run, a multi-file
   request, “keep going”, “finish”, or “run overnight” is not activation.

When a check stops activation, remain an ordinary Codex session or the named
worker. Do not silently fall through to coordinator behavior.

## Coordinator startup — only after the identity gate passes

1. Read `AGENTS.md` and `docs/AGENT-MEMORY.md`.
2. Read the main-session constitution at
   `.claude/skills/orchestrator/SKILL.md`. It remains authoritative; this file
   changes only runtime operations.
3. Acquire the session-scoped Codex coordinator lease before reading or
   changing run state:

   ```sh
   python3 .codex/hooks/coordinator-lease.py acquire --session-id <session-id>
   ```

   Use the session id reported by the Codex `SessionStart` hook. Refusal means
   another coordinator or unreconciled OPEN run owns the repository: stop and
   request a deliberate handoff; never delete, replace, or take over its lease.
4. If `docs/orchestra/STATE.md` records an open run, reconcile its stamp with
   `git rev-parse HEAD`, `git status --porcelain`, and `git worktree list`. The
   tree is truth. Only the active coordinator may repair run state.
5. Read exactly one routing state with:

   ```sh
   python3 .claude/skills/orchestrator/scripts/flow-state.py <state>
   ```

6. Read the matching phase playbook from
   `.claude/skills/orchestrator/references/` and announce every transition as
   required by the shared constitution.

Do not copy or reconstruct `flow.json`, the phase playbooks, or dispatch
templates. Their shared paths are:

- `.claude/skills/orchestrator/references/flow.json`
- `.claude/skills/orchestrator/references/briefs.md`
- `.claude/skills/orchestrator/references/{design,plan,execute,gates,pr-review,audit,release,cleanup,diagnose}.md`
- `.claude/skills/orchestrator/references/STATE.template.md`

## Codex runtime substitutions

Apply only these substitutions while following the shared constitution:

- A Claude `Workflow` dispatch becomes a Codex native subagent dispatch using
  one of the named project agents in `.codex/agents/`.
- Use Codex native wait, message, follow-up, and interrupt operations for that
  child. Do not emulate a handoff by spawning a second child for the same
  ticket.
- Never override a generated agent's model or reasoning effort at dispatch.
  `docs/orchestra/codex-models.json` and the generated TOML own those values.
- Dispatch only roles present in both `.codex/agents/` and
  `docs/orchestra/codex-models.json`. There is no spawned `orchestrator` role.
- Use the runtime capacity the current Codex host actually exposes. The
  project configuration's concurrency value is a ceiling, not a promise of
  available slots.
- Parallelize every unblocked, non-colliding ticket the plan permits. Two or
  more concurrent writers in one clone require separate worktrees, created and
  integrated by this coordinator, never by a worker.
- Before dispatching a writer, create its worktree and put the absolute
  worktree path, branch, and expected HEAD in the brief. The worker's first
  receipt must show `pwd -P`, `git rev-parse --show-toplevel`, and
  `git status --short --branch` matching that assignment. If the current Codex
  client cannot honor an assigned working directory, do not fan out writers;
  serialize them in the coordinator checkout.
- Workers do not spawn children. Their generated definitions disable native
  agents, and every brief restates the depth-one rule.

Everything else is unchanged: rulings custody, fresh eyes, bounded findings,
evidence with direct exit codes, the plan collision map, sole-writer run state,
gate hashes, PR review, CLEAN authorization, release policy, and honest terminal
states all come from the shared constitution and current flow state.

## State, autonomy, and release boundaries

- `docs/orchestra/STATE.md` and `.orchestra/state.json` have one writer: the
  active coordinator. Never run a Codex coordinator beside a live Claude or
  Orca coordinator on the same repository state.
- The Codex lease supplements that shared-state rule; it does not prove a
  non-Codex coordinator is absent, authenticate explicit user intent, or
  replace the sandbox. Keep it for the coordinator's lifetime and release it
  only at a terminal close or an explicit handoff:
  `python3 .codex/hooks/coordinator-lease.py release --session-id <session-id>`.
- If a crash leaves a lease, never delete it automatically. Inspect tracked
  state, process/transcript liveness, and every worktree, then ask the user to
  authorize a deliberate stale-lease recovery or handoff.
- Explicitly selecting this skill does not arm autonomy. Autonomy still
  requires its named invocation and an existing ledger under the shared rules.
- Codex does not wire the Claude autonomy loop as a project-wide `Stop` hook:
  a standalone worker is also a root Codex session, so a generic hook could
  mistake it for the coordinator. Keep an invoked Codex autonomy run inside
  the active coordinator turn until a tested session-scoped coordinator
  identity can guard re-entry.
- A dispatched Codex worker cannot grant itself merge or deploy authority.
- Release requires the delivery declaration, a current green gate hash, and
  fresh `pr-reviewer` CLEAN. The releaser follows the provider-specific path;
  this adapter grants no Azure credential.
- When another live coordinator owns `main`, prepare only an isolated branch
  or draft PR until that coordinator reaches a safe handoff and the branch is
  updated and re-reviewed.

## Cloud use

Before coordinating in Codex Cloud, read `docs/orchestra/codex-cloud.md`.
Cloud setup secrets do not survive into the agent phase. A cloud run may build,
verify, and return a branch or PR, but it must not claim Azure landing or deploy
parity without an observed agent-phase credential design approved for that
purpose.
