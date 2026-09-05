#!/usr/bin/env python3
"""Codex SubagentStart advisory; this event cannot stop a subagent startup."""

import json
import os
import subprocess
import sys

CONTEXT = (
    "You are an Orchestra worker, not the Orchestra coordinator. Execute only "
    "the assigned brief and owned paths. You must not route work, update shared "
    "Orchestra state, and must not spawn subagents. Do not load the coordinator skill."
)


def load_policy(root):
    path = os.path.join(root, "docs", "orchestra", "codex-models.json")
    try:
        with open(path, encoding="utf-8") as handle:
            return (json.load(handle).get("roles") or {})
    except (OSError, ValueError, TypeError):
        return {}


def repository_root(payload):
    explicit = os.environ.get("CLAUDE_PROJECT_DIR")
    if explicit:
        return os.path.realpath(explicit)
    cwd = payload.get("cwd") or os.getcwd()
    resolved = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    return os.path.realpath(resolved.stdout.strip()) if resolved.returncode == 0 else os.path.realpath(cwd)


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        payload = {}

    root = repository_root(payload)
    role = payload.get("agent_type") or payload.get("agentType") or ""
    expected = load_policy(root).get(role) or {}
    observed_model = payload.get("model")
    observed_effort = (
        payload.get("model_reasoning_effort")
        or payload.get("reasoning_effort")
        or payload.get("effort")
    )
    mismatches = []
    # Current official SubagentStart fields do not promise model or effort.
    # Compare only when a host actually supplies them; generated TOML tests are
    # the deterministic model-policy seam when they are absent.
    # `permission_mode` is an approval policy, not a sandbox identity, so it is
    # deliberately not compared with generated read-only role configuration.
    if expected.get("model") and observed_model and observed_model != expected["model"]:
        mismatches.append(f"model expected {expected['model']}, observed {observed_model}")
    if expected.get("effort") and observed_effort and observed_effort != expected["effort"]:
        mismatches.append(f"effort expected {expected['effort']}, observed {observed_effort}")
    result = {
        "hookSpecificOutput": {
            "hookEventName": "SubagentStart",
            "additionalContext": CONTEXT,
        }
    }
    if mismatches:
        result["systemMessage"] = (
            f"Model policy mismatch or worker warning for Codex role {role or 'unknown'}: "
            + "; ".join(mismatches)
            + ". SubagentStart is advisory and cannot stop startup; inspect the generated agent definition."
        )
    print(json.dumps(result))


if __name__ == "__main__":
    main()
