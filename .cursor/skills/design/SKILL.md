---
name: design
description: Turn an idea into an approved, committed spec — recon, frontier rounds, competing approaches, architect-drafted spec, red-team spot-check, explicit user approval. Use for any full-chain feature before any code. Routing: flow.json design.* states.
---

# Design

Goal: an approved spec at `docs/specs/YYYY-MM-DD-<topic>-design.md`, committed. You run the conversation; the architect drafts the artifacts. Hard gate: **no product code until the user approves the design** (a throwaway prototype on a clearly-marked disposable branch is not product code).

## Mechanics

1. **Recon before questions** (scout; never ask the user what the codebase can answer). Decompose multi-subsystem requests first.
2. **Frontier rounds**: all questions whose prerequisites are settled, in one round, numbered, each with a recommended answer:
   - ❓ Q1: <question> — ➡️ Recommended: <answer, one-line why>
   Never two questions in one round where one depends on the other. Facts route to scout/researcher (non-blocking); decisions wait for the user. **Record every ruling verbatim at the moment it is made.**
3. **Approaches**: 2–3 with real trade-offs, ONE recommendation. Success signals: one approach surprises the user; one is rejected for a stated reason. Hard-to-reverse interfaces get design-it-twice (architect sketches + judge). Questions only running code answers get a prototype (disposable branch, one command, no polish; harvest, record the ruling, keep the branch as the primary source).
4. **Spec drafting**: architect (brief: `briefs.md#architect`) for designs with 3+ rulings or multiple approaches — diff its Rulings section against your record on return; smaller designs you draft inline and say so, with the same self-review (placeholders, contradictions, dual-readable lines, scope creep). Record which seams tests will assert at — the plan inherits them. Vocabulary sharpened into `CONTEXT.md` (glossary only); an ADR only when hard-to-reverse AND surprising AND a real trade-off.
5. **Gate**: red-teamer requirements spot-check (@L1) against the rulings, then present the spec in sections and confirm each. Approval is explicit, never inferred. **Commit the approved spec.** Industry-standard/post-cutoff dependencies queue the researcher for the plan phase.

Design ends by entering the plan phase — a design that stops without handing off is unfinished.
