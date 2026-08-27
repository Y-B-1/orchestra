#!/usr/bin/env python3
"""Cursor subagentStart hook: denies sub-agents spawning their own sub-agents.

Policy, not platform: since Cursor 2.5 a sub-agent may launch one further level;
this system forbids it — all fan-out belongs to the orchestrator.

Mechanism: child conversation ids seen spawning are recorded in
.orchestra/subagent-children.json; a spawn whose parent is a recorded child is
nested and denied. Fails OPEN (allow) on payload surprises, but logs every
fail-open to .orchestra/hook-failures.log so the janitor surfaces a disarmed
hook instead of it dying silently after a Cursor update.
"""
import json
import os
import sys

STATE = os.path.join(".orchestra", "subagent-children.json")
LOG = os.path.join(".orchestra", "hook-failures.log")


def log_failure(note):
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(LOG, "a") as f:
            f.write(f"block-nested-subagents: {note}\n")
    except Exception:
        pass


def respond(permission, msg=None):
    out = {"permission": permission}
    if msg:
        out["agent_message"] = msg
        out["user_message"] = msg
    print(json.dumps(out))
    sys.exit(0)


try:
    payload = json.load(sys.stdin)
except Exception:
    log_failure("stdin parse failure")
    respond("allow")

parent = (payload.get("parent_conversation_id")
          or payload.get("parentConversationId") or "")
child = (payload.get("conversation_id") or payload.get("conversationId")
         or payload.get("subagent_conversation_id") or "")

if not parent and not child:
    log_failure("payload had no recognizable conversation id fields — hook may be disarmed by a schema change")

children = set()
try:
    with open(STATE) as f:
        children = set(json.load(f))
except FileNotFoundError:
    pass
except Exception:
    log_failure("state file unreadable")

if parent and parent in children:
    respond("deny",
            "Orchestra policy: sub-agents must not spawn sub-agents. All fan-out belongs "
            "to the orchestrator (main session). Finish your own brief and report back.")

if child:
    children.add(child)
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(STATE, "w") as f:
            json.dump(sorted(children), f)
    except Exception:
        log_failure("state file unwritable")

respond("allow")
