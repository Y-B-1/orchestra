#!/usr/bin/env python3
"""Claude PreToolUse(Agent): workers must not spawn sub-agents.

Main session has no agent_type (or it is empty). A worker session carries
agent_type. Deny Agent/Task from a worker. Fail open on parse surprises and
log .orchestra/hook-failures.log.
"""
import json
import os
import sys


def log_failure(note):
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(".orchestra/hook-failures.log", "a") as f:
            f.write(f"orchestra-block-nested: {note}\n")
    except Exception:
        pass


def decide(decision, reason=None):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
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

tool = payload.get("tool_name") or payload.get("toolName") or ""
kind = payload.get("agent_type") or payload.get("agentType") or ""
if tool in ("Agent", "Task") and kind:
    decide(
        "deny",
        "Orchestra policy: sub-agents must not spawn sub-agents. All fan-out "
        "belongs to the orchestrator (main session). Finish your brief and report back.",
    )
decide("allow")
