#!/usr/bin/env python3
"""Guardrail hook: Claude Code PreToolUse (Bash). Source of truth for the deny
logic; `.cursor/hooks/block-dangerous.py` is a thin adapter that imports
`check_command` from this file.

Denies destructive commands. Never returns ask (no human click). Protected-branch
landings (plain git, gh, az repos, glab) and declared deploy commands are allow
only when pr-reviewer CLEAN is recorded in state.json (reviews.pr) together with a
matching gates.last_green_hash — including headless (ralph / overnight). Otherwise
deny. server_side_gate true allows host-mediated PR completion. Denies protected
landings while the recorded green-gate hash differs from HEAD, unless the host
enforces the gate itself.

Honest contract: this is a tripwire against accidents and first-order drift, not a
wall against adversarial evasion. Fails OPEN on parse surprises so a hook bug
cannot brick the session — but every fail-open appends to
.orchestra/hook-failures.log, which sessionStart and the janitor surface.

Root resolution: every `.orchestra/` path is anchored to `CLAUDE_PROJECT_DIR`
(falling back to cwd when unset, e.g. under this file's own test) — never a bare
relative path, which would resolve against whatever cwd the harness happens to
have and silently stop seeing real state.
"""
import json
import os
import re
import shlex
import subprocess
import sys

# Set True in __main__ when the payload carries worker identity (agent_id/agentId).
# Module default False keeps the cursor adapter's bare check_command import working.
_IS_WORKER = False

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def orchestra_path(*parts):
    return os.path.join(ROOT, ".orchestra", *parts)


def log_failure(note):
    try:
        os.makedirs(orchestra_path(), exist_ok=True)
        with open(orchestra_path("hook-failures.log"), "a") as f:
            f.write(f"block-dangerous: {note}\n")
    except Exception:
        pass


