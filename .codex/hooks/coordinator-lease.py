#!/usr/bin/env python3
"""Acquire, inspect, or release the session-bound Codex coordinator lease."""

import argparse
import json
import os
import re
import subprocess
import sys
import time


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(2)


def repo_root(requested):
    resolved = subprocess.run(
        ["git", "-C", requested or os.getcwd(), "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    if resolved.returncode != 0:
        fail("coordinator lease requires a Git worktree")
    return os.path.realpath(resolved.stdout.strip())


def git_common_dir(root):
    resolved = subprocess.run(
        ["git", "-C", root, "rev-parse", "--path-format=absolute", "--git-common-dir"],
        check=False,
        capture_output=True,
        text=True,
    )
    if resolved.returncode != 0:
        fail("coordinator lease could not resolve the Git common directory")
    return os.path.realpath(resolved.stdout.strip())


def lease_path(root):
    return os.path.join(git_common_dir(root), "codex-orchestra", "coordinator-lease.json")


def read_lease(path):
    try:
        with open(path, encoding="utf-8") as handle:
            lease = json.load(handle)
    except FileNotFoundError:
        return None
    except (OSError, ValueError, TypeError):
        fail("coordinator lease exists but is unreadable; refusing automatic takeover")
    if not isinstance(lease, dict) or not lease.get("session_id"):
        fail("coordinator lease is invalid; refusing automatic takeover")
    return lease


def state_is_open(root):
    try:
        with open(os.path.join(root, "docs", "orchestra", "STATE.md"), encoding="utf-8") as handle:
            return bool(re.search(r"status:\s*\*\*OPEN\*\*", handle.read()))
    except OSError:
        return False


def acquire(root, session_id):
    path = lease_path(root)
    existing = read_lease(path)
    if existing:
        if existing.get("session_id") == session_id:
            print(json.dumps(existing))
            return
        fail(f"coordinator lease already belongs to session {existing.get('session_id')}; no stale takeover")
    if state_is_open(root):
        fail("cannot acquire Codex coordinator lease while tracked STATE.md is OPEN")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    record = {"session_id": session_id, "acquired_at": int(time.time())}
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(record, handle)
    except FileExistsError:
        fail("coordinator lease appeared concurrently; refusing takeover")
    print(json.dumps(record))


def release(root, session_id):
    path = lease_path(root)
    existing = read_lease(path)
    if not existing:
        fail("no coordinator lease exists")
    if existing.get("session_id") != session_id:
        fail(f"coordinator lease belongs to session {existing.get('session_id')}; refusing release")
    os.unlink(path)
    print(json.dumps({"released": True, "session_id": session_id}))


def status(root, session_id):
    existing = read_lease(lease_path(root))
    result = {
        "active": bool(existing),
        "matches": bool(existing and existing.get("session_id") == session_id),
    }
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("acquire", "release", "status"))
    parser.add_argument("--root")
    parser.add_argument("--session-id", required=True)
    args = parser.parse_args()
    root = repo_root(args.root)
    {"acquire": acquire, "release": release, "status": status}[args.action](root, args.session_id)


if __name__ == "__main__":
    main()
