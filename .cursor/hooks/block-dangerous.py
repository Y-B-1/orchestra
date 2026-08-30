#!/usr/bin/env python3
"""Guardrail hook: Cursor beforeShellExecution and Claude PreToolUse (Bash).

Detects the harness from the payload (or ORCHESTRA_HOOK_RUNTIME=claude).

Denies destructive commands. Never returns ask (no human click). Protected-branch
landings (plain git, gh, az repos, glab) and declared deploy commands are allow
only when pr-reviewer CLEAN is recorded in state.json (reviews.pr) together with a
matching gates.last_green_hash — including headless (ralph / overnight). Otherwise
deny. server_side_gate true allows host-mediated PR completion. Denies protected
landings while the recorded green-gate hash differs from HEAD, unless the host
enforces the gate itself.

Host never-merge rails (block-pr-merge.sh) are stripped at install. Full e2e is not
a merge precondition.

Honest contract: this is a tripwire against accidents and first-order drift, not a
wall against adversarial evasion. Fails OPEN on parse surprises so a hook bug
cannot brick the session — but every fail-open appends to
.orchestra/hook-failures.log, which sessionStart and the janitor surface.
Pair with failClosed: true so crash/timeout/invalid JSON blocks the command.
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


def headless():
    """True in cloud agent / CI. The hook never returns ask; headless still
    matters for gate_fresh fail-closed when state.json is missing.

    Override explicitly with "headless": true|false in .orchestra/delivery.json.
    """
    declared = delivery().get("headless", "auto")
    if declared is not True and declared is not False:
        markers = ("CURSOR_CLOUD_AGENT", "CURSOR_BACKGROUND_AGENT", "CURSOR_AGENT_ID",
                   "CI", "BUILD_BUILDID", "GITHUB_ACTIONS", "TF_BUILD")
        return any(os.environ.get(m) for m in markers)
    return declared


RUNTIME = ["cursor"]


def is_claude_payload(payload):
    return bool(
        payload.get("hook_event_name")
        or payload.get("hookEventName")
        or payload.get("tool_input")
        or os.environ.get("ORCHESTRA_HOOK_RUNTIME") == "claude"
    )


def respond(permission, reason=None):
    if permission == "ask":
        # Belt: this hook must never surface a human click.
        permission = "deny"
        reason = (f"{reason} — Orchestra does not ask; land/deploy requires "
                  "pr-reviewer CLEAN + matching last_green_hash")
    if RUNTIME[0] == "claude":
        decision = "allow" if permission == "allow" else "deny"
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
            }
        }
        if reason:
            out["hookSpecificOutput"]["permissionDecisionReason"] = (
                f"Orchestra guardrail [{decision}]: {reason}"
            )
        print(json.dumps(out))
        sys.exit(0)
    out = {"permission": permission}
    if reason:
        out["user_message"] = f"Orchestra guardrail [{permission}]: {reason}"
        out["agent_message"] = (f"The orchestra guardrail hook returned '{permission}' ({reason}). "
                                "Do not retry variants; follow the release process.")
    print(json.dumps(out))
    sys.exit(0)


try:
    payload = json.load(sys.stdin)
    if is_claude_payload(payload):
        RUNTIME[0] = "claude"
    cmd = (
        payload.get("command")
        or (payload.get("tool_input") or {}).get("command")
        or ""
    )
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


def load_state():
    try:
        with open(".orchestra/state.json") as f:
            return json.load(f)
    except Exception:
        return None


def gate_fresh():
    """True when state.json records a green gate at the current HEAD (or check impossible).

    Returns None (no opinion) when the host enforces the gate itself — an Azure DevOps
    branch policy or equivalent builds the preview merge commit, which is a stronger
    guarantee than a locally recorded hash.
    """
    if delivery().get("server_side_gate"):
        return None
    try:
        state = load_state()
        if state is None:
            return False if headless() else None
        gate = (state.get("gates") or {}).get("last_green_hash", "")
        if not gate:
            # No record. Locally that means "no opinion"; in a cloud VM it means the
            # record could not travel (state.json is gitignored), so fail CLOSED —
            # a headless landing with no provable gate is exactly what we must stop.
            return False if headless() else None
        head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                              text=True, timeout=5).stdout.strip()
        return head.startswith(gate) or gate.startswith(head)
    except Exception:
        return None


def pr_review_authorized():
    """pr-reviewer CLEAN + fast-gate hash at HEAD is merge authorization.

    The releaser may land (including headless / ralph). Full e2e is not a
    precondition. Direct force-push stays deny regardless.
    """
    if gate_fresh() is not True:
        return False
    state = load_state() or {}
    return (state.get("reviews") or {}).get("pr") == "CLEAN"


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
    """Deny/allow rules over one command's tokens. Recurses into interpreter -c strings."""
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

    # Deploy commands declared per repo: CLEAN+fresh allows; otherwise deny.
    for pat in delivery().get("deploy_commands", []):
        try:
            if re.search(pat, " ".join(tokens)):
                if pr_review_authorized():
                    respond("allow")
                respond("deny", f"declared deploy command ({pat}) without pr-reviewer CLEAN + matching gate hash")
        except re.error:
            log_failure(f"bad deploy_commands pattern: {pat}")

    # Host CLIs that can land code on a protected branch. Provider-agnostic:
    # GitHub (gh), Azure DevOps (az repos), GitLab (glab).
    if prog in ("gh", "az", "glab"):
        joined = " ".join(tokens)
        lands = (
            re.search(r"\bpr\s+merge\b", joined)                      # gh pr merge
            or re.search(r"\bapi\b.*\bmerges?\b", joined)             # gh api …/merges
            or re.search(r"\bmr\s+merge\b", joined)                   # glab mr merge
            or (re.search(r"\brepos\s+pr\b", joined)                  # az repos pr …
                and re.search(r"status\s+completed|--auto-complete\s+true|--complete\s+true", joined))
        )
        if lands:
            # Host-mediated landing: when the host enforces the gate itself (branch
            # policy / required checks), it will refuse a PR whose checks are red.
            # That is a stronger gate than ours, and it is the recommended cloud path,
            # so it stays allowed even headless. Direct pushes below do NOT get this.
            if delivery().get("server_side_gate"):
                respond("allow")
            if gate_fresh() is False:
                respond("deny", "PR/MR completion while the recorded green-gate hash differs from "
                                "HEAD — re-run the fast gate first, or enable server_side_gate and "
                                "let the host's branch policy be the gate of record")
            if pr_review_authorized():
                respond("allow")
            respond("deny", f"landing a PR/MR via {prog} without pr-reviewer CLEAN + matching gate hash")
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
            if pr_review_authorized():
                respond("allow")
            respond("deny", f"push to protected branch ({', '.join(sorted(targets & PROTECTED))}) "
                            "without pr-reviewer CLEAN + matching gate hash")
        elif sub == "merge" and current_branch() in PROTECTED:
            if gate_fresh() is False:
                respond("deny", "merge into protected branch while the recorded green-gate hash "
                                "differs from HEAD — re-run the fast gate first")
            if pr_review_authorized():
                respond("allow")
            respond("deny", f"merge into protected branch ({current_branch()}) "
                            "without pr-reviewer CLEAN + matching gate hash")
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
