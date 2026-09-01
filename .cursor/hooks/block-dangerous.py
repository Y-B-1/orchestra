#!/usr/bin/env python3
"""Cursor beforeShellExecution adapter — the deny logic itself lives in
`.claude/hooks/block-dangerous.py` (source of truth, SPEC-native.md §1). This
file reads Cursor's `{command}` payload, calls that module's `check_command`,
and emits Cursor's `{permission}` shape.

If `.claude/` is somehow absent, fail CLOSED (deny with an explanatory
message) — never open. Deleting `.cursor/` removes zero Claude behavior;
deleting `.claude/` while `.cursor/` remains must not silently reopen the gate.
"""
import importlib.util
import json
import os
import sys


def deny(reason):
    print(json.dumps({
        "permission": "deny",
        "user_message": f"Orchestra guardrail [deny]: {reason}",
        "agent_message": (f"The orchestra guardrail hook returned 'deny' ({reason}). "
                          "Do not retry variants; follow the release process."),
    }))
    sys.exit(0)


def allow():
    print(json.dumps({"permission": "allow"}))
    sys.exit(0)


# Resolve relative to this file's own location, not cwd: Cursor's fixture
# tests (and any future one) may run this script from a temp git repo with no
# .claude/ tree of its own, and CLAUDE_PROJECT_DIR is a Claude Code env var
# Cursor never sets — this file's real path is the one thing guaranteed stable.
root = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
source_path = os.path.join(root, ".claude", "hooks", "block-dangerous.py")

try:
    spec = importlib.util.spec_from_file_location("_claude_block_dangerous", source_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
except Exception:
    deny("the native guard at .claude/hooks/block-dangerous.py is missing or failed to load "
         "— fail closed rather than run with no guard")

try:
    payload = json.load(sys.stdin)
    cmd = payload.get("command") or (payload.get("tool_input") or {}).get("command") or ""
except Exception:
    allow()  # stdin parse failure: same fail-open contract as the native guard's own __main__.

reason = module.check_command(cmd)
if reason:
    deny(reason)
allow()
