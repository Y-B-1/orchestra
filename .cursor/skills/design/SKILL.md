---
name: design
description: Main session only. Workers never load this. Turn an idea into an approved spec — recon, approaches, architect, red-team spot-check, explicit approval. Routing: flow.json design.* states.
disable-model-invocation: true
---

# Design

Goal: an approved spec at `docs/specs/YYYY-MM-DD-<topic>-design.md`, committed. You run the conversation; the architect drafts the artifacts. Hard gate: **no product code until the user approves the design** (a throwaway prototype on a clearly-marked disposable branch is not product code).

## Mechanics

1. **Recon before questions** (scout; never ask the user what the codebase can answer). Decompose multi-subsystem requests first.
2. **Frontier rounds**: all questions whose prerequisites are settled, in one round, numbered, each with a recommended answer:
   - ❓ Q1: <question> — ➡️ Recommended: <answer, one-line why>
   Never two questions in one round where one depends on the other. Facts route to scout/researcher (non-blocking); decisions wait for the user. **Record every ruling verbatim at the moment it is made.**
3. **Diverge, then converge.**
   - **Brainstorm first** whenever the space is not already open — a new feature, an unfamiliar problem, or the user arriving with a single idea. Dispatch `architect:brainstorm`: 6–10 genuinely distinct options, unfiltered, including one that reuses what exists, one that costs far less code, one that removes a requirement instead of building, and one deliberately bold. Present the list before narrowing; judging during divergence is how the good option dies. Skip only when the approach is genuinely settled — and say that you skipped it.
   - **Then approaches**: 2–3 with real trade-offs, ONE recommendation. Success signals: one approach surprises the user; one is rejected for a stated reason. Hard-to-reverse interfaces get design-it-twice (architect sketches + judge). Questions only running code answers get a prototype (disposable branch, one command, no polish; harvest, record the ruling, keep the branch as the primary source).
3b. **Sharpen the vocabulary.** Every design surfaces terms. Challenge fuzzy or overloaded ones against `CONTEXT.md` (glossary only — no implementation detail), stress-test each with a concrete scenario ("what exactly is a *session* when the user has two tabs?"), and cross-check against how the code already names things. Rule on the term with the user, then write it to CONTEXT.md inline. Two names for one concept, or one name for two, is a defect you fix here — not in review. A decision that is hard to reverse AND surprising AND a real trade-off also earns a short ADR; nothing else does.

3c. **Judge designs on depth, not taste.** Compare options with the deep-module vocabulary (defined in `architect.md`): depth (functionality behind the interface ÷ interface size), locality (does a typical change land in one place?), seam placement, and the deletion test (if this module vanished, does its complexity disappear or just move to callers?). An abstraction with one hypothetical implementation is speculative; two real ones justify the seam. Record the seams the tests will assert at — the plan's tickets inherit them.

4. **Spec drafting**: architect (brief: `briefs.md#architect`) for designs with 3+ rulings or multiple approaches — diff its Rulings section against your record on return; smaller designs you draft inline and say so, with the same self-review (placeholders, contradictions, dual-readable lines, scope creep). Record which seams tests will assert at — the plan inherits them. Vocabulary sharpened into `CONTEXT.md` (glossary only); an ADR only when hard-to-reverse AND surprising AND a real trade-off.
5. **Gate**: red-teamer requirements spot-check (@L1) against the rulings, then present the spec in sections and confirm each. Approval is explicit, never inferred. **Commit the approved spec.** Industry-standard/post-cutoff dependencies queue the researcher for the plan phase.

Design ends by entering the plan phase — a design that stops without handing off is unfinished.
