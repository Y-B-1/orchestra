#!/usr/bin/env python3
"""Claude PreToolUse(Agent) + SubagentStart: nesting AND matrix enforcement.

IDENTITY, NOT LABEL (repaired 2026-08-31, wave D2). This hook used to key on
`agent_type` ALONE. A captured live PreToolUse payload from inside a worker
(Claude Code, 2026-08-31) carries BOTH:

    "agent_id": "a4e8098b04426409c",   ← the identity: present for EVERY worker
    "agent_type": "builder",           ← the label: only when a NAMED agent
                                         definition was dispatched

`agent_id` is the load-bearing field. A sub-agent launched without a named
definition — a bare Task, or any future dispatch shape that does not resolve to
a file in .claude/agents/ — has an EMPTY agent_type, and the old hook read that
as "this is the main session" and ALLOWED the nest. The deny is now the UNION:
any worker identity at all closes the door. Both spellings are accepted on each
field, matching the Cursor twin (.cursor/hooks/block-nested-subagents.py).

The main session carries neither field.

Fails OPEN on parse surprises. An Agent/Task call whose payload carries NO
identity field at all is logged to .orchestra/hook-failures.log — that is the
signature of a schema change silently disarming this guard, and it is the one
thing a hook cannot detect about itself after the fact.

MODEL-GUARD (added 2026-09-02, ruling docs/plans/RULINGS-2026-09-02-founder.md
U11). Two more checks, both scoped to a dispatch FROM the main session (a
worker dispatch is already denied above, before either of these run):

  1. `tool_input` carrying a `model` or `effort` key AT ALL is denied — "YAML
     owns the matrix". This is how ~40 agents ran at the wrong tier/effort on 2026-08-31:
     a dispatch-time override on top of correct frontmatter.
  2. A `subagent_type` whose OWN agent file's frontmatter has drifted off the
     matrix (encoded below, and in `docs/orchestra/claude-models.md`) is
     denied — belt-and-braces alongside any host-side matrix test, which only
     catches drift at test time, not dispatch time.

Same escape hatch as the model lock: `ORCHESTRA_MODEL_UNLOCK=1` in the PROCESS
environment. It bypasses the two MODEL-GUARD checks only — the nesting ban
above is never bypassable by it.

SubagentStart ALSO fires for Workflow-spawned agents, per the official hooks
reference (2026-09-02) — but that event does NOT document blocking support,
unlike PreToolUse. So for SubagentStart this hook can only WARN (loud
`additionalContext`, plus a `.orchestra/hook-failures.log` line), never deny —
said plainly rather than pretended otherwise. The real lock for `Agent`/`Task`
dispatches is the PreToolUse path above, which does deny.
"""
import json
import os
import re
import sys

MATRIX = {
    # FALLBACK 2026-09-04 (U24): Fable usage EXHAUSTED (HTTP 429). The matrix's own
    # escape — judgement roles fall back to the strongest available model. RESTORE
    # these seven to claude-fable-5 when Fable resets. Build ceiling is unchanged.
    "architect": ("claude-opus-5", "low"),
    "planner": ("claude-opus-5", "low"),
    "red-teamer": ("claude-opus-5", "low"),
    "auditor": ("claude-opus-5", "low"),
    "reviewer": ("claude-opus-5", "low"),
    "pr-reviewer": ("claude-opus-5", "low"),
    "builder-max": ("claude-opus-5", "medium"),  # U15: repair valve, the one Opus
    "builder": ("claude-sonnet-5", "medium"),
    "gatekeeper": ("claude-sonnet-5", "medium"),
    "janitor": ("claude-sonnet-5", "medium"),
    "releaser": ("claude-sonnet-5", "medium"),
    "researcher": ("claude-sonnet-5", "medium"),
    "scout": ("claude-sonnet-5", "low"),
}

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def log_failure(note):
    try:
        os.makedirs(os.path.join(ROOT, ".orchestra"), exist_ok=True)
        with open(os.path.join(ROOT, ".orchestra", "hook-failures.log"), "a") as f:
            f.write(f"orchestra-block-nested: {note}\n")
    except Exception:
        pass