def delivery():
    try:
        with open(orchestra_path("delivery.json")) as f:
            return json.load(f)
    except Exception:
        return {}


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
        with open(orchestra_path("state.json")) as f:
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
        if head.startswith(gate) or gate.startswith(head):
            return True
        # PR flow (U21, 2026-09-02): the gate runs at the PR branch's tip, which
        # is never this checkout's HEAD. Accept when the gated commit CONTAINS
        # HEAD — the merged-tree premise scripts/fastgate.sh enforces.
        anc = subprocess.run(["git", "merge-base", "--is-ancestor", head, gate],
                             capture_output=True, timeout=5)
        return anc.returncode == 0
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
    reviews = state.get("reviews") or {}
    if reviews.get("pr") != "CLEAN":
        return False
    # B3 (2026-09-04 plans-vs-built audit): a CLEAN that exists only as narrative is
    # unauditable. The pr-reviewer must have written a record FILE under
    # docs/orchestra/reviews/ and state.json must name it in reviews.pr_record.
    record = reviews.get("pr_record") or ""
    base = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if not record or not os.path.isfile(os.path.join(base, record)):
        return False
    return True


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
    """Deny/allow rules over one command's tokens. Returns a deny reason, or None
    to allow (and, for git, fall through to the caller's per-segment pass).
    Recurses into interpreter -c strings via check_line."""
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
        return None

    prog = os.path.basename(tokens[0])

    # Deploy commands declared per repo: CLEAN+fresh allows; otherwise deny.
    for pat in delivery().get("deploy_commands", []):
        try:
            if re.search(pat, " ".join(tokens)):
                if pr_review_authorized():
                    return None
                return f"declared deploy command ({pat}) without pr-reviewer CLEAN + matching gate hash"
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
                return None
            if gate_fresh() is False:
                return ("PR/MR completion while the recorded green-gate hash differs from "
                        "HEAD — re-run the fast gate first, or enable server_side_gate and "
                        "let the host's branch policy be the gate of record")
            if pr_review_authorized():
                return None
            return f"landing a PR/MR via {prog} without pr-reviewer CLEAN + matching gate hash"
        return None

    if prog in ("sh", "bash", "zsh", "dash", "ksh", "python", "python3", "node"):
        for j, t in enumerate(tokens):
            if t == "-c" and j + 1 < len(tokens):
                reason = check_line(tokens[j + 1])
                if reason:
                    return reason
        return None

    if prog == "git":
        sub, args = analyze_git(tokens)
        if sub is None:
            return None
        flags = [a for a in args if a.startswith("-")]
        short = "".join(f[1:] for f in flags if re.match(r"^-[A-Za-z]+$", f))
        positional = [a for a in args if not a.startswith("-")]

        if sub == "push":
            if ("--force" in flags or "--force-with-lease" in flags or "--force-if-includes" in flags
                    or "f" in short or "--delete" in flags or "d" in short
                    or any(p.startswith("+") for p in positional)):
                return "force/delete push"
            refspecs = positional[1:] if positional else []
            targets = {r.split(":")[-1] for r in refspecs} if refspecs else {current_branch()}
            landing = targets & PROTECTED
            # ONLY A LANDING NEEDS THE GATE (repaired 2026-08-31, wave D3). The
            # deny used to sit OUTSIDE this condition, so EVERY push was denied —
            # including `git push <remote> feature`, a non-protected branch —
            # with the tell-tale empty branch list "push to protected branch ()".
            # Pushes are unblocked, automated agent acts; only a protected target
            # is a landing. The protected set is the host's, from
            # `.orchestra/delivery.json`.
            #
            # A non-protected push falls through to None rather than a reason:
            # returning here would stop check_line's whole-line pass and leave
            # the rest of a compound command (a destructive verb chained after
            # "&&") never inspected.
            if landing:
                if gate_fresh() is False:
                    return ("push to protected branch while the recorded green-gate hash "
                            "differs from HEAD — re-run the fast gate first")
                if pr_review_authorized():
                    return None
                return (f"push to protected branch ({', '.join(sorted(landing))}) "
                        "without pr-reviewer CLEAN + matching gate hash")
        elif sub == "merge" and current_branch() in PROTECTED:
            if gate_fresh() is False:
                return ("merge into protected branch while the recorded green-gate hash "
                        "differs from HEAD — re-run the fast gate first")
            if pr_review_authorized():
                return None
            return (f"merge into protected branch ({current_branch()}) "
                    "without pr-reviewer CLEAN + matching gate hash")
        elif sub == "reset" and "--hard" in flags:
            return "hard reset discards work"
        elif sub == "clean" and ("--force" in flags or "f" in short):
            return "git clean deletes untracked files"
        elif sub == "branch":
            if "D" in short or ("--delete" in flags and "--force" in flags):
                return "force branch delete"
        elif sub in ("checkout", "restore"):
            if positional and positional[-1] == ".":
                return "bulk discard of working tree changes"
        elif sub == "stash":
            return "stash is repo-wide and unsafe with worktrees"
        elif sub == "rebase":
            if "--continue" not in flags and "--skip" not in flags:
                return "history rewrite while agents may hold refs (only --continue/--skip allowed)"
        elif sub == "commit" and "--amend" in flags:
            return "history rewrite while agents may hold refs"
        elif sub == "worktree":
            # A30 (enforced 2026-09-04, audit B4): worktrees are the ORCHESTRATOR's
            # instrument; a worker running any worktree subcommand recreates the
            # shared-ref-store hazards the ruling exists to prevent.
            if _IS_WORKER and positional and positional[0] in ("add", "remove", "prune", "move"):
                return "A30: workers never run git worktree commands — the orchestrator owns worktrees"
            if positional and positional[0] == "remove":
                if "--force" in flags or "f" in short:
                    return "forced worktree removal destroys uncommitted work; inspect and rescue first"
        return None

    if prog == "rm":
        rm_flags = [t for t in tokens[1:] if t.startswith("-")]
        rm_short = "".join(f[1:] for f in rm_flags if re.match(r"^-[A-Za-z]+$", f))
        recursive = "r" in rm_short or "R" in rm_short or "--recursive" in rm_flags
        force = "f" in rm_short or "--force" in rm_flags
        targets = [t for t in tokens[1:] if not t.startswith("-")]
        if recursive and force and any(
                t in ("/", "~", "$HOME", "..", ".")
                or t.startswith(("/", "~", "$HOME/", "${HOME}"))
                for t in targets):
            return "recursive force delete outside the working tree"
        return None

    if prog == "dd":
        if any(t.startswith("of=/dev/") for t in tokens[1:]):
            return "raw write to a device"
        return None

    return None


def check_line(line):
    if re.search(r"\b(curl|wget)\b[^|;&]*\|\s*(ba|z|da|k)?sh\b", line):
        return "piping a download into a shell"
    # Whole-line parse first: shlex keeps quoted payloads (with ; inside) intact,
    # so interpreter -c strings recurse correctly.
    try:
        reason = check_tokens(shlex.split(line.strip()))
        if reason:
            return reason
    except ValueError:
        pass
    for segment in re.split(r"(?:&&|\|\||;|\|)", line):
        try:
            tokens = shlex.split(segment.strip())
        except ValueError:
            tokens = segment.strip().split()
        reason = check_tokens(tokens)
        if reason:
            return reason
    return None


def check_command(cmd):
    """Public seam: a command string in, a deny reason out (None = allow)."""
    try:
        return check_line(cmd)
    except Exception as e:
        log_failure(f"analysis error: {type(e).__name__}")
        return None


if __name__ == "__main__":
    try:
        payload = json.load(sys.stdin)
        cmd = (payload.get("tool_input") or {}).get("command") or payload.get("command") or ""
        # Worker identity, same two channels orchestra-block-nested.py keys on.
        globals()["_IS_WORKER"] = bool(payload.get("agent_id") or payload.get("agentId"))
    except Exception:
        log_failure("stdin parse failure")
        cmd = None

    reason = check_command(cmd) if cmd is not None else None
    decision = "deny" if reason else "allow"
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        out["hookSpecificOutput"]["permissionDecisionReason"] = f"Orchestra guardrail [deny]: {reason}"
    print(json.dumps(out))
    sys.exit(0)
