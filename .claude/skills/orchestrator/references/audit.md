# Audit

Two fresh auditors in parallel, one axis each (brief: `briefs.md#auditor`). Not every run needs it: a single-ticket run's reviewer already saw the whole diff — audit adds value only when no single reviewer did, when the user asks, or as a standalone review.

**Boundary.** The **auditor** is the two-axis check (Standards vs Spec, reports never merged). The **pr-reviewer** (`review.pr`, after the fast gate) is the inclusive whole-PR / whole-branch artifact — walkthrough, severities, merge recommendation. pr-reviewer does not replace this two-axis audit; the auditor does not replace the inclusive PR review. Single-ticket runs still skip this audit (`audit.decide` → `release.merge`) after `review.pr` is CLEAN.

## Preparation (yours)

1. Pin the fixed point: `git rev-parse <base>`; fail early on a bad ref or empty diff. Diff: `git diff <fixed-point>...HEAD` — pasted when small, passed as the pinned command + file list when large.
2. Standards axis gets the repo's standards files; Spec axis gets the originating spec (from `docs/specs/`, the PR/issue, or the user).
3. Ledger axis fires at `plan.pickup` (resuming a run, verify what the ledger already claims before
   trusting it) and at `audit.run` for a founder-group close — brief it with the ledger pasted plus a
   read-only tree, never a writable one.

## Consuming the verdicts

- Present both reports **verbatim** under `## Standards` / `## Spec`, each with its worst-issue line. Never merge or re-rank across axes.
- Verify each finding yourself; real ones route to builders as findings rounds; spec-contradicting ones go to the user; re-audit the touched surface after fixes.
- CLAIMED-NOT-FOUND rows reopen the ledger row; never flip it back silently.
- **Standalone review**: present the reports and stop — no gates, no release, no push.
- Chain run: audit residuals do not block the **merge** (fast-gate green is the merge requirement). For change-sets where the audit fires (2+ tickets, or on request), the **spec axis must be green before a production deploy and before declaring the run DONE** — an unimplemented requirement has no test to catch it. Single-ticket runs rely on their reviewer's spec-match check instead.
