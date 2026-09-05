#!/usr/bin/env python3
"""Codex PreToolUse routing floor for Bash writes and apply_patch.

Bash extraction covers explicit redirects, tee, and sed -i. It does not follow
directory changes inside compound commands or parse arbitrary interpreter
bodies; those remain disclosed limits rather than false enforcement claims.
Detected targets outside the repository fail closed instead of disappearing
from the per-session routing count.
"""

import json
import os
import re
import subprocess
import sys

THRESHOLD = 3
PATCH_TARGET = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", re.MULTILINE)
REDIRECT = re.compile(r"(?<!<)\d{0,2}>{1,2}(?!&)\s*([^\s|;&()<>]+)")
DEVNULLISH = {"/dev/null", "/dev/stdout", "/dev/stderr"}


def output(decision="allow", reason=None):
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        result["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(result))


def deny(reason):
    output("deny", reason)


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


def common_dir(root):
    resolved = subprocess.run(
        ["git", "-C", root, "rev-parse", "--path-format=absolute", "--git-common-dir"],
        check=False,
        capture_output=True,
        text=True,
    )
    return os.path.realpath(resolved.stdout.strip()) if resolved.returncode == 0 else None


def lease_matches(root, session_id):
    git_dir = common_dir(root)
    if not git_dir:
        return False
    try:
        path = os.path.join(git_dir, "codex-orchestra", "coordinator-lease.json")
        with open(path, encoding="utf-8") as handle:
            lease = json.load(handle)
        return lease.get("session_id") == session_id
    except (OSError, ValueError, TypeError):
        return False


def worker_environment():
    return bool(
        os.environ.get("ORCHESTRA_CODEX_WORKER")
        or (os.environ.get("ORCA_WORKTREE_ID") and not os.environ.get("ORCA_WORKSPACE_ID"))
    )


def normalize(root, base, raw):
    target = raw.strip().strip('"\'')
    absolute = target if os.path.isabs(target) else os.path.join(base, target)
    normalized = os.path.realpath(os.path.normpath(absolute))
    try:
        inside = os.path.commonpath([root, normalized]) == root
    except ValueError:
        inside = False
    return normalized, inside


def bash_targets(command):
    if not command:
        return set()
    head = re.split(r"<<", command, maxsplit=1)[0]
    targets = set()
    for segment in re.split(r"&&|\|\||;|\|", head):
        for match in REDIRECT.finditer(segment):
            path = match.group(1).strip('"\'')
            if path and path not in DEVNULLISH:
                targets.add(path)
        tokens = segment.split()
        if "tee" in tokens:
            index = tokens.index("tee") + 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 1
            if index < len(tokens):
                targets.add(tokens[index].strip('"\''))
        if "sed" in tokens and any(token == "-i" or token.startswith("-i") for token in tokens):
            positional = [token for token in tokens[1:] if not token.startswith("-")]
            if positional:
                targets.add(positional[-1].strip('"\''))
    return targets


def routing_file(root, session_id):
    safe_id = re.sub(r"[^A-Za-z0-9_-]", "_", session_id) or "unknown"
    return os.path.join(root, ".orchestra", "routing", f"{safe_id}.json")


def load_touched(path):
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    files = data.get("files")
    if not isinstance(files, list) or not all(isinstance(item, str) for item in files):
        raise ValueError("invalid routing state")
    return set(files)


def save_touched(path, files):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = f"{path}.tmp.{os.getpid()}"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump({"files": sorted(files)}, handle)
    os.replace(temporary, path)


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        deny("Codex routing floor: malformed hook input; mutating calls fail closed.")
        return

    root = repository_root(payload)
    base = os.path.realpath(payload.get("cwd") or root)
    tool_name = payload.get("tool_name") or payload.get("toolName") or ""
    command = (payload.get("tool_input") or payload.get("toolInput") or {}).get("command") or ""

    if tool_name == "apply_patch":
        raw_targets = PATCH_TARGET.findall(command)
        if not raw_targets:
            deny("Codex routing floor: apply_patch payload had no parseable file targets.")
            return
        normalized = [normalize(root, base, target) for target in raw_targets]
        if any(not inside for _, inside in normalized):
            deny("Codex routing floor: apply_patch target escapes the repository root.")
            return
        targets = {path for path, _ in normalized}
    elif tool_name == "Bash":
        normalized = [normalize(root, base, raw) for raw in bash_targets(command)]
        if any(not inside for _, inside in normalized):
            deny("Codex routing floor: Bash write target escapes the repository root.")
            return
        targets = {path for path, _ in normalized}
        if not targets:
            output()
            return
    else:
        output()
        return

    session_id = payload.get("session_id") or payload.get("sessionId") or ""
    if not session_id:
        deny("Codex routing floor: mutating call is missing session_id.")
        return

    if worker_environment() or lease_matches(root, session_id):
        output()
        return

    path = routing_file(root, session_id)
    try:
        prospective = load_touched(path) | targets
        if len(prospective) > THRESHOLD:
            deny(
                "Orchestra routing floor: this Codex session would edit "
                f"{len(prospective)} distinct files without a matching coordinator lease."
            )
            return
        save_touched(path, prospective)
    except (OSError, ValueError, TypeError) as error:
        deny(f"Codex routing floor: routing persistence failed closed ({type(error).__name__}).")
        return
    output()


if __name__ == "__main__":
    main()
