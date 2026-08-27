---
name: audit
description: Post-execution two-axis review of the whole change-set — Standards and Spec auditors in parallel, reports never merged. Use after all tickets close, before gates and release; also standalone for "review this branch/PR".
---

# Using the auditors

Two fresh `auditor` sub-agents, dispatched **in parallel in one message**, one axis each. Never merge or re-rank their reports — separation prevents one axis masking the other.

## Preparation (yours)

1. Pin the fixed point: `git rev-parse <base>` — merge-base, branch point, or the commit the user names. Fail early on a bad ref or empty diff.
2. Produce the diff: `git diff <fixed-point>...HEAD`. Paste it into the briefs when small; when large, paste the pinned command and the changed-file list instead and instruct the auditor to run the diff itself, read-only.
3. Collect the material each axis needs — the sub-agents have no other access:
   - Standards axis: the repo's documented standards files, pasted in full.
   - Spec axis: the originating spec (from `docs/specs/`, the PR/issue, or the user), pasted in full.

## Briefs

```
AXIS: STANDARDS. Review this entire diff against the standards below plus your
smell baseline. Cite standard/smell + file + hunk + concrete fix per violation.
Do not fix. End with the worst issue on this axis. CLEAN or ranked findings,
<400 words. --- STANDARDS --- ... --- DIFF --- ...
```
```
AXIS: SPEC. Review this entire diff against the spec below. Report missing
(quote the spec line), partial, wrong-looking (letter vs intent), scope creep.
Do not fix. End with the worst issue on this axis. CLEAN or ranked findings,
<400 words. --- SPEC --- ... --- DIFF --- ...
```

## Consuming the verdicts

- Present both reports to the user **verbatim**, under `## Standards` and `## Spec`, each with its worst-issue line.
- Verify each finding yourself before acting on it; findings route to builders via the findings loop.
- A finding that contradicts the spec goes to the user, not to a builder.
- **Standalone review request** (the user asked only for a review; no execution phase ran): present the two reports and stop — terminal state, no gates, no release, no push.
- Chain run, both CLEAN (or user accepts residual findings) → proceed to `/gates` tier 3.
