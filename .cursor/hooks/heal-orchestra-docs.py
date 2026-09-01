#!/usr/bin/env python3
"""Cursor adapter: forwards to the native `.claude/hooks/heal-orchestra-docs.py`.

Direction reversed 2026-09-01 (SPEC-native.md §1) — the deny/heal logic now
lives under `.claude/`, source of truth; this file loads it by path so
`.cursor/hooks/session-start.py` (which imports "heal-orchestra-docs.py" from
its own directory) keeps working unchanged. Deleting `.cursor/` now removes
zero Claude behavior; deleting `.claude/` breaks this adapter loudly (fails
open on the SessionStart hook, logged) rather than silently.
"""
import importlib.util
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_NATIVE = os.path.join(_HERE, "..", "..", ".claude", "hooks", "heal-orchestra-docs.py")

_spec = importlib.util.spec_from_file_location("heal_orchestra_docs_native", _NATIVE)
if _spec is None or _spec.loader is None:
    raise ImportError(f"native heal module missing: {_NATIVE}")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

# Re-export so `spec_from_file_location(..., "heal-orchestra-docs.py")` callers
# (this file's own dir, e.g. .cursor/hooks/session-start.py) see the same API.
heal_agents = _mod.heal_agents
heal_memory = _mod.heal_memory

if __name__ == "__main__":
    try:
        json.load(sys.stdin)
    except Exception:
        pass
    try:
        heal_agents()
        heal_memory()
    except Exception as e:
        _mod.log(f"heal error: {type(e).__name__}")
    print("{}")
    sys.exit(0)
