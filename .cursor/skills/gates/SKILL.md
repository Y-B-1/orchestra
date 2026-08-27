---
name: gates
description: Verification policy — one always-on fast set (lint, typecheck, scoped unit, smoke core, framework doctor, scoped e2e on flow changes), mechanical scope widening, flake quarantine, and a detached user-triggered full suite. Routing: flow.json gates.fast and fullsuite.run.
---

# Gates

Three sets. The gatekeeper executes and reports (brief: `briefs.md#gatekeeper`); **you derive and approve every command list** — scoping is never the gatekeeper's guess, and commands come from the recon's verified tooling list.

| Set | When | Contents |
|---|---|---|
| **Fast** | every wave close; the merge requirement | lint + typecheck + scoped unit + smoke core + framework doctor (e.g. React Doctor on React repos) + scoped e2e when a user-facing flow changed (isolated port) |
| **Re-proof** | reviewer flags implausible evidence | that one ticket's done_when, nothing else |
| **Full** | ONLY user-triggered (or scheduled, if the user sets that up) | whole codebase, on main, quiet worktree or Cursor cloud agent — never on the critical path, never blocking a PR |

## Rules

- **Mechanical widening, not judgment**: a diff touching dependency manifests, build/tsconfig, migrations/schema, shared types/tokens, or auth middleware widens the scoped set. This list lives in your derivation step.
- **Record every report into `.orchestra/state.json` keyed by commit hash.** The hook denies protected-branch pushes while the recorded green hash ≠ HEAD.
- **Voiding is mechanical**: `git diff --stat <green-hash>..HEAD -- ':!docs' ':!*.md'` non-empty = void, re-run; docs/memory-only commits do not void. No judgment allowed either direction.
- **FLAKY = quarantine, not a question**: first occurrence → ship allowed, flake ticketed and quarantined in state.json; second occurrence of the same flake → mandatory fix ticket before that surface merges again. Never loop-until-green; never ask the user per flake after the first.
- Full-suite failures become intake items (bug lane), prioritized with the user — the run itself never blocks anything.
