#!/usr/bin/env python3
"""Claude SessionStart: heal charter/memory, inject orchestrator context.

Workers (agent_type set) get no orchestrator identity. Main session is told
to load the Cursor skill file — there is no second skill under .claude/skills/.
"""
import importlib.util
import json
import os
import sys

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
os.chdir(root)

try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}


def heal():
    path = os.path.join(root, ".cursor", "hooks", "heal-orchestra-docs.py")
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
    os.makedirs(".orchestra", exist_ok=True)
    with open(src) as f:
        body = f.read()
    with open(dst, "w") as f:
        f.write(body if body.endswith("\n") else body + "\n")


try:
    heal()
    seed_state()
except Exception:
    pass

kind = payload.get("agent_type") or payload.get("agentType") or ""
if kind:
    print("{}")
    sys.exit(0)

ctx = (
    "Orchestra main session (Claude Code). Load `.cursor/skills/orchestrator/SKILL.md` "
    "and route via `.cursor/skills/orchestrator/flow.json`. Workers: `.claude/agents/`. "
    "Models: `docs/orchestra/claude-models.md`. After intake the only user-facing stop "
    "is unanswered frontier questions. Maximize parallelism: dispatch every unblocked "
    "ticket whose files do not overlap, in one message — including current waves from "
    "independent plans. Do not write product code when a builder can. Do not add "
    "`.claude/skills/orchestrator/`."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }
}))
