#!/usr/bin/env python3
"""Claude PreModelSwitch: locks the main-session model to the matrix.

MODEL-GUARD (ticket, ruling docs/plans/RULINGS-2026-09-02-founder.md U11,
verbatim): "we're using fable 5.1 strictly and explicitly on low effort ...
it has to be invoked every single time, either via hook, via a rule, a
guardrail, whatever it is."

PreModelSwitch DOES support blocking (confirmed against the official hooks
reference, 2026-09-02): it fires before Claude Code applies a requested model
switch and can return `permissionDecision: "deny"` to refuse it. So this is a
real LOCK, not a warning — a `/model` switch (or a client requesting a
different model) to anything but `claude-fable-5` at `low` effort is denied
before it takes effect.

Payload (per the docs): `to_model` (canonical model name), and `effort`
(`{"level": ...}`) when the target model supports effort levels. Both are
checked: the model id AND the effort level.

Escape hatch: `ORCHESTRA_MODEL_UNLOCK=1` in the PROCESS environment — never a
file — same shape as the routing floor's escape (`require-open-run.py`).

Fails OPEN on payload surprises (same convention as orchestra-block-nested.py):
an unparseable payload should never brick the session, but is logged so the
silent-disarm signature is visible.
"""
import json
import os
import sys

LOCKED_MODEL = "claude-fable-5"  # U14 (2026-09-02): Fable 5, NOT 5.1
LOCKED_EFFORT = "low"  # U14 (2026-09-02)


def log_failure(note):
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(".orchestra/hook-failures.log", "a") as f:
            f.write(f"guard-model: {note}\n")
    except Exception:
        pass


def decide(decision, reason=None):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreModelSwitch",
            "permissionDecision": decision,
        }
    }
    if reason:
        out["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(out))
    sys.exit(0)


try:
    payload = json.load(sys.stdin)
except Exception:
    log_failure("stdin parse failure")
    decide("allow")

if os.environ.get("ORCHESTRA_MODEL_UNLOCK") == "1":
    decide("allow")

to_model = payload.get("to_model") or ""
effort = payload.get("effort")
effort_level = effort.get("level") if isinstance(effort, dict) else None

if not to_model:
    # No target model named at all — nothing to compare against. Fail open,
    # but log it: a payload shape change here is exactly how this guard would
    # go silently disarmed.
    log_failure("PreModelSwitch payload carried no to_model")
    decide("allow")

if to_model != LOCKED_MODEL:
    decide(
        "deny",
        f"MODEL-GUARD (ruling 2026-09-02, U11): main session is locked to "
        f"{LOCKED_MODEL} at {LOCKED_EFFORT} effort — not up for debate or "
        f"chance. Requested switch to {to_model} is refused. Escape hatch: "
        f"set ORCHESTRA_MODEL_UNLOCK=1 in the process environment.",
    )

if effort_level is not None and effort_level != LOCKED_EFFORT:
    decide(
        "deny",
        f"MODEL-GUARD (ruling 2026-09-02, U11): main session is locked to "
        f"{LOCKED_MODEL} at {LOCKED_EFFORT} effort. Requested effort "
        f"{effort_level!r} is refused. Escape hatch: set "
        f"ORCHESTRA_MODEL_UNLOCK=1 in the process environment.",
    )

decide("allow")
