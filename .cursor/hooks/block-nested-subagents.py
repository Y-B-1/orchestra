#!/usr/bin/env python3
"""Cursor subagentStart hook: denies sub-agents spawning their own sub-agents.

Since Cursor 2.5 a sub-agent may launch one further level of children. This
system forbids that by policy: all fan-out belongs to the orchestrator (the
main session), or fresh-eyes and single-dispatcher guarantees break.

Mechanism: every subagentStart reports a parent conversation id. Ids we have
seen spawned as children are recorded in a state file; a spawn whose parent is
a recorded child is a nested spawn and is denied. Fails OPEN on any surprise
(unknown payload shape, unreadable state file) so a hook bug cannot block the
orchestrator's own legitimate dispatches.
"""
import json
import os
import sys
import tempfile

STATE = os.path.join(tempfile.gettempdir(), "orchestra-subagent-children.json")


def respond(permission, agent_message=None):
    out = {"permission": permission}
    if agent_message:
        out["agent_message"] = agent_message
        out["user_message"] = agent_message
    print(json.dumps(out))
    sys.exit(0)


try:
    payload = json.load(sys.stdin)
except Exception:
    respond("allow")

parent = (payload.get("parent_conversation_id")
          or payload.get("parentConversationId") or "")
child = (payload.get("conversation_id") or payload.get("conversationId")
         or payload.get("subagent_conversation_id") or "")

children = set()
try:
    with open(STATE) as f:
        children = set(json.load(f))
except Exception:
    pass

if parent and parent in children:
    respond("deny",
            "Orchestra policy: sub-agents must not spawn sub-agents. All fan-out "
            "belongs to the orchestrator (main session). Finish your own brief and "
            "report back; the orchestrator will dispatch any further work.")

if child:
    children.add(child)
    try:
        with open(STATE, "w") as f:
            json.dump(sorted(children), f)
    except Exception:
        pass

respond("allow")
