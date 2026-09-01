#!/usr/bin/env python3
"""sessionStart: keep CLAUDE.md / AGENTS.md and AGENT-MEMORY.md as fill-in frameworks.

Creates missing files from docs/orchestra/*.framework.md. Appends a missing
## Orchestra block. Prepends a missing How-to-fill on memory. Never overwrites
filled project slots. Fail-open (empty JSON) so a missing template cannot
brick a session; every action is logged.

Charter rule: CLAUDE.md is the real file. AGENTS.md is a symlink to it (Cursor's
name). Never follow or copy ~/.claude/CLAUDE.md — that is global Claude config,
not the project charter.

NATIVE HOME (moved from `.cursor/hooks/` 2026-09-01, SPEC-native.md §1). This is
the source; `.claude/hooks/orchestra-session-start.py` imports it directly.
`.cursor/hooks/heal-orchestra-docs.py` is now a thin adapter that loads THIS
file — direction reversed so deleting `.cursor/` costs Claude nothing.
"""
import json
import os
import sys

LOG = os.path.join(".orchestra", "hook-failures.log")
AGENTS = "AGENTS.md"
CLAUDE = "CLAUDE.md"
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


def project_dir():
    return os.path.realpath(os.getcwd())


def inside_project(path):
    root = project_dir()
    real = os.path.realpath(path)
    return real == root or real.startswith(root + os.sep)


def is_outside_symlink(path):
    """True when path is a symlink whose resolved target is outside this repo."""
    if not os.path.islink(path):
        return False
    return not inside_project(path)


def unlink_outside(path, label):
    if not is_outside_symlink(path):
        return False
    log(f"{label} pointed outside the project ({os.path.realpath(path)}) — "
        "refusing (never ~/.claude/CLAUDE.md); removing the link")
    try:
        os.unlink(path)
    except OSError as e:
        log(f"could not unlink {path}: {type(e).__name__}")
        return True
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
        "orchestrator. Routing: `.claude/skills/orchestrator/references/flow.json`.\n"
    )


def ensure_agents_symlink():
    """AGENTS.md must be a relative symlink to project CLAUDE.md."""
    unlink_outside(AGENTS, "AGENTS.md")
    if os.path.islink(AGENTS):
        target = os.readlink(AGENTS)
        if target == CLAUDE:
            return True
        log(f"AGENTS.md symlink was {target!r}; retargeting to {CLAUDE}")
        try:
            os.unlink(AGENTS)
        except OSError as e:
            log(f"could not unlink AGENTS.md: {type(e).__name__}")
            return False
    elif os.path.isfile(AGENTS):
        if not os.path.isfile(CLAUDE):
            text = read(AGENTS)
            if text is not None:
                write(CLAUDE, text)
                log("copied AGENTS.md → CLAUDE.md")
            try:
                os.remove(AGENTS)
            except OSError as e:
                log(f"could not remove AGENTS.md after copy: {type(e).__name__}")
                return False
        else:
            a, c = read(AGENTS), read(CLAUDE)
            if a == c:
                try:
                    os.remove(AGENTS)
                    log("AGENTS.md was a duplicate of CLAUDE.md — replacing with symlink")
                except OSError as e:
                    log(f"could not remove duplicate AGENTS.md: {type(e).__name__}")
                    return False
            else:
                log("AGENTS.md and CLAUDE.md both exist and differ — left both; "
                    "will not destroy either to force a symlink")
                return False
    if not os.path.lexists(AGENTS) and os.path.isfile(CLAUDE):
        try:
            os.symlink(CLAUDE, AGENTS)
            log("linked AGENTS.md -> CLAUDE.md")
        except OSError as e:
            log(f"symlink failed: {type(e).__name__}")
            return False
    return True


def heal_agents():
    unlink_outside(CLAUDE, "CLAUDE.md")
    text = read(CLAUDE)
    frame = read(FRAME_AGENTS)
    if text is None:
        if os.path.isfile(AGENTS) and not os.path.islink(AGENTS):
            text = read(AGENTS)
            if text:
                write(CLAUDE, text)
                log("created CLAUDE.md from existing AGENTS.md")
        elif frame:
            write(CLAUDE, frame)
            log("created CLAUDE.md from framework")
        else:
            log("CLAUDE.md missing and no framework on disk")
            return
        text = read(CLAUDE)

    ensure_agents_symlink()

    text = read(CLAUDE)
    if text is None:
        return
    if ORCHESTRA_HEADING not in text:
        write(CLAUDE, text.rstrip() + "\n\n" + orchestra_block())
        log("appended ## Orchestra to CLAUDE.md")


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
