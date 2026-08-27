---
name: diagnose
description: Diagnosis loop for bugs, failing tests, regressions, and performance problems. Build a feedback loop first — that IS the work — then hypothesize, instrument, and fix through a one-ticket execute pass with the regression test written first.
---

# Diagnose

The bug path of the routing graph (`bug.feedback-loop` in flow.json). The discipline: no fix attempt before a reproduction loop exists.

## 1. Build the feedback loop — this is the skill

A loop is a **named command you have already run** that shows the bug red and would show the fix green. Pick the tightest construction that fits, in order of preference: failing test → curl script → CLI diff of outputs → headless browser check → trace replay → bisect harness.

The bar for "loop exists": already run once, red-capable, fast (seconds, not minutes), and deterministic. A non-deterministic bug first gets its reproduction rate raised (tight loop, seeded inputs, forced timing) and the rate stated. A performance bug gets a **measured baseline** (numbers, not vibes) before any change. If no loop is possible, stop and tell the user — guessing at fixes without one wastes everyone's time.

## 2. Minimise

Shrink the reproduction until every remaining element is load-bearing. Each removed element that keeps the bug red narrows where the bug can live.

## 3. Hypothesize

Write 3–5 **ranked, falsifiable** hypotheses and show them to the user (non-blocking — continue working). Each names what evidence would kill it.

## 4. Instrument

One variable at a time. A debugger beats logging; if logging, tag every line (`[DEBUG-<id>]`) so cleanup can find them. Never log-everything — drowning the signal is the classic failure. For performance: measure, then bisect the measurement, never guess.

## 5. Fix — through the normal machinery

The fix is a one-ticket `/execute` pass: the regression test is the ticket's test-first (written at a proper seam — no seam available is itself a finding to report), the loop command is the done_when, a fresh reviewer checks the diff. The bug does not exempt the fix from review.

## 6. Close

Remove every `[DEBUG-]` line, name the winning hypothesis in the commit message, and route to `/audit` if the diff is non-trivial — else terminal with evidence (the loop command, now green, exit code quoted).
