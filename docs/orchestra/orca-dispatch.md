# Orca dispatch contract — how the coordinator uses Orca

SCOPE: applies when the orchestrator runs inside an Orca terminal (check: `orca status --json`
returns runtimeReachable true). It replaces ONLY the dispatch layer — Claude sub-agents become
Orca workers. Everything else (roles, briefs, rulings, ledger, gates policy, memory files,
CLAUDE.md law) is unchanged and still binding.

## Setup, once per feature
1. `orca orchestration run-create --objective "<feature>" --json` — binds this terminal as coordinator.
2. Tickets → tasks: `orca orchestration task-create --spec "<ticket id + one-line goal>" --deps '["<task_id>"...]' --json`.
   Specs are pointers; the full self-contained brief travels at dispatch. Keep dep chains ≤3–4.

## Dispatch, per ticket
`orca orchestration worker-start --task <id> --worktree current|new-child --agent <claude|codex|cursor|opencode> --model <id> --effort <level> --json`
- Model/effort per role: docs/orchestra/orca-model-matrix.md (chains + floors; fallback on the
  limit signatures in orca-runtimes.json — follow the chain verbatim, no rank re-derivation).
- **Worktree grouping (user ruling 2026-09-02, after an OOM at 16 one-ticket worktrees): ONE worktree
  per WAVE (or per plan's concurrent slice), never one per ticket.** All of a wave's builders dispatch
  into that shared worktree via `--worktree path:<wave-worktree>`; the collision map's file-disjointness
  is what makes this safe. Each worktree costs ~1–2 GB (node_modules + caches) — the machine budget is
  ~4–6 live worktrees, NOT 4–6 live agents; parallelism stays maximal, worktrees do not. Commits in a
  shared worktree: builders commit ONLY their exclusive paths (`git commit -F <msg> -- <paths>`), or
  leave work uncommitted for the coordinator's per-ticket wave-close commits. New-child per TICKET is
  reserved for a genuine checkout conflict (e.g. resuming a preserved branch like wt/g2-2).
- **Worktree death is a RELEASE-TIME duty, not batch close:** when the last worker in a worktree is
  released, the coordinator inspects the DIRECTORY (never refs) in that same turn — harvest/commit any
  work, then `git worktree remove`. The janitor's batch-close sweep is the backstop, not the mechanism.
- The brief: worker-start injects the spec + Orca preamble; send the full role brief with
  `orca orchestration send --type dispatch --to dispatch:<id> --body "<brief>"` if it exceeds the spec.

## Waiting and results
- `orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 900000 --json`
  Keepalives arrive on STDERR — never pipe stderr into a JSON parser. Timeout with count:0 is a
  checkpoint, not a failure. Ack every delivery: `check --ack <delivery_id> --wait`.
- A valid `worker_done` (with --outcome, --files-modified) auto-completes the task — do NOT
  task-update after it. Paste its body into the ledger as the LEDGER trailer line.
- Worker questions arrive as `question` → answer with `reply --id <msg_id> --body <answer>`. Never re-ask.

## After each worker_done, before acking — pick one
- Reuse: `worker-start --task <next> --terminal <handle>` (same terminal, next ticket).
- Release: `worker-release --dispatch <id>` (keeps output inspectable; NEVER `terminal close` a worker).
- Retain: `worker-retain --dispatch <id>` only when the user asked to debug.
Findings loop: rounds 1–3 reuse the same terminal; round 4 = `worker-start --retry-of <dispatch_id>`
with the builder-max row of the matrix; Orca circuit-breaks a task after 3 failed dispatches — that
IS the round cap, respect it.

## Gates and approvals
- DAG decisions: `gate-create --task <id> --question ...` / `gate-resolve --id ... --resolution ...`.
- Gates are coordinator-resolved — a HUMAN approval still means: surface NEEDS-APPROVAL in chat,
  wait for the user's words, then resolve quoting them. Orca has no human-approval UI; the chat is it.
- Approval boundaries, gate evidence, and gate-freshness stay governed by the repo's existing rules
  and hooks — Orca does not know about them.

## Inspection and recovery
`worker-list` (resource accounting) · `worker-read --dispatch <id> --limit 50` (provable transcript)
· `worker-show` · stale handles happen across runtime restarts: re-list, never dual-send ·
`worker-stop` fences + closes; `worker-abandon` fences only.

## Hard don'ts
No nested workers (depth 1). No `task-create`/`--inject`/`check --wait` for full-handoff work the
user phrased as "hand off". No `--dangerously-skip-permissions` — Orca panes are interactive; the
ask-tier is the floor. Usage before waves: `orca account list --json` (session/weekly/fableWeekly).

