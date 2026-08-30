#!/usr/bin/env python3
"""Write .claude/agents/*.md from .cursor/agents/*.md bodies + Claude YAML.

Bodies must stay identical (install.sh checks). Cursor YAML (model slugs,
force-default-model) must not land in the Claude files.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, ".cursor", "agents")
DST = os.path.join(ROOT, ".claude", "agents")

# Highest intelligence / middle / execution — docs/orchestra/claude-models.md
MATRIX = {
    "architect": ("claude-fable-5", "low"),
    "planner": ("claude-fable-5", "low"),
    "red-teamer": ("claude-fable-5", "low"),
    "auditor": ("claude-fable-5", "low"),
    "builder-max": ("claude-fable-5", "low"),
    "pr-reviewer": ("claude-fable-5", "low"),
    "scout": ("claude-opus-5", "medium"),
    "researcher": ("claude-opus-5", "medium"),
    "reviewer": ("claude-opus-5", "medium"),
    "builder": ("claude-sonnet-5", "medium"),
    "gatekeeper": ("claude-sonnet-5", "medium"),
    "janitor": ("claude-sonnet-5", "medium"),
    "releaser": ("claude-sonnet-5", "medium"),
}


def split_md(text: str) -> tuple[str, str]:
    if text.startswith("---"):
        end = text.find("\n---\n", 3)
        if end != -1:
            return text[4:end], text[end + 5 :]
    return "", text


def fm_field(front: str, key: str) -> str:
    m = re.search(rf"^{key}:\s*(.+)$", front, re.M)
    return m.group(1).strip() if m else ""


def main() -> int:
    os.makedirs(DST, exist_ok=True)
    missing = [r for r in MATRIX if not os.path.isfile(os.path.join(SRC, f"{r}.md"))]
    if missing:
        print("FAIL: missing Cursor agents: " + ", ".join(missing), file=sys.stderr)
        return 1
    for role, (model, effort) in MATRIX.items():
        raw = open(os.path.join(SRC, f"{role}.md")).read()
        front, body = split_md(raw)
        desc = fm_field(front, "description") or f"Orchestrator-dispatched {role}."
        out = (
            f"---\n"
            f"name: {role}\n"
            f"description: {desc}\n"
            f"model: {model}\n"
            f"effort: {effort}\n"
            f"disallowedTools: Agent\n"
            f"---\n"
            f"{body.lstrip('\n')}"
        )
        if not out.endswith("\n"):
            out += "\n"
        path = os.path.join(DST, f"{role}.md")
        with open(path, "w") as f:
            f.write(out)
        print(f"wrote {os.path.relpath(path, ROOT)}")
    extra = sorted(
        n for n in os.listdir(DST) if n.endswith(".md") and n[:-3] not in MATRIX
    )
    if extra:
        print("note: extra Claude agent files (not in matrix): " + ", ".join(extra))
    return 0


if __name__ == "__main__":
    sys.exit(main())
