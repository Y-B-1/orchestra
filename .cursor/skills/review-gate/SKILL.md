---
name: review-gate
description: How to brief the per-ticket reviewer — fresh eyes on one builder's diff versus its ticket, immediately after every ticket, before the ledger marks it complete.
---

# Using the reviewer

Every ticket gets a fresh reviewer the moment its builder reports DONE. No ticket enters the ledger as complete without a reviewer PASS. The builder's own report is never evidence.

## Brief template

```
Review ONE ticket's diff against its ticket. You did not write it.
--- TICKET (spec, files owned, done_when) --- ...
--- DIFF --- <paste or name the exact git range>
--- BUILDER'S CLAIMED EVIDENCE --- ...
Check in order: spec match (quote ticket lines for gaps); test honesty (would
it have failed before? does it assert behavior, not the mock?); evidence honesty
(real command from this repo, pipe-free capture, test names match the diff — you
are read-only, do not re-run; implausible evidence is a finding); ownership
(files outside the list); surgery (lines not traceable to the ticket); style match.
Do not fix anything. Placeholder reviews are defects — cite specific hunks.
A finding contradicting the ticket/plan: mark "ESCALATE: contradicts plan".
Verdict: PASS or FINDINGS (ranked). Under 400 words.
```

## Consuming the verdict

- FINDINGS → the bounded loop (same builder ×3 → builder-max → adjudicate).
- Implausible-evidence finding → dispatch gatekeeper tier 0 (that ticket's done_when only) for an honest re-proof before deciding.
- ESCALATE → the user, verbatim, with your recommendation.
- PASS → ledger complete with both the builder evidence and the review verdict recorded.
