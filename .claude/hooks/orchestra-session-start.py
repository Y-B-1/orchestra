#!/usr/bin/env python3
"""Claude SessionStart: heal charter/memory, remind the main session to route.

Workers get no orchestrator identity (see the WHO IS THIS? note below). The main
session is pointed at the PROJECT skill, `.claude/skills/orchestrator/`.

THIS HOOK IS NO LONGER THE ONLY CHANNEL, and that is the point. Until 2026-09-01
it was: the skill lived under `.cursor/skills/`, which Claude Code does not scan,
so the single sentence injected here was all that told a session to route — and a
session skipped it for an entire run. The skill now lives under `.claude/skills/`
and carries a model-invocable `description`, so it is selected on its own merits.
This message is belt-and-braces.
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
os.chdir(root)

try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}


def heal():
    """Run the native heal module. Returns a warning string, or None on success.

    NARROWED SWALLOW (R3, 2026-09-01): a missing/broken heal module used to
    vanish inside a bare `try/except: pass` around the caller. A healer that
    fails quietly is worse than none, so the failure now surfaces as a visible
    line in `additionalContext` instead of being swallowed.
    """
    path = os.path.join(root, ".claude", "hooks", "heal-orchestra-docs.py")
    try:
        spec = importlib.util.spec_from_file_location("heal_orchestra_docs", path)
        if spec is None or spec.loader is None:
            return f"heal module missing at {path}"
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        if hasattr(mod, "heal_agents"):
            mod.heal_agents()
        if hasattr(mod, "heal_memory"):
            mod.heal_memory()
    except Exception as e:
        return f"heal failed: {type(e).__name__}"
    return None


def seed_state():
    dst = os.path.join(".orchestra", "state.json")
    src = os.path.join("docs", "orchestra", "state.example.json")
    if os.path.isfile(dst) or not os.path.isfile(src):
        return
    os.makedirs(".orchestra", exist_ok=True)
    with open(src) as f:
        body = f.read()
    with open(dst, "w") as f:
        f.write(body if body.endswith("\n") else body + "\n")


heal_warning = None
try:
    heal_warning = heal()
    seed_state()
except Exception as e:
    heal_warning = f"heal/seed error: {type(e).__name__}"


# Plan Part 7 item 3: `.orchestra/package-version` records the Orchestra commit
# this repo was installed from. A fork's own `.claude/agents/` and
# `.claude/skills/orchestrator/` can drift ahead of it (Section C — the
# portable-parts push to an upstream checkout). Print the drift count so
# that push is prompted at every batch close instead of forgotten.
#
# Host-neutral by design: no path is hardcoded here. Set
# ORCHESTRA_UPSTREAM_CHECKOUT to the sibling checkout's path; when it is
# unset (or does not exist), the comparison is skipped with one line and the
# session continues clean.
DRIFT_PATHS = (".claude/agents", ".claude/skills/orchestrator")


def upstream_drift():
    """FEASIBILITY FIRST: never hard-depend on the sibling checkout existing —
    a fresh clone, another machine, or CI will not have it. Skip with one line
    and exit clean rather than fail the session over an optional comparison."""
    sib = os.environ.get("ORCHESTRA_UPSTREAM_CHECKOUT", "")
    if not sib or not os.path.isdir(sib):
        return f"[upstream-drift] skipped: sibling checkout not found at {sib or '(ORCHESTRA_UPSTREAM_CHECKOUT unset)'}"
    try:
        n = 0
        for rel_dir in DRIFT_PATHS:
            local_dir = os.path.join(root, rel_dir)
            if not os.path.isdir(local_dir):
                continue
            for dirpath, _dirs, files in os.walk(local_dir):
                for fname in files:
                    local_path = os.path.join(dirpath, fname)
                    rel = os.path.relpath(local_path, root)
                    sib_path = os.path.join(sib, rel)
                    try:
                        with open(local_path, "rb") as f:
                            local_bytes = f.read()
                    except Exception:
                        continue
                    if not os.path.isfile(sib_path):
                        n += 1
                        continue
                    with open(sib_path, "rb") as f:
                        sib_bytes = f.read()
                    if local_bytes != sib_bytes:
                        n += 1
        return f"[upstream-drift] Orchestra fork ahead of upstream by {n} files"
    except Exception as e:
        return f"[upstream-drift] skipped: {type(e).__name__}"


# Plan Part 8 item 4 (the doctor-reminder half). RESEARCH pinned v2.1.233 at
# authoring time; the stamp is seeded with whatever `claude --version` reports
# on first write. `.orchestra/` is gitignored, so the stamp lives in
# `docs/orchestra/` where a version bump is a visible, reviewable diff.
CLAUDE_VERSION_STAMP = os.path.join("docs", "orchestra", "claude-version.stamp")


def doctor_reminder():
    stamp_path = os.path.join(root, CLAUDE_VERSION_STAMP)
    try:
        with open(stamp_path) as f:
            stamped = f.read().strip()
    except Exception:
        return f"[doctor-reminder] skipped: no stamp at {CLAUDE_VERSION_STAMP}"
    if not shutil.which("claude"):
        return "[doctor-reminder] skipped: `claude` not on PATH"
    try:
        out = subprocess.run(
            ["claude", "--version"], capture_output=True, text=True, timeout=5
        ).stdout
    except Exception as e:
        return f"[doctor-reminder] skipped: claude --version failed ({type(e).__name__})"
    m = re.search(r"\d+\.\d+\.\d+", out)
    if not m:
        return "[doctor-reminder] skipped: could not parse claude --version output"
    current = m.group(0)
    if current == stamped:
        return None
    return (
        f"Claude Code version changed since {stamped} (now {current}) — "
        "run `claude doctor` and do the manual context pass"
    )


def routing_context():
    """Inject the routing constitution verbatim (R1) — the deterministic half
    of routing. Missing/empty is never a silent no-op (R2): it reddens loudly
    so a broken channel is visible instead of quietly routing nobody."""
    path = os.path.join(root, ".claude", "hooks", "routing-context.md")
    try:
        with open(path) as f:
            text = f.read().strip()
    except Exception:
        text = ""
    if not text:
        return f"ROUTING-CONTEXT MISSING: {path} is missing or empty."
    return text


def host_routing_context():
    """Optional per-host addendum, injected verbatim after the package block.
    Absent is the normal case — most hosts carry no host-specific routing
    text — so a missing file is silent, never a warning."""
    path = os.path.join(root, ".claude", "hooks", "routing-context.host.md")
    try:
        with open(path) as f:
            text = f.read().strip()
    except Exception:
        return None
    return text or None

# WHO IS THIS? The same two channels `orchestra-block-nested.py` keys on, and for
# the same reason it was fixed on 2026-08-31: `agent_type` is the LABEL and is
# present only for a worker launched from a named definition in `.claude/agents/`,
# while `agent_id` is the IDENTITY and is present for EVERY worker. Reading the
# label alone made an unnamed sub-agent look like the main session — which here
# meant injecting the ORCHESTRATOR identity block into a worker and telling it to
# dispatch other agents. Either field being present means "not the main session".
worker = (
    payload.get("agent_id")
    or payload.get("agentId")
    or payload.get("agent_type")
    or payload.get("agentType")
    or ""
)
if worker:
    print("{}")
    sys.exit(0)

# WHY THE OLD "Do not add `.claude/skills/orchestrator/`" SENTENCE EXISTED, and why
# it is gone (2026-09-01). It was a MIRROR-DRIFT rule, not a routing rule: a second
# hand-maintained copy of the orchestrator under `.claude/` would drift silently
# against the `.cursor/` one, which is exactly how `docs/CONSTITUTION.md` rotted
# here until it was retired to a pointer stub. The ban bought that safety at the
# price of the skill being invisible to Claude Code, which scans `.claude/skills/`
# and never `.cursor/skills/` — so routing depended on a session reading THIS
# sentence, and a session skipped it.
#
# The source/mirror direction removes the tradeoff instead of choosing a side.
# `.claude/skills/orchestrator/` is now the SOURCE and `.cursor/` is GENERATED from
# it (the convention CLAUDE.md already states for `.claude/rules/*.md`), so there is
# no second hand-maintained copy to drift and drift is a red build, not a silence.
# Do not restore the ban: it would re-hide the skill from the session it governs.
ctx = (
    "Orchestra main session (Claude Code). Load the `orchestrator` skill — "
    "`.claude/skills/orchestrator/SKILL.md` — and route via its `references/flow.json`, "
    "read one state at a time with `scripts/flow-state.py`. Workers: `.claude/agents/`. "
    "Models: `docs/orchestra/claude-models.md`. After intake the only user-facing stop "
    "is unanswered frontier questions. Maximize parallelism: dispatch every unblocked "
    "ticket whose files do not overlap, in one message — including current waves from "
    "independent plans. Do not write product code when a builder can."
)

# R1/R2: inject the routing constitution itself (deterministic), not a pointer.
# The optional host addendum (`routing-context.host.md`) follows the package
# block verbatim when present; a host with none gets no marker at all.
parts = [ctx, routing_context()]
host_ctx = host_routing_context()
if host_ctx:
    parts.append(host_ctx)
if heal_warning:
    parts.append(f"[heal] {heal_warning}")
parts.append(upstream_drift())
doctor_warning = doctor_reminder()
if doctor_warning:
    parts.append(doctor_warning)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n\n".join(parts),
    }
}))
