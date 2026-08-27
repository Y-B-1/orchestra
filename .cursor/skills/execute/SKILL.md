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
   - 2+ builders editing concurrently → **each gets its own worktree** (one shared tree = one shared git index; staging discipline cannot fix that): `git worktree add <repo>/.cursor/worktrees/<ticket> -b <ticket-branch>`. First check you are not already inside one (`git rev-parse --git-dir` differs from `--git-common-dir` means you are), and make sure `.cursor/worktrees/` is in the repo's `.gitignore`.
   - Cursor's native per-agent worktrees also satisfy isolation, but Cursor may clean them up itself — if you use them, the named ticket branch is the only preservation you control; commits are the rescue, not the directory.
   - **Prove the toolchain** in each fresh worktree before dispatching into it: install dependencies (worktrees share no `node_modules`), then run the actual test runner once (`ls node_modules/.bin/<runner>` then a no-op run) — install output lies. If the proof fails and one repair attempt does not fix it, collapse the wave to sequential builders in the main tree rather than dispatching into a broken tree.
   - Each worktree serves its own ports; never share a dev server.
   - You created it, you remove it — same wave it closes, via `/cleanup` inspection first. Never `git stash` anywhere in the repo while worktrees exist.
3. Read the repo memory file; carry only what this wave needs.

## Per ticket (continuous loop, no idle check-ins)

1. **Dispatch a fresh builder** (`/build-wave` has the brief template). Paste the full ticket: files owned, test-first, done_when, scoped verification, tree assignment, branch, and the builder iron rules restated. Mark "running" in the ledger only after dispatch returns an id.
2. **Per-ticket review gate.** When the builder reports, dispatch a **fresh reviewer** (`/review-gate` template) with the diff + the ticket. The builder's success report is never evidence.
3. **Bounded findings loop:**
   - Rounds 1–3: resume the **same builder** with the findings (Cursor: `Resume agent <id>`; if resume is unavailable, a fresh `builder` given the ticket plus the full findings history counts as the round).
   - Round 4: dispatch **`builder-max`** — the escalation builder at the strongest tier — with ticket + full findings history.
   - Round 5: adjudicate yourself, park the finding in the ledger as a known issue, or mark the ticket BLOCKED.
   - A finding that contradicts the plan or spec goes to the **user**, not into the loop.
4. Record completion + evidence in the ledger; dispatch the next unblocked ticket. Batch independent tickets into parallel waves.

## Wave close — in this order

1. **Integrate.** All reviews PASS → merge each ticket branch into the feature branch yourself, in the main tree, ordered by blocking edges. Conflicts are expected — that is why the tickets were isolated. Resolve each by understanding both tickets' intent and preserving both; never `--abort`, never invent behavior. A conflict too entangled to resolve confidently goes to a fresh builder as a findings round, with both tickets pasted in the brief.
2. **Close the batch.** `/cleanup`: janitor inspects worktree directories (brief must paste the ledger excerpt for this wave — the janitor has no other context); you rescue or remove, and commit the memory draft **in this batch-closing commit** on the feature branch.
3. **Gate.** `/gates` tier 1 (fast, scoped) at the post-merge, post-memory HEAD — this is the hash that ships. Tier 2 (scoped e2e) too if the wave touched user-facing flows. Failures fix forward through the findings loop (a lone builder in the main tree now), then re-run the tier — any commit after a green gate voids it as evidence.

## Interrupts and dead builders

User interrupt: stop dispatching, report ledger state. Foreground dispatches are synchronous; the liveness rule (state file in `~/.cursor/subagents/` + mtime) applies to **background** sub-agents only. A dispatch that errors or never returns: check the ledger and the tree for partial commits first, then dispatch a fresh builder for that ticket — never two builders on one ticket in one tree.

## Close

All tickets DONE/parked with user sign-off → invoke `/audit`.
