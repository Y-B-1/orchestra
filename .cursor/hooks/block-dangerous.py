#!/usr/bin/env python3
"""Cursor beforeShellExecution hook: the deterministic floor.

Denies destructive commands; asks (Cursor surfaces the approval to the real user)
on pushes/merges to protected branches; denies protected pushes while the recorded
green-gate hash differs from HEAD.

Honest contract: this is a tripwire against accidents and first-order drift, not a
wall against adversarial evasion. Fails OPEN on parse surprises so a hook bug cannot
brick the session — but every fail-open appends to .orchestra/hook-failures.log,
which the janitor sweeps.
"""
import json
import os
import re
import shlex
import subprocess
import sys


def log_failure(note):
    try:
        os.makedirs(".orchestra", exist_ok=True)
        with open(".orchestra/hook-failures.log", "a") as f:
            f.write(f"block-dangerous: {note}\n")
    except Exception:
        pass


def respond(permission, reason=None):
    out = {"permission": permission}
    if reason:
        out["user_message"] = f"Orchestra guardrail [{permission}]: {reason}"
        out["agent_message"] = (f"The orchestra guardrail hook returned '{permission}' ({reason}). "
                                "Do not retry variants; follow the release process or ask the user.")
    print(json.dumps(out))
    sys.exit(0)


try:
    payload = json.load(sys.stdin)
    cmd = payload.get("command", "") or ""
except Exception:
    log_failure("stdin parse failure")
    respond("allow")


def delivery():
    try:
        with open(".orchestra/delivery.json") as f:
            return json.load(f)
    except Exception:
        return {}


PROTECTED = set(delivery().get("protected_branches", ["main", "master"]))
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--exec-path", "--namespace"}


def current_branch():
    try:
        r = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:
        return ""


def gate_fresh():
    """True when state.json records a green gate at the current HEAD (or check impossible)."""
    try:
        with open(".orchestra/state.json") as f:
            state = json.load(f)
        gate = (state.get("gates") or {}).get("last_green_hash", "")
        if not gate:
            return None
        head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                              text=True, timeout=5).stdout.strip()
        return head.startswith(gate) or gate.startswith(head)
    except Exception:
        return None


def analyze_git(tokens):
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


