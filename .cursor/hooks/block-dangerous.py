#!/usr/bin/env python3
"""Cursor beforeShellExecution hook: blocks destructive commands.

stdin: JSON with the command; stdout: permission JSON (snake_case per
cursor.com/docs/hooks). Deliberately fails OPEN on parse errors so a hook bug
cannot brick the session; the deny path is what must stay deterministic.
"""
import json
import re
import shlex
import sys


def allow():
    print(json.dumps({"permission": "allow"}))
    sys.exit(0)


def deny(reason):
    print(json.dumps({
        "permission": "deny",
        "user_message": f"Blocked by orchestra guardrail: {reason}",
        "agent_message": ("This command is blocked by the orchestra guardrail hook "
                          f"({reason}). Destructive operations require the user to run "
                          "them manually. Do not retry variants of the same command."),
    }))
    sys.exit(0)


try:
    payload = json.load(sys.stdin)
    cmd = payload.get("command", "") or ""
except Exception:
    allow()

GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--exec-path", "--namespace"}


def analyze_git(tokens):
    """tokens: token list starting at 'git'. Returns (subcommand, args) with global opts stripped."""
    i = 1
    while i < len(tokens):
        t = tokens[i]
        if t in GIT_VALUE_OPTS:
            i += 2
        elif any(t.startswith(o + "=") for o in GIT_VALUE_OPTS) or t.startswith("--"):
            i += 1
        else:
            return t, tokens[i + 1:]
    return None, []


# Pipe-to-shell must be checked on the raw line, before pipes are split away.
if re.search(r"\b(curl|wget)\b[^|;&]*\|\s*(ba|z|da|k)?sh\b", cmd):
    deny("piping a download into a shell")

for segment in re.split(r"(?:&&|\|\||;|\|)", cmd):
    try:
        tokens = shlex.split(segment.strip())
    except ValueError:
        tokens = segment.strip().split()
    while tokens and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0]):
        tokens = tokens[1:]
    if tokens and tokens[0] in ("sudo", "command", "env"):
        tokens = tokens[1:]
    if not tokens:
        continue

    prog = tokens[0]

    if prog == "git":
        sub, args = analyze_git(tokens)
        if sub is None:
            continue
        flags = [a for a in args if a.startswith("-")]
        short = "".join(f[1:] for f in flags if re.match(r"^-[A-Za-z]+$", f))
        positional = [a for a in args if not a.startswith("-")]

        if sub == "push":
            if ("--force" in flags or "--force-with-lease" in flags
                    or "--force-if-includes" in flags or "f" in short
                    or "--delete" in flags or "d" in short
                    or any(p.startswith("+") for p in positional)):
                deny("force/delete push")
        elif sub == "reset" and "--hard" in flags:
            deny("hard reset discards work")
        elif sub == "clean" and ("--force" in flags or "f" in short):
            deny("git clean deletes untracked files")
        elif sub == "branch":
            if "D" in short or ("--delete" in flags and "--force" in flags):
                deny("force branch delete")
        elif sub in ("checkout", "restore"):
            if positional and positional[-1] == ".":
                deny("bulk discard of working tree changes")
        elif sub == "stash":
            deny("stash is repo-wide and unsafe with worktrees")
        elif sub == "rebase":
            if "--continue" not in flags and "--skip" not in flags:
                deny("history rewrite while agents may hold refs (only --continue/--skip allowed)")
        elif sub == "commit" and "--amend" in flags:
            deny("history rewrite while agents may hold refs")
        elif sub == "worktree" and positional and positional[0] == "remove":
            if "--force" in flags or "f" in short:
                deny("forced worktree removal destroys uncommitted work; inspect and rescue first")

    elif prog == "rm":
        rm_flags = [t for t in tokens[1:] if t.startswith("-")]
        rm_short = "".join(f[1:] for f in rm_flags if re.match(r"^-[A-Za-z]+$", f))
        recursive = "r" in rm_short or "R" in rm_short or "--recursive" in rm_flags
        force = "f" in rm_short or "--force" in rm_flags
        targets = [t for t in tokens[1:] if not t.startswith("-")]
        if recursive and force and any(
                t in ("/", "~", "$HOME", "..", ".") or t.startswith(("/", "~"))
                for t in targets):
            deny("recursive force delete outside the working tree")

    elif prog == "dd":
        if any(t.startswith("of=/dev/") for t in tokens[1:]):
            deny("raw write to a device")

allow()
