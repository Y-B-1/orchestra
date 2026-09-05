#!/usr/bin/env python3
"""Codex SessionStart advisory. It intentionally performs no filesystem writes."""

import json
import shlex
import sys

try:
    payload = json.load(sys.stdin)
except (ValueError, TypeError):
    payload = {}

session_id = payload.get("session_id") or payload.get("sessionId") or "<session-id>"
quoted_session_id = shlex.quote(session_id)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": (
            "Codex-native Orchestra coordination is available but inactive. "
            "It activates only after the user makes an explicit Orchestra choice; "
            "ordinary Codex sessions must not open, heal, or resume a run. "
            "After that explicit choice, acquire the session-bound lease with: "
            "python3 .codex/hooks/coordinator-lease.py acquire --session-id "
            f"{quoted_session_id}"
        ),
    }
}))
