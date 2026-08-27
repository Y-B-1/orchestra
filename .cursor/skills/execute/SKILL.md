---
name: execute
description: Work a ticketed plan to completion — fresh builder per ticket, fresh reviewer per ticket, bounded findings loop, worktrees when 2+ builders run concurrently, ledger on disk. Use after a plan passes red team.
---

# Execute

Goal: every ticket DONE with evidence, on a branch ready for audit and gates. You coordinate and talk to the user; builders build; reviewers review. You never build when a builder can.

## Setup

1. Create the feature branch. Create a **ledger** section in the plan file (or `docs/plans/<plan>-ledger.md`): per ticket — status, builder run, review verdict, evidence. State lives on disk, not in chat.
2. **Worktree rule.** Count concurrent builders this wave:
   - 1 builder → main tree. No worktree (cost without benefit).
   - 2+ builders editing concurrently → **each gets its own worktree** (one shared tree = one shared git index; staging discipline cannot fix that). Use Cursor's native per-agent worktrees, or `git worktree add <repo>/.cursor/worktrees/<ticket> -b <ticket-branch>`.
   - **Prove the toolchain** in each fresh worktree before dispatching into it: run the actual test runner once (`ls node_modules/.bin/<runner>` then a no-op run) — install output lies.
   - Each worktree serves its own ports; never share a dev server.
   - You created it, you remove it — same wave it closes, via `/cleanup` inspection first. Never `git stash` anywhere in the repo while worktrees exist.
3. Read the repo memory file; carry only what this wave needs.

## Per ticket (continuous loop, no idle check-ins)

1. **Dispatch a fresh builder** (`/build-wave` has the brief template). Paste the full ticket: files owned, test-first, done_when, scoped verification, tree assignment, branch, and the builder iron rules restated. Mark "running" in the ledger only after dispatch returns an id.
2. **Per-ticket review gate.** When the builder reports, dispatch a **fresh reviewer** (`/review-gate` template) with the diff + the ticket. The builder's success report is never evidence.
3. **Bounded findings loop:**
   - Rounds 1–3: resume the **same builder** with the findings.
   - Round 4: dispatch a **fresh builder one model tier up** with ticket + findings history.
   - Round 5: adjudicate yourself, park the finding in the ledger as a known issue, or mark the ticket BLOCKED.
   - A finding that contradicts the plan or spec goes to the **user**, not into the loop.
4. Record completion + evidence in the ledger; dispatch the next unblocked ticket. Batch independent tickets into parallel waves.

## Wave close

- `/gates` tier 1 (fast, scoped) per wave; fix-forward failures through the findings loop.
- `/cleanup` inspects worktrees; you execute removals and commit the memory draft **in the batch-closing commit**.
- Any commit after a green gate voids it as evidence.

## Interrupts

User interrupt: stop dispatching, report ledger state. Before any status claim about a background builder, verify liveness (state file in `~/.cursor/subagents/` + mtime), then resume — never re-dispatch blind (two builders on one ticket in one tree is corruption).

## Close

All tickets DONE/parked with user sign-off → invoke `/audit`.
