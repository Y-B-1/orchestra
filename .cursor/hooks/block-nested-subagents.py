#!/usr/bin/env python3
"""Cursor subagentStart hook: denies sub-agents spawning their own sub-agents.

Policy, not platform: since Cursor 2.5 a sub-agent may launch one further level;
this system forbids it — all fan-out belongs to the orchestrator.

Documented payload (https://cursor.com/docs/hooks): subagent_id is this spawn,
parent_conversation_id is the parent session. conversation_id is the parent/
session — never record it as a child (that poisons the set and denies every
later orchestrator dispatch).

Mechanism: record each allowed spawn's subagent_id (cap 200, oldest dropped).
A spawn whose parent_conversation_id is a recorded child id is nested → deny.

Fails OPEN (allow) on payload surprises, but logs every fail-open to
.orchestra/hook-failures.log. Pair with failClosed: true in hooks.json so a
crash/timeout/invalid JSON blocks the spawn instead of leaking a nest.
"""
import json
import os
import time
import sys

STATE = os.path.join(".orchestra", "subagent-children.json")
LOG = os.path.join(".orchestra", "hook-failures.log")
CAP = 200


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


def load_entries():
    try:
        with open(STATE) as f:
            raw = json.load(f)
    except FileNotFoundError:
        return []
    except Exception:
        log_failure("state file unreadable")
        return []
    if isinstance(raw, list):
        if raw and isinstance(raw[0], str):
            return [{"id": x, "parent": "", "type": "", "git_branch": "", "ts": 0}
                    for x in raw]
        return [e for e in raw if isinstance(e, dict) and e.get("id")]
    if isinstance(raw, dict) and isinstance(raw.get("children"), list):
        return [e for e in raw["children"] if isinstance(e, dict) and e.get("id")]
    log_failure("state file unexpected shape")
    return []


def save_entries(entries):
    if len(entries) > CAP:
        entries = entries[-CAP:]
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(STATE, "w") as f:
            json.dump({"children": entries, "cap": CAP}, f)
    except Exception:
        log_failure("state file unwritable")


try:
    payload = json.load(sys.stdin)
except Exception:
    log_failure("stdin parse failure")
    respond("allow")

# Documented child id. Do not fall back to conversation_id — that field is the
# parent/session in current Cursor payloads and must not enter the child set.
child = (payload.get("subagent_id") or payload.get("subagentId") or "")
parent = (payload.get("parent_conversation_id")
          or payload.get("parentConversationId") or "")
kind = payload.get("subagent_type") or payload.get("subagentType") or ""
branch = payload.get("git_branch") or payload.get("gitBranch") or ""

if not child:
    log_failure("payload had no subagent_id — hook may be disarmed by a schema change")

entries = load_entries()
known = {e["id"] for e in entries}

if parent and parent in known:
    respond(
        "deny",
        "Orchestra policy: sub-agents must not spawn sub-agents. All fan-out belongs "
        "to the orchestrator (main session). Finish your own brief and report back.",
    )

if child and child not in known:
    entries.append({
        "id": child,
        "parent": parent,
        "type": kind,
        "git_branch": branch,
        "ts": int(time.time()),
    })
    save_entries(entries)

respond("allow")
