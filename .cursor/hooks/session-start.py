#!/usr/bin/env python3
"""sessionStart: heal charter/memory frameworks and surface disarmed hooks.

Fire-and-forget. Returns additional_context so a fail-open on the trivial or
single-ticket path (where the janitor never runs) is still visible. Heal never
overwrites filled CLAUDE.md / memory slots. AGENTS.md is a symlink to
project CLAUDE.md — never ~/.claude/CLAUDE.md.
"""
import json
import os
import sys

LOG = os.path.join(".orchestra", "hook-failures.log")


def heal():
    import importlib.util
    path = os.path.join(os.path.dirname(__file__), "heal-orchestra-docs.py")
    spec = importlib.util.spec_from_file_location("heal_orchestra_docs", path)
    if spec is None or spec.loader is None:
        return
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if hasattr(mod, "heal_agents"):
        mod.heal_agents()
    if hasattr(mod, "heal_memory"):
        mod.heal_memory()


def seed_state():
    dst = os.path.join(".orchestra", "state.json")
    src = os.path.join("docs", "orchestra", "state.example.json")
    if os.path.isfile(dst) or not os.path.isfile(src):
        return
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(src) as f:
            body = f.read()
        with open(dst, "w") as f:
            f.write(body if body.endswith("\n") else body + "\n")
    except Exception:
        pass


def failures():
    try:
        with open(LOG) as f:
            lines = [ln.rstrip() for ln in f if ln.strip()]
    except FileNotFoundError:
        return []
    except Exception:
        return []
    return lines[-20:]


try:
    json.load(sys.stdin)
except Exception:
    pass

notes = []
try:
    heal()
    seed_state()
except Exception as e:
    notes.append(f"heal error: {type(e).__name__}")

tail = failures()
if tail:
    notes.append(
        "Orchestra hook-failures.log is non-empty. A fail-open may mean a "
        "guardrail is disarmed. Last lines:\n- " + "\n- ".join(tail)
    )

ctx = ""
if notes:
    ctx = "\n".join(notes)

print(json.dumps({"additional_context": ctx} if ctx else {}))
sys.exit(0)