def check_tokens(tokens):
    """Deny/ask rules over one command's tokens. Recurses into interpreter -c strings."""
    # Strip wrapper layers to a fixpoint: VAR= assignments, sudo/command/env/nohup,
    # and env's own short flags — so `sudo env CI=1 git push -f` still classifies.
    while tokens:
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0]):
            tokens = tokens[1:]
        elif tokens[0] in ("sudo", "command", "nohup"):
            tokens = tokens[1:]
        elif tokens[0] == "env":
            tokens = tokens[1:]
            while tokens and (tokens[0] in ("-i",) or tokens[0].startswith("-u")
                              or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0])):
                tokens = tokens[2:] if tokens[0] == "-u" and len(tokens) > 1 else tokens[1:]
        else:
            break
    if not tokens:
        return

    prog = os.path.basename(tokens[0])

    # Deploy commands declared per repo get a user-facing ask.
    for pat in delivery().get("deploy_commands", []):
        try:
            if re.search(pat, " ".join(tokens)):
                respond("ask", f"declared deploy command ({pat})")
        except re.error:
            log_failure(f"bad deploy_commands pattern: {pat}")

    if prog == "gh":
        joined = " ".join(tokens)
        if re.search(r"\bpr\s+merge\b", joined) or re.search(r"\bapi\b.*\bmerges?\b", joined):
            if gate_fresh() is False:
                respond("deny", "PR merge while the recorded green-gate hash differs from HEAD — "
                                "re-run the fast gate first")
            respond("ask", "merging a PR into a protected branch via gh")
        return

    if prog in ("sh", "bash", "zsh", "dash", "ksh", "python", "python3", "node") :
        for j, t in enumerate(tokens):
            if t == "-c" and j + 1 < len(tokens):
                check_line(tokens[j + 1])
        return

    if prog == "git":
        sub, args = analyze_git(tokens)
        if sub is None:
            return
        flags = [a for a in args if a.startswith("-")]
        short = "".join(f[1:] for f in flags if re.match(r"^-[A-Za-z]+$", f))
        positional = [a for a in args if not a.startswith("-")]

        if sub == "push":
            if ("--force" in flags or "--force-with-lease" in flags or "--force-if-includes" in flags
                    or "f" in short or "--delete" in flags or "d" in short
                    or any(p.startswith("+") for p in positional)):
                respond("deny", "force/delete push")
            refspecs = positional[1:] if positional else []
            targets = {r.split(":")[-1] for r in refspecs} if refspecs else {current_branch()}
            if targets & PROTECTED:
                fresh = gate_fresh()
                if fresh is False:
                    respond("deny", "push to protected branch while the recorded green-gate hash "
                                    "differs from HEAD — re-run the fast gate first")
                respond("ask", f"push to protected branch ({', '.join(sorted(targets & PROTECTED))})")
        elif sub == "merge" and current_branch() in PROTECTED:
            respond("ask", f"merge into protected branch ({current_branch()})")
        elif sub == "reset" and "--hard" in flags:
            respond("deny", "hard reset discards work")
        elif sub == "clean" and ("--force" in flags or "f" in short):
            respond("deny", "git clean deletes untracked files")
        elif sub == "branch":
            if "D" in short or ("--delete" in flags and "--force" in flags):
                respond("deny", "force branch delete")
        elif sub in ("checkout", "restore"):
            if positional and positional[-1] == ".":
                respond("deny", "bulk discard of working tree changes")
        elif sub == "stash":
            respond("deny", "stash is repo-wide and unsafe with worktrees")
        elif sub == "rebase":
            if "--continue" not in flags and "--skip" not in flags:
                respond("deny", "history rewrite while agents may hold refs (only --continue/--skip allowed)")
        elif sub == "commit" and "--amend" in flags:
            respond("deny", "history rewrite while agents may hold refs")
        elif sub == "worktree" and positional and positional[0] == "remove":
            if "--force" in flags or "f" in short:
                respond("deny", "forced worktree removal destroys uncommitted work; inspect and rescue first")

    elif prog == "rm":
        rm_flags = [t for t in tokens[1:] if t.startswith("-")]
        rm_short = "".join(f[1:] for f in rm_flags if re.match(r"^-[A-Za-z]+$", f))
        recursive = "r" in rm_short or "R" in rm_short or "--recursive" in rm_flags
        force = "f" in rm_short or "--force" in rm_flags
        targets = [t for t in tokens[1:] if not t.startswith("-")]
        if recursive and force and any(
                t in ("/", "~", "$HOME", "..", ".")
                or t.startswith(("/", "~", "$HOME/", "${HOME}"))
                for t in targets):
            respond("deny", "recursive force delete outside the working tree")

    elif prog == "dd":
        if any(t.startswith("of=/dev/") for t in tokens[1:]):
            respond("deny", "raw write to a device")


def check_line(line):
    if re.search(r"\b(curl|wget)\b[^|;&]*\|\s*(ba|z|da|k)?sh\b", line):
        respond("deny", "piping a download into a shell")
    # Whole-line parse first: shlex keeps quoted payloads (with ; inside) intact,
    # so interpreter -c strings recurse correctly.
    try:
        check_tokens(shlex.split(line.strip()))
    except ValueError:
        pass
    for segment in re.split(r"(?:&&|\|\||;|\|)", line):
        try:
            tokens = shlex.split(segment.strip())
        except ValueError:
            tokens = segment.strip().split()
        check_tokens(tokens)


try:
    check_line(cmd)
except SystemExit:
    raise
except Exception as e:
    log_failure(f"analysis error: {type(e).__name__}")

respond("allow")