def decide(decision, reason=None, event="PreToolUse"):
    out = {
        "hookSpecificOutput": {
            "hookEventName": event,
            "permissionDecision": decision,
        }
    }
    if reason:
        out["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(out))
    sys.exit(0)


def agent_frontmatter(role):
    """(model, effort) declared in .claude/agents/<role>.md, or None if the
    file is missing/unparseable — never fabricate a value to compare against."""
    path = os.path.join(ROOT, ".claude", "agents", f"{role}.md")
    try:
        with open(path) as f:
            head = f.read(2000)
    except Exception:
        return None
    m = re.search(r"^model:\s*(\S+)", head, re.MULTILINE)
    e = re.search(r"^effort:\s*(\S+)", head, re.MULTILINE)
    if not m or not e:
        return None
    return (m.group(1), e.group(1))


def unlocked():
    return os.environ.get("ORCHESTRA_MODEL_UNLOCK") == "1"


try:
    payload = json.load(sys.stdin)
except Exception:
    log_failure("stdin parse failure")
    decide("allow")

event = payload.get("hook_event_name") or payload.get("hookEventName") or "PreToolUse"
tool = payload.get("tool_name") or payload.get("toolName") or ""

# The identity channels, in order of authority. agent_id is present for every
# worker; agent_type only for a named one. Either one means "not the main session".
worker_id = payload.get("agent_id") or payload.get("agentId") or ""
worker_type = payload.get("agent_type") or payload.get("agentType") or ""

if event == "SubagentStart":
    # Best-effort, non-blocking: SubagentStart does not document a deny path.
    # Say so plainly rather than silently doing nothing.
    if not unlocked():
        role = worker_type
        expected = MATRIX.get(role)
        got_model = payload.get("model")
        got_effort_level = (payload.get("effort") or {}).get("level") \
            if isinstance(payload.get("effort"), dict) else None
        mismatch = expected and (
            (got_model and got_model != expected[0])
            or (got_effort_level and got_effort_level != expected[1])
        )
        if mismatch:
            msg = (
                f"MODEL-GUARD WARNING (cannot deny on SubagentStart): "
                f"role {role!r} spawned as model={got_model!r} "
                f"effort={got_effort_level!r}, matrix expects {expected}. "
                f"A Workflow agent() override was not caught by the "
                f"PreToolUse(Agent) lock."
            )
            log_failure(msg)
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "SubagentStart",
                    "additionalContext": msg,
                }
            }))
            sys.exit(0)
    print("{}")
    sys.exit(0)

if tool in ("Agent", "Task"):
    if worker_id or worker_type:
        decide(
            "deny",
            "Orchestra policy: sub-agents must not spawn sub-agents. All fan-out "
            "belongs to the orchestrator (main session). Finish your brief and report back.",
        )
    if "agent_id" not in payload and "agentId" not in payload:
        # Neither identity field is even PRESENT on an Agent dispatch. Every
        # payload we have captured carries agent_id inside a worker and omits it
        # in the main session, so absence is expected in the main session — but
        # if that ever stops being true this guard is disarmed and silent.
        log_failure(
            "Agent dispatch payload carried no agent_id key — main session, or a "
            "schema change has disarmed this hook; re-capture a worker payload"
        )

    if not unlocked():
        tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
        overridden = [k for k in ("model", "effort") if k in tool_input]
        if overridden:
            decide(
                "deny",
                f"MODEL-GUARD (ruling 2026-09-02, U11): YAML owns the matrix — a "
                f"dispatch must not override {', '.join(overridden)}. Fix the "
                f"agent's frontmatter in .claude/agents/, not the dispatch call. "
                f"Escape hatch: ORCHESTRA_MODEL_UNLOCK=1 in the process environment.",
            )

        subagent_type = (
            tool_input.get("subagent_type")
            or tool_input.get("subagentType")
            or tool_input.get("agent_type")
        )
        if subagent_type and subagent_type in MATRIX:
            found = agent_frontmatter(subagent_type)
            if found and found != MATRIX[subagent_type]:
                decide(
                    "deny",
                    f"MODEL-GUARD (ruling 2026-09-02, U11): "
                    f".claude/agents/{subagent_type}.md is off-matrix "
                    f"(frontmatter {found}, matrix expects {MATRIX[subagent_type]}). "
                    f"Fix the frontmatter before dispatching. Escape hatch: "
                    f"ORCHESTRA_MODEL_UNLOCK=1 in the process environment.",
                )
            elif found is None:
                log_failure(
                    f"could not read frontmatter for subagent_type={subagent_type!r}"
                )

decide("allow")
