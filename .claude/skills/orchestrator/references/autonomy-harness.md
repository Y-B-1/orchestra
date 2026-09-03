# Autonomy harness — the Orca-adapted ralph loop (2026-09-03)

The outer engine for multi-batch, multi-wave autonomy. In-session
`autonomy.loop` alone dies with its session; this harness makes the loop
survive that. **Main-session/coordinator concern only — never mirrored to
workers** (generate-runtimes.py excludes the orchestrator skill on purpose).

## Why it exists — the four documented killers of full autonomy

1. **Session death.** Planners and coordinators die on the session/usage limit
   mid-run (2026-09-02: seven planners lost; work re-dispatched by hand the
   next day). The loop lived inside one context window with nothing outside it
   to restart it — every "overnight run" ended as a HANDOFF file instead.
2. **Turn-end waits.** A coordinator that ends its turn to "wait" pauses the
   run silently until a human types (2026-09-02: "a herder HARNESS must never
   end its turn to wait — one did and its chain died unseen").
3. **Per-ledger scope.** `autonomy.loop` ended at one plan's ledger; a
   multi-plan backbone (G1–G10) had no driver to open plan N+1 when plan N
   closed. Fixed in flow.json: plan-complete is a wave boundary, not a run end.
4. **Item-level blocks ending the run.** A user-blocked item (G7-class) or a
   gated action stopped everything instead of being parked. Fixed in
   flow.json: park and advance; only nothing-unblocked-anywhere stops the run.

## The mechanism (adapted from Charge `ralph-loop`, not copied)

`scripts/orca-ralph.sh` relaunches a **fresh** coordinator (`claude -p`, model
`claude-fable-5`) each pass with `scripts/orca-ralph-PROMPT.md`. Each pass
reads AGENT-MEMORY + STATE.md, enters `autonomy.loop`, dispatches through Orca
when reachable (else Claude sub-agents), works to its context ceiling, commits
state, and ends with one sigil. The repo is the only memory between passes.

Kept from Charge: fresh context per pass, disk state as sole authority, sigil
vocabulary as claims, harness-side deterministic stall detection (progress
signature = main tip + status + plan/ledger bytes), caps, honest terminal
states (DONE 0 / STALLED 3 / EXHAUSTED 4 / BLOCKED 5 / NEEDS-APPROVAL 6).
Changed for Orchestra: no `loop-state.json` feature list — the ledger and
STATE.md are the state file; no per-feature verify commands — gates and
pr-reviewer CLEAN are the verification; `SIGIL: RECYCLE` added as the normal
"context spent, work remains" exit; dispatch layer is Orca per
`docs/orchestra/orca-dispatch.md`.

## Invocation

Named triggers unchanged (`orchestra autonomy` / `run overnight` / `ralph`).
For a run meant to outlive this session, the user (or the coordinator, on the
user's autonomy invocation) starts the harness in a plain terminal:

    ./scripts/orca-ralph.sh -n 20 -N 2

An OPEN run in STATE.md is required (the script refuses otherwise). Passes run
with `--permission-mode bypassPermissions`; the repo's guard hooks stay armed
and are the real rails (block-dangerous.py, guard-git-add.sh, CLEAN-gated
merges, migration denies). Do not start the harness while another coordinator
session is live on the same checkout — one coordinator per repo.

## Duties of a harness-driven pass (restated in the pass prompt)

- Never end a turn waiting; poll dispatched work in the foreground.
- Park blocked items; open the next plan when one closes; re-plans reuse
  committed recon.
- At the context ceiling: commit (explicit paths), update STATE.md + ledger so
  the next pass needs nothing from the conversation, emit `SIGIL: RECYCLE`.
- Report honestly; STALLED/EXHAUSTED belong to the harness.
