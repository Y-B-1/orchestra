---
name: execute
description: Work the ticketed plan — fresh builder and fresh reviewer per ticket, bounded findings loop, worktrees for concurrent waves, orchestrator-owned integration, wave close in the fixed order. Routing: flow.json execute.* states.
---

# Execute

You coordinate and talk to the user; builders build; reviewers review. Briefs come from `briefs.md` — filled completely, since builders have clean context.

## Setup

1. Feature branch + the ledger file `docs/plans/<feature>-ledger.md` (always separate) before the first dispatch. Read repo memory; carry only what the wave needs.
2. **Worktrees for 2+ builders sharing one checkout** — a local session, or sub-agents inside a single cloud VM (one shared tree = one shared git index). Builders that are each their own cloud agent skip this entirely: the VM is the isolation, each pushes its own branch, and integration means fetching those branches. The rule: `git worktree add <repo>/.cursor/worktrees/<ticket> -b <ticket-branch>`. First check you are not already inside one (`git rev-parse --git-dir` ≠ `--git-common-dir`), and keep `.cursor/worktrees/` gitignored. Install dependencies and **prove each toolchain** (run the real test runner once — install output lies) before dispatching; a proof that survives one repair attempt broken collapses the wave to sequential in the main tree. Own ports per tree. Cursor's native per-agent worktrees isolate too, but Cursor may clean them itself — commits on named ticket branches are the only preservation. Never `git stash` while worktrees exist.

## Per ticket

Dispatch → review → findings loop, per flow.json execute.review: rounds 1–3 same builder (resume, or fresh-with-history), round 4 `builder-max`, round 5 you adjudicate. Reviewer-flagged implausible evidence gets a gatekeeper re-proof (that done_when only). Ledger "running" only after a dispatch returns an id; verdicts recorded to the ledger and `.orchestra/state.json`. A builder BLOCKED on a plan defect routes to the planner as an L1 repair while other tickets keep running.

## Wave close — fixed order

1. **Integrate**: merge each reviewed ticket branch into the feature branch yourself, ordered by blocking edges. Conflicts are expected; resolve by preserving both tickets' intent — never `--abort`, never invented behavior; too-entangled conflicts go to a fresh builder with both tickets pasted.
2. **Close the batch**: janitor (worktrees exist or 2+ tickets — brief pastes the ledger excerpt) or your own memory line (tiny batches); rescue-or-remove worktrees; memory draft lands **in this batch-closing commit**. Rewrite `STATE.md` (stamped). First wave of a PR-landing repo: releaser opens the **draft PR** now.
3. **Gate**: the fast set at the post-merge, post-memory HEAD — the hash that ships. Failures fix forward (lone builder, main tree) and re-run without repeating step 1–2's always-batch.

## Interrupts and dead builders

User interrupt: stop dispatching, report ledger state, resume from the ledger — never re-dispatch blind. A dispatch that errors or never returns: check ledger and tree for partial commits, then dispatch fresh. Liveness applies to background agents (state file + mtime at the verified path); foreground dispatches are synchronous.
