---
name: build-wave
description: How to brief and dispatch builder sub-agents — one fresh builder per ticket, self-contained brief, worktree assignment, TDD contract, evidence requirements.
---

# Using the builder

One ticket, one fresh builder. Never resume a builder across tickets; never give one builder two tickets.

## Brief template (paste, completely filled — no placeholders)

```
TICKET: <id + title>
GOAL: <2-3 sentences>
TREE: <main tree | worktree path> — never leave it. BRANCH: <name>.
FILES YOU OWN (touch nothing else; unlisted-but-needed = report BLOCKED):
- <file> ...
TEST FIRST: write <test description> in <file>; run it; watch it fail for the
right reason before implementing.
DONE WHEN: `<command>` exits 0 <+ guards, e.g. "without reducing coverage">.
SCOPED VERIFICATION: <commands>.
CONVENTIONS: <from scout — naming, test style, one example each>.
PATH RULES THAT GOVERN YOUR FILES (harvested by the plan's scout — paste them):
<relevant .cursor/rules + AGENTS.md excerpts for the owned paths, verbatim>
RULES (restated because you have no other context): minimum code that solves
the ticket; every changed line traces to it; no drive-by refactors; match
surrounding style; assert behavior never the mock; no git stash/push/merge/
history rewrites; never spawn sub-agents; commit on your branch referencing
the ticket; report evidence as `cmd > /tmp/out.log 2>&1; echo exit:$?` — never
pipe a gate through grep/tail; a visual change needs screenshots in both light
and dark themes. Terminal states: DONE (with evidence) or BLOCKED (with reason).
```

## Dispatch rules

- Independent tickets → parallel builders, each in its **own worktree** (2+ concurrent editors rule); prove each worktree's toolchain before dispatch.
- Ledger "running" only after the dispatch returns an id.
- Findings loop: rounds 1–3 resume this builder (`Resume agent <id>`; if resume is unavailable, a fresh builder with the findings history counts as the round); round 4 dispatch `builder-max` with the full findings history; round 5 adjudicate/park/BLOCKED.
