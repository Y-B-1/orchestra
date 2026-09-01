#!/usr/bin/env python3
"""Claude PreToolUse(Skill): workers must not invoke main-session-only skills.

Layer 2 of the three-layer defense (SPEC-claude-native §3): a worker's
`skills:` preload already gives it the rails it needs (layer 1), and this
hook denies it reaching for the orchestrator skill anyway. Layer 3
(`orchestra-worker-context.py`) covers the unnamed-worker case this cannot:
a Skill dispatch always carries identity when it comes from inside a worker
(same two channels `orchestra-block-nested.py` keys on — `agent_id`/`agentId`
is the identity, always present; `agent_type`/`agentType` is the label, only
present for a named worker).

Fails OPEN on parse surprises, logged to .orchestra/hook-failures.log — the
main session must never be bricked by a malformed payload.
"""
import json
import os
import sys

MAIN_SESSION_SKILLS = {"orchestrator"}

DENY_MESSAGE = "Worker sub-agents do not route. Execute your brief; your rails are preloaded."


def log_failure(note):
    try:
        base = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        orchestra_dir = os.path.join(base, ".orchestra")
        os.makedirs(orchestra_dir, exist_ok=True)
        with open(os.path.join(orchestra_dir, "hook-failures.log"), "a") as f:
            f.write(f"orchestra-block-worker-skill: {note}\n")
    except Exception:
        pass


try:
    payload = json.load(sys.stdin)
except Exception:
    log_failure("stdin parse failure")
    sys.exit(0)

worker_id = payload.get("agent_id") or payload.get("agentId") or ""
worker_type = payload.get("agent_type") or payload.get("agentType") or ""

tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
skill_name = tool_input.get("skill") or tool_input.get("name") or ""

if (worker_id or worker_type) and skill_name in MAIN_SESSION_SKILLS:
    print(DENY_MESSAGE, file=sys.stderr)
    sys.exit(2)

sys.exit(0)
