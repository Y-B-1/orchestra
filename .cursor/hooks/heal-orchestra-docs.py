#!/usr/bin/env python3
"""sessionStart: keep AGENTS.md and AGENT-MEMORY.md as fill-in frameworks.

Creates missing files from docs/orchestra/*.framework.md. Appends a missing
## Orchestra block. Prepends a missing How-to-fill on memory. Never overwrites
filled project slots. Fail-open (empty JSON) so a missing template cannot
brick a session; every action is logged.
"""
import json
import os
import sys

LOG = os.path.join(".orchestra", "hook-failures.log")
AGENTS = "AGENTS.md"
MEMORY_CANDIDATES = [
    "docs/AGENT-MEMORY.md",
    "docs/agent-memory.md",
]
FRAME_AGENTS = os.path.join("docs", "orchestra", "AGENTS.framework.md")
FRAME_MEMORY = os.path.join("docs", "orchestra", "AGENT-MEMORY.framework.md")
ORCHESTRA_HEADING = "## Orchestra"
FILL_HEADING = "## How to fill"


def log(note):
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(LOG, "a") as f:
            f.write(f"heal-orchestra-docs: {note}\n")
    except Exception:
        pass


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return None
    except Exception as e:
        log(f"read failed {path}: {type(e).__name__}")
        return None


def write(path, text):
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w") as f:
            f.write(text if text.endswith("\n") else text + "\n")
        return True
    except Exception as e:
        log(f"write failed {path}: {type(e).__name__}")
        return False


def orchestra_block():
    framed = read(FRAME_AGENTS) or ""
    if ORCHESTRA_HEADING in framed:
        part = framed.split(ORCHESTRA_HEADING, 1)[1]
        nxt = part.find("\n## ")
        body = part if nxt < 0 else part[:nxt]
        return ORCHESTRA_HEADING + body.rstrip() + "\n"
    return (
        "## Orchestra\n\n"
        "When the orchestrator skill is loaded, the main session is the "
        "orchestrator. Routing: `.cursor/skills/orchestrator/flow.json`.\n"
    )


def heal_agents():
    text = read(AGENTS)
    frame = read(FRAME_AGENTS)
    if text is None:
        if frame:
            write(AGENTS, frame)
            log("created AGENTS.md from framework")
        else:
            log("AGENTS.md missing and no framework on disk")
        return
    if ORCHESTRA_HEADING not in text:
        write(AGENTS, text.rstrip() + "\n\n" + orchestra_block())
        log("appended ## Orchestra to AGENTS.md")


def existing_memory_path():
    for p in MEMORY_CANDIDATES:
        if os.path.isfile(p):
            return p
    return None


def heal_memory():
    path = existing_memory_path()
    frame = read(FRAME_MEMORY)
    if path is None:
        if frame:
            write("docs/AGENT-MEMORY.md", frame)
            log("created docs/AGENT-MEMORY.md from framework")
        else:
            log("memory index missing and no framework on disk")
        return
    text = read(path)
    if text is None:
        return
    if FILL_HEADING not in text:
        how = ""
        if frame and FILL_HEADING in frame:
            rest = frame.split(FILL_HEADING, 1)[1]
            nxt = rest.find("\n## ")
            how = FILL_HEADING + (rest if nxt < 0 else rest[:nxt]).rstrip() + "\n\n"
        else:
            how = (
                "## How to fill\n\n"
                "- topic · path · as-of date · one-line lesson. Prune stale "
                "entries. Git is history.\n\n"
            )
        write(path, how + text.lstrip())
        log(f"prepended How to fill on {path}")


if __name__ == "__main__":
    try:
        json.load(sys.stdin)
    except Exception:
        log("stdin parse failure")

    try:
        heal_agents()
        heal_memory()
    except Exception as e:
        log(f"heal error: {type(e).__name__}")

    print("{}")
    sys.exit(0)
