#!/usr/bin/env python3
"""Claude SubagentStart: injects the worker-negative context.

Layer 3 of the three-layer defense (SPEC-claude-native §3): the one channel
that reaches a sub-agent dispatched WITHOUT a named definition — there is no
`skills:` preload to carry the rule for that case, so it is injected here on
every SubagentStart instead. Runs for every worker regardless of payload
shape; the negative it prints does not depend on parsing any field.

Fails OPEN on parse surprises: prints an empty JSON object rather than
bricking the sub-agent's start, and logs the surprise to
.orchestra/hook-failures.log.
"""
import json
import os
import sys

ADDITIONAL_CONTEXT = (
    "You are an Orchestra worker, not the main session. Execute the brief you "
    "were given. Do not load the orchestrator skill or route. Rails that apply "
    "to your files: `.claude/rules/`."
)


def log_failure(note):
    try:
        base = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        orchestra_dir = os.path.join(base, ".orchestra")
        os.makedirs(orchestra_dir, exist_ok=True)
        with open(os.path.join(orchestra_dir, "hook-failures.log"), "a") as f:
            f.write(f"orchestra-worker-context: {note}\n")
    except Exception:
        pass


try:
    json.load(sys.stdin)
except Exception:
    log_failure("stdin parse failure")
    print("{}")
    sys.exit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SubagentStart",
        "additionalContext": ADDITIONAL_CONTEXT,
    }
}))
sys.exit(0)
