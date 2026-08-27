---
name: design
description: Turn an idea into an approved spec through recon, frontier-round questions, competing approaches, and a self-reviewed spec. Use for any non-trivial feature or change before any code is written. Hard gate — no product code until the user approves the design.
---

# Design

Goal: an approved spec at `docs/specs/YYYY-MM-DD-<topic>-design.md`. You (the orchestrator) run this phase yourself because it is a conversation — sub-agents cannot talk to the user.

## Process

1. **Recon before questions.** Dispatch `/scout-recon` for everything the codebase can answer; never ask the user those. Multi-subsystem requests: decompose first, recon each part.
2. **Frontier rounds.** Ask every question whose prerequisites are settled, all at once, numbered, each with your recommended answer:
   - ❓ Q1: <question> — ➡️ Recommended: <answer, one-line why>
   Never put two questions in one round where one depends on the other's answer. FACTS you can look up go to a scout/researcher (non-blocking); DECISIONS wait for the user.
3. **Record rulings verbatim.** Every user decision goes into the spec word-for-word, in a "Rulings" section. Do not paraphrase.
4. **Propose 2–3 approaches** with real trade-offs and exactly one recommendation. Success signal: at least one approach surprises the user, and one is rejected for a stated reason. If all approaches are obvious, you have not explored the space.
5. **Design-it-twice for hard interfaces.** For a module interface that is hard to reverse, dispatch 2–3 parallel red-teamers with the Judge lens brief off radically different sketches; compare on depth, locality, seam placement. Record in the spec **which seams the tests will assert at** — the plan's tickets inherit them.
5b. **Prototype detour.** A question only running code can answer (does this library handle X? how does this interaction feel?) gets a throwaway prototype: disposable branch, clearly marked, no polish, no persistence, one command to run. Harvest the answer, record the ruling, keep the branch as the primary source.
6. **Vocabulary.** New or fuzzy domain terms get sharpened and written to `CONTEXT.md` (glossary only). A decision that is hard to reverse AND surprising AND a real trade-off gets a short ADR; otherwise no ADR.
7. **External standards.** If the design leans on an industry standard or unknown API, queue `/research` — the plan phase consumes it.
8. **Write the spec**, then **self-review before showing it**: hunt placeholders, contradictions, requirements readable two ways, and scope creep. Fix what you find.
9. **User review gate.** Present the spec in sections, confirm each. Approval must be explicit.
10. **Commit the approved spec** before moving on — it is the contract every later phase cites.
11. **Terminal state: invoke `/plan`.** Design that ends without handing off is unfinished.

## Guard

If you catch yourself writing product code or scaffolding during this phase, stop — that is the one hard gate. A small change gets a two-sentence design, never a bypass.
