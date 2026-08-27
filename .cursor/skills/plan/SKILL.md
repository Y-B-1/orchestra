---
name: plan
description: Turn an approved spec into a red-teamed, ticketed execution plan with blocking edges, done_when contracts, and file ownership. Use after design approval, before any execution. The plan is not ready until three red-team lenses pass.
---

# Plan

Goal: `docs/plans/YYYY-MM-DD-<feature>.md` — a plan a fresh session can execute without this conversation.

## Phase 1 — Recon (always)

Dispatch `/scout-recon`: map the spec against the codebase. The report names files and symbols (never line numbers), conventions, and the exact verification commands available. Also have the scout harvest the `.cursor/rules` and AGENTS.md excerpts that govern the paths the work will touch — ticket briefs must restate those rules verbatim, and the orchestrator cannot restate what nobody harvested.

## Phase 2 — Research (when triggered)

If design queued research, or any ticket touches a post-cutoff API: dispatch `/research` as a background sub-agent. The plan may not cite model memory for version-sensitive claims — it cites RESEARCH.md.

## Phase 3 — Draft

Structure the work as **tracer-bullet tickets**: each a thin end-to-end slice one fresh builder session can hold. Ship the thinnest full pipe first; widen after it is verified. Every ticket carries:

- **Files owned** — exact list, including sibling files (tests, styles, types). Two tickets never own the same file unless a blocking edge orders them.
- **Test first** — the test that goes RED before implementation, named, asserting at a **seam agreed in the design** (public interface, never internals or mocks).
- **done_when** — a mechanical yes/no command ("`npm test -- auth` exits 0"), plus guards so the letter cannot beat the intent ("without reducing coverage").
- **Scoped verification** — the fast checks and any scoped e2e specs for this ticket.
- **Blocking edges** — which tickets must land first.
- **Model tier** — builder tier per the routing rule.
- **Self-contained brief text** — the ticket body will be pasted verbatim to a builder with clean context; restate every rule the builder must follow inline (see the builder brief template in `/build-wave`).

Steps inside a ticket are bite-sized (2–5 minutes each).

## Phase 4 — Red team (ALWAYS, all three lenses)

Dispatch three `/red-team` sub-agents **in parallel, fresh context, one lens each**:
1. **Requirements** — brief includes the spec + verbatim rulings + the plan.
2. **Feasibility** — brief includes the plan + instructs codebase access; every challenge must name a file/symbol.
3. **Scope** — brief includes the plan + ticket file-ownership table.

The plan is **NOT-READY** until all three return READY. Repair and re-dispatch the failed lens with fresh context. A non-trivial plan that passes all three on the first round means the skeptics failed — tighten the briefs and rerun once.

## Hand-off

Commit the plan (and the spec, if design left it uncommitted) before execution begins — on-disk state is the source of truth, and an uncommitted plan can be lost to any tree operation. Terminal state: invoke `/execute` with the plan path. The plan file, not this conversation, is the source of truth from here.
