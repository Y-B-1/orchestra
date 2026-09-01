#!/usr/bin/env python3
"""Claude PreToolUse(Agent): workers must not spawn sub-agents.

IDENTITY, NOT LABEL (repaired 2026-08-31, wave D2). This hook used to key on
`agent_type` ALONE. A captured live PreToolUse payload from inside a worker
(Claude Code, 2026-08-31) carries BOTH:

    "agent_id": "a4e8098b04426409c",   ← the identity: present for EVERY worker
    "agent_type": "builder",           ← the label: only when a NAMED agent
                                         definition was dispatched

`agent_id` is the load-bearing field. A sub-agent launched without a named
definition — a bare Task, or any future dispatch shape that does not resolve to
a file in .claude/agents/ — has an EMPTY agent_type, and the old hook read that
as "this is the main session" and ALLOWED the nest. The deny is now the UNION:
any worker identity at all closes the door. Both spellings are accepted on each
field, matching the Cursor twin (.cursor/hooks/block-nested-subagents.py).

The main session carries neither field.

Fails OPEN on parse surprises. An Agent/Task call whose payload carries NO
identity field at all is logged to .orchestra/hook-failures.log — that is the
signature of a schema change silently disarming this guard, and it is the one
thing a hook cannot detect about itself after the fact.
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

# The identity channels, in order of authority. agent_id is present for every
# worker; agent_type only for a named one. Either one means "not the main session".
worker_id = payload.get("agent_id") or payload.get("agentId") or ""
worker_type = payload.get("agent_type") or payload.get("agentType") or ""

if tool in ("Agent", "Task"):
    if worker_id or worker_type:
        decide(
            "deny",
            "Orchestra policy: sub-agents must not spawn sub-agents. All fan-out "
            "belongs to the orchestrator (main session). Finish your brief and report back.",
        )
    if "agent_id" not in payload and "agentId" not in payload:
        # Neither identity field is even PRESENT on an Agent dispatch. Every
        # payload we have captured carries agent_id inside a worker and omits it
        # in the main session, so absence is expected in the main session — but
        # if that ever stops being true this guard is disarmed and silent.
        log_failure(
            "Agent dispatch payload carried no agent_id key — main session, or a "
            "schema change has disarmed this hook; re-capture a worker payload"
        )

decide("allow")
