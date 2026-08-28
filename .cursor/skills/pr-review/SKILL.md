---
name: pr-review
description: Main session only. Workers never load this. Inclusive whole-PR review after the fast gate and before merge — hire pr-reviewer. Does not replace CI. Routing: flow.json review.pr.
disable-model-invocation: true
---

# PR review (merge path)

You coordinate; `pr-reviewer` reviews. Brief: `briefs.md#pr-reviewer`.

**When:** `review.pr` — fast gate green, feature complete (full chain) or small-lane close when the repo lands via PRs. Re-enter after a findings fix and a new green fast gate.

**Not:** per-ticket `reviewer` (already ran). Not the two-axis `auditor` (Standards vs Spec, never merged). Not the gatekeeper. Hosted Bugbot/Copilot/CodeRabbit on the remote PR are extra, not a substitute on Azure DevOps / GitLab / plain git.

## Your half

1. Pin the merge-base / PR diff command. Paste a small diff; pass a pinned command + file list when large.
2. Dispatch one `pr-reviewer@L2` (L1 only for tiny small-lane diffs).
3. **BLOCKED** (Critical/Major) → findings loop (same builder if one ticket; else a ticketed fix). Then re-gate and re-review.
4. **CLEAN** or nits-only → continue (`audit.decide` on the full chain; `release.merge` on the small lane when the repo lands via PRs; `terminal.done` on the small lane with no PR flow). Record nits in the ledger; janitor may promote accepted preferences into `docs/AGENT-MEMORY.md`.
5. Nits never block merge. Fast-gate green remains the merge CI requirement.
