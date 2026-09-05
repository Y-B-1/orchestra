#!/usr/bin/env python3
"""The ONE generator: .claude/ is source, .cursor/ is generated.

Ports the contract of two DEVOPS TypeScript scripts (scripts/sync-cursor-skills.ts,
scripts/generate-rule-skills.ts) into one Python script, because the package ships
no Node — `python3` is already required by install.sh.

Five generated families, in a fixed write order (a partial failure stays diagnosable):

  1. .claude/skills/orchestra-rails/SKILL.md   <- .claude/skills/orchestrator/references/standing-rails.md
  2. .claude/skills/rule-<name>/SKILL.md       <- .claude/rules/<name>.md (host files; none in the package)
  3. .cursor/agents/<role>.md                  <- .claude/agents/<role>.md + the rails body
  4. .cursor/rules/<name>.mdc                  <- .claude/rules/<name>.md
  5. .cursor/skills/<skill>/**                 <- .claude/skills/<skill>/** (byte mirror + banner)
  6. bb-plugin/skills/orchestra-rails/SKILL.md <- .claude/skills/orchestra-rails/SKILL.md (byte copy)

Steps 1-2 precede 3 because --check in step 3 resolves `skills:` names against what
steps 1-2 wrote. This script is the SOLE writer of every path above; it never reads a
generated file as input. A second run is a no-op.

Step 5 exception: a host may mirror a skill (or one file inside it) as a SYMLINK to
its `.claude/skills/` source instead of a generated copy — one file under two names
cannot drift, which is strictly stronger than a copy plus a drift check. A generated
path whose realpath already equals its source file's realpath (the file itself is a
symlink, or a parent directory is) is SATISFIED as-is: --check does not flag it, and
write mode never touches it — overwriting it would replace the symlink with a copy
and reintroduce whatever problem the symlink was avoiding (e.g. a tool that discovers
both trees seeing the same skill twice).

    python3 docs/orchestra/sync-agent-config.py            # write every generated path; print each one
    python3 docs/orchestra/sync-agent-config.py --check    # write nothing; exit 1 listing EVERY drift
    python3 docs/orchestra/sync-agent-config.py --root D   # operate on host D (install.sh passes $DST)
"""
from __future__ import annotations

import os
import re
import sys

REGEN_CMD = "python3 docs/orchestra/sync-agent-config.py"

# role -> (model, effort). The Claude-side pool (docs/orchestra/claude-models.md).
CLAUDE_MATRIX: dict[str, tuple[str, str]] = {
    "architect": ("claude-fable-5", "low"),
    "planner": ("claude-fable-5", "low"),
    "red-teamer": ("claude-fable-5", "low"),
    "auditor": ("claude-fable-5", "low"),
    "reviewer": ("claude-fable-5", "low"),
    "pr-reviewer": ("claude-fable-5", "low"),
    "builder-max": ("claude-opus-5", "medium"),
    "builder": ("claude-sonnet-5", "medium"),
    "gatekeeper": ("claude-sonnet-5", "medium"),
    "janitor": ("claude-sonnet-5", "medium"),
    "releaser": ("claude-sonnet-5", "medium"),
    "researcher": ("claude-sonnet-5", "medium"),
    "scout": ("claude-sonnet-5", "low"),
}

# role -> (model field text, force_default_model, readonly).
# CURSOR IS A WORKER RUNTIME AND ONLY A WORKER RUNTIME. It takes a dispatched
# ticket and executes its brief; it never routes, never fans out, never
# orchestrates. Only roles that are actually dispatched to Cursor appear here —
# a role with no entry generates no `.cursor/agents/<role>.md`, because an agent
# file for a role Cursor never receives is an orphan that drifts. Coordination
# roles (architect, planner, gatekeeper, janitor, releaser, pr-reviewer,
# builder-max, researcher, founder-mind) are deliberately absent.
CURSOR_MATRIX: dict[str, tuple[str, bool, bool]] = {
    "auditor": ("grok-4.6[effort=high]", False, True),
    "builder": ("grok-4.6[effort=high]", False, False),
    "red-teamer": ("grok-4.6[effort=xhigh]", False, True),
    "reviewer": ("grok-4.6[effort=high]", False, True),
    "scout": ("grok-4.6[effort=high]", False, True),
}

# Skills that must NEVER be mirrored into `.cursor/`. The orchestrator skill is
# the constitution of the main session; mirroring it hands Cursor the routing
# graph and makes "Cursor as orchestrator" one Custom Mode away. Enforced twice:
# step 5 skips it, and check arm 13 fails if the directory reappears.
CURSOR_EXCLUDED_SKILLS: set[str] = {"orchestrator"}

# Generated paths that must not exist at all. `orchestra-router.mdc` was the
# alwaysApply rule that told a Cursor main session to load the orchestrator and
# route; it is retired, not regenerated, and check arm 13 fails if it returns.
CURSOR_FORBIDDEN_PATHS: tuple[str, ...] = (
    ".cursor/skills/orchestrator",
    ".cursor/rules/orchestra-router.mdc",
)

# Files inside a mirrored skill dir that are Cursor-only sources: hand-maintained,
# exempt from both the write and the drift check.
CURSOR_ONLY_FILES: dict[str, list[str]] = {}

STANDING_RAILS_REL = os.path.join(".claude", "skills", "orchestrator", "references", "standing-rails.md")
ORCHESTRA_RAILS_DESCRIPTION = (
    "Standing rails every Orchestra worker follows: honest exit codes, who commits and how to "
    "stage, and where scratch files live. Preload this so a worker carries the discipline even "
    "when its own brief never restates it."
)


# ---------------------------------------------------------------------------
# Frontmatter helpers
# ---------------------------------------------------------------------------

def split_md(text: str) -> tuple[str, str]:
    """(frontmatter body without the --- fences, body after the second ---)."""
    m = re.match(r"^---\n([\s\S]*?)\n---\n([\s\S]*)$", text)
    if not m:
        return "", text
    return m.group(1), m.group(2)


def fm_field(front: str, key: str) -> str:
    m = re.search(rf"^{re.escape(key)}:\s*(.+)$", front, re.M)
    return m.group(1).strip() if m else ""


def fm_list(front: str, key: str) -> list[str]:
    """A YAML block-list value: `key:\\n  - a\\n  - b`. Quotes optional."""
    m = re.search(rf"^{re.escape(key)}:\s*\n((?:[ \t]*-\s*.+\n?)*)", front, re.M)
    if not m:
        return []
    items = re.findall(r"-\s*\"?([^\"\n]+?)\"?\s*$", m.group(1), re.M)
    return [i.strip() for i in items]


def strip_leading_blank(text: str) -> str:
    return re.sub(r"^\n+", "", text)


# ---------------------------------------------------------------------------
# Banners
# ---------------------------------------------------------------------------

def _html_banner(kind: str, source_rel: str) -> str:
    lines = [
        f"{kind} of {source_rel} — DO NOT EDIT THIS FILE.",
        "Edit the .claude source and regenerate:",
        f"  {REGEN_CMD}",
    ]
    return f"<!-- {lines[0]}\n" + "\n".join(f"     {l}" for l in lines[1:]) + " -->"


def _hash_banner(kind: str, source_rel: str) -> str:
    lines = [
        f"{kind} of {source_rel} — DO NOT EDIT THIS FILE.",
        "Edit the .claude source and regenerate:",
        f"  {REGEN_CMD}",
    ]
    return "\n".join(f"# {l}" for l in lines)


def skill_banner(source_rel: str) -> str:
    """Banner for a generated SKILL.md (rule-* / orchestra-rails)."""
    lines = [
        f"GENERATED from {source_rel} — DO NOT EDIT THIS FILE.",
        "Edit the rule source and regenerate:",
        f"  {REGEN_CMD}",
    ]
    return f"<!-- {lines[0]}\n" + "\n".join(f"     {l}" for l in lines[1:]) + " -->"


def mdc_banner(source_rel: str) -> str:
    return skill_banner(source_rel)


# ---------------------------------------------------------------------------
# Pure render functions (the seam the test asserts through)
# ---------------------------------------------------------------------------

def render_agent(role: str, claude_text: str, rails_body: str) -> str:
    """`.claude/agents/<role>.md` text + the rails body -> `.cursor/agents/<role>.md` text.

    Strips model/effort/skills/disallowedTools; keeps name/description; adds the
    Cursor model/force-default-model/readonly triple from CURSOR_MATRIX; appends the
    rails under a `## Standing rails` heading so Cursor workers, which cannot
    preload, still carry them inline.
    """
    front, body = split_md(claude_text)
    name = fm_field(front, "name") or role
    description = fm_field(front, "description")
    model_field, force, readonly = CURSOR_MATRIX[role]

    lines = ["---", f"name: {name}", f"description: {description}"]
    if readonly:
        lines.append("readonly: true")
    lines.append(f"model: {model_field}")
    if force:
        lines.append("force-default-model: true")
    lines.append("---")

    rails_block = "## Standing rails\n" + rails_body.rstrip("\n") + "\n"
    new_body = body.rstrip("\n") + "\n\n" + rails_block
    return "\n".join(lines) + "\n" + new_body


def render_mirror(rel_path: str, src_bytes: bytes) -> bytes:
    """The exact bytes the `.cursor/skills/**` mirror of one `.claude/skills/**` file
    must contain: a banner inserted after any frontmatter (.md) or after the
    shebang (.py / .sh); a plain byte copy otherwise (.json has no comment syntax)."""
    if rel_path.endswith(".md"):
        text = src_bytes.decode("utf-8")
        m = re.match(r"^(---\n[\s\S]*?\n---\n)([\s\S]*)$", text)
        head = m.group(1) if m else ""
        body = strip_leading_blank(m.group(2) if m else text)
        banner = _html_banner("GENERATED MIRROR", rel_path)
        return f"{head}{banner}\n\n{body}".encode("utf-8")
    if rel_path.endswith(".py") or rel_path.endswith(".sh"):
        text = src_bytes.decode("utf-8")
        m = re.match(r"^(#![^\n]*\n)([\s\S]*)$", text)
        shebang = m.group(1) if m else ""
        body = strip_leading_blank(m.group(2) if m else text)
        banner = _hash_banner("GENERATED MIRROR", rel_path)
        return f"{shebang}{banner}\n\n{body}".encode("utf-8")
    return src_bytes


def render_rule_skill(name: str, rule_text: str) -> tuple[str, str]:
    """`.claude/rules/<name>.md` text -> (generated SKILL.md text, generated .mdc text)."""
    source_rel = f".claude/rules/{name}.md"
    front, body = split_md(rule_text)
    body = strip_leading_blank(body)
    paths = fm_list(front, "paths")
    m = re.search(r"^#\s+(.+)$", body, re.M)
    heading = m.group(1).strip() if m else name

    description = (
        f"Path-scoped rule generated from {source_rel}, governing "
        f"{', '.join(paths) if paths else 'no declared paths'}. "
        f"{heading} — preload this so a worker carries the rule even when its own files "
        "never touch those paths."
    )
    skill_text = render_skill(f"rule-{name}", source_rel, description, body)

    mdc_lines = ["---", f'description: "{heading}"']
    if paths:
        globs = "[" + ", ".join(f"'{p}'" for p in paths) + "]"
        mdc_lines.append(f"globs: {globs}")
    mdc_lines.append("alwaysApply: false")
    mdc_lines.append("---")
    mdc_text = "\n".join(mdc_lines) + "\n\n" + mdc_banner(source_rel) + "\n\n" + body

    return skill_text, mdc_text


def render_skill(name: str, source_rel: str, description: str, body: str) -> str:
    """A generated `SKILL.md`: frontmatter (name, description) + banner + body verbatim."""
    return f"---\nname: {name}\ndescription: {description}\n---\n\n{skill_banner(source_rel)}\n\n{body}"


def orchestra_rails_source(root: str) -> dict | None:
    """The single `orchestra-rails` skill source, or None if the reference file is absent."""
    abs_path = os.path.join(root, STANDING_RAILS_REL)
    if not os.path.isfile(abs_path):
        return None
    with open(abs_path, encoding="utf-8") as f:
        body = f.read()
    return {
        "name": "orchestra-rails",
        "sourceRel": STANDING_RAILS_REL.replace(os.sep, "/"),
        "description": ORCHESTRA_RAILS_DESCRIPTION,
        "body": body,
    }


# ---------------------------------------------------------------------------
# Tree walking
# ---------------------------------------------------------------------------

def list_files(d: str) -> list[str]:
    out: list[str] = []
    for entry in sorted(os.listdir(d)):
        if entry.startswith("."):
            continue
        p = os.path.join(d, entry)
        if os.path.isdir(p):
            out.extend(os.path.join(entry, sub) for sub in list_files(p))
        else:
            out.append(entry)
    return sorted(out)


def rule_names(root: str) -> list[str]:
    d = os.path.join(root, ".claude", "rules")
    if not os.path.isdir(d):
        return []
    return sorted(f[:-3] for f in os.listdir(d) if f.endswith(".md"))


def agent_roles(root: str) -> list[str]:
    d = os.path.join(root, ".claude", "agents")
    if not os.path.isdir(d):
        return []
    return sorted(f[:-3] for f in os.listdir(d) if f.endswith(".md"))


def skill_names(root: str) -> list[str]:
    d = os.path.join(root, ".claude", "skills")
    if not os.path.isdir(d):
        return []
    return sorted(n for n in os.listdir(d) if not n.startswith(".") and os.path.isdir(os.path.join(d, n)))


# ---------------------------------------------------------------------------
# Write / check plan (both modes walk the same plan)
# ---------------------------------------------------------------------------

class Plan:
    def __init__(self) -> None:
        self.problems: list[str] = []
        self.written: list[str] = []
        self.notes: list[str] = []

    def emit(self, root: str, rel: str, content: bytes, write: bool, source_rel: str | None = None) -> None:
        abs_path = os.path.join(root, rel)
        if source_rel is not None:
            src_abs = os.path.join(root, source_rel)
            if os.path.exists(abs_path) and os.path.exists(src_abs):
                try:
                    if os.path.realpath(abs_path) == os.path.realpath(src_abs):
                        return  # symlink mirror (direct, or via a symlinked
                        # ancestor dir) resolving to the source file — satisfied.
                except OSError:
                    pass
        if os.path.isfile(abs_path):
            with open(abs_path, "rb") as f:
                current = f.read()
            if current == content:
                return
            problem = "differs from its generated content"
        else:
            problem = "is missing"
        if not write:
            self.problems.append(f"{rel}: {problem}")
            return
        os.makedirs(os.path.dirname(abs_path), exist_ok=True)
        with open(abs_path, "wb") as f:
            f.write(content)
        self.written.append(rel)
        print(f"wrote   {rel}")


def run(root: str, write: bool) -> Plan:
    plan = Plan()

    # Step 1: orchestra-rails skill.
    rails = orchestra_rails_source(root)
    if rails is None:
        plan.notes.append("note: no orchestrator/references/standing-rails.md — orchestra-rails skipped")
    else:
        skill_text = render_skill(rails["name"], rails["sourceRel"], rails["description"], rails["body"])
        plan.emit(root, os.path.join(".claude", "skills", "orchestra-rails", "SKILL.md"), skill_text.encode("utf-8"), write)

    # Step 2: rule-* skills + .mdc-ready sources (mdc itself is step 4).
    names = rule_names(root)
    if not names:
        print("rules: none found")
    rule_bodies: dict[str, str] = {}
    for name in names:
        with open(os.path.join(root, ".claude", "rules", f"{name}.md"), encoding="utf-8") as f:
            rule_bodies[name] = f.read()
        skill_text, _ = render_rule_skill(name, rule_bodies[name])
        plan.emit(root, os.path.join(".claude", "skills", f"rule-{name}", "SKILL.md"), skill_text.encode("utf-8"), write)
        if not fm_list(split_md(rule_bodies[name])[0], "paths"):
            plan.notes.append(f"note: rule {name} has no paths: — .mdc has no globs")

    # Step 3: .cursor/agents/*.md.
    rails_body = rails["body"] if rails is not None else ""
    for role in agent_roles(root):
        if role not in CURSOR_MATRIX:
            plan.notes.append(f"note: role {role} has no CURSOR_MATRIX entry — .cursor/agents/{role}.md skipped")
            continue
        with open(os.path.join(root, ".claude", "agents", f"{role}.md"), encoding="utf-8") as f:
            claude_text = f.read()
        cursor_text = render_agent(role, claude_text, rails_body)
        plan.emit(root, os.path.join(".cursor", "agents", f"{role}.md"), cursor_text.encode("utf-8"), write)

    # Step 4: .cursor/rules/*.mdc.
    for name in names:
        _, mdc_text = render_rule_skill(name, rule_bodies[name])
        plan.emit(root, os.path.join(".cursor", "rules", f"{name}.mdc"), mdc_text.encode("utf-8"), write)

    # Step 5: .cursor/skills/<skill>/** mirrors. Excluded skills are never mirrored.
    for skill in skill_names(root):
        if skill in CURSOR_EXCLUDED_SKILLS:
            plan.notes.append(f"note: skill {skill} is Cursor-excluded — no .cursor/skills/{skill} mirror")
            continue
        src_dir = os.path.join(root, ".claude", "skills", skill)
        dst_dir = os.path.join(root, ".cursor", "skills", skill)
        exempt = set(CURSOR_ONLY_FILES.get(skill, []))
        expected: dict[str, bytes] = {}
        for rel in list_files(src_dir):
            with open(os.path.join(src_dir, rel), "rb") as f:
                raw = f.read()
            source_rel = f".claude/skills/{skill}/{rel}".replace(os.sep, "/")
            content = render_mirror(source_rel, raw)
            expected[rel] = content

        for rel, content in expected.items():
            plan.emit(
                root,
                os.path.join(".cursor", "skills", skill, rel),
                content,
                write,
                source_rel=os.path.join(".claude", "skills", skill, rel),
            )

        # Cursor-only files (hand-maintained): note if missing.
        for rel in exempt:
            if not os.path.isfile(os.path.join(dst_dir, rel)):
                plan.notes.append(
                    f"note: .cursor/skills/{skill}/{rel} is missing — hand-maintained, not generated"
                )

        # Stale mirror output: a file the source no longer has.
        if os.path.isdir(dst_dir):
            for rel in list_files(dst_dir):
                if rel in expected or rel in exempt:
                    continue
                path = os.path.join(".cursor", "skills", skill, rel)
                if not write:
                    plan.problems.append(f"{path}: has no source and is not a Cursor-only file")
                    continue
                os.remove(os.path.join(root, path))
                print(f"removed {path}")

    # Step 6: the BB plugin ships the rails to every provider BB can drive.
    # Generated, so it can never drift from the .claude/ source.
    rails_md = os.path.join(root, ".claude", "skills", "orchestra-rails", "SKILL.md")
    if os.path.isfile(rails_md):
        with open(rails_md, "rb") as f:
            plan.emit(
                root,
                os.path.join("bb-plugin", "skills", "orchestra-rails", "SKILL.md"),
                f.read(),
                write,
                source_rel=os.path.join(".claude", "skills", "orchestra-rails", "SKILL.md"),
            )

    # Orphan census: a .cursor/skills/<dir> with no .claude/skills/<dir> source.
    known = set(skill_names(root)) - CURSOR_EXCLUDED_SKILLS
    cursor_skills_dir = os.path.join(root, ".cursor", "skills")
    if os.path.isdir(cursor_skills_dir):
        for entry in sorted(os.listdir(cursor_skills_dir)):
            if entry.startswith(".") or entry in known:
                continue
            if not os.path.isdir(os.path.join(cursor_skills_dir, entry)):
                continue
            plan.problems.append(f".cursor/skills/{entry}: has no .claude/skills source and is not a generated mirror")

    return plan


# ---------------------------------------------------------------------------
# Extra --check assertions over the SOURCE files (not generated-output drift)
# ---------------------------------------------------------------------------

def extra_checks(root: str) -> list[str]:
    problems: list[str] = []
    roles = agent_roles(root)
    agent_fronts: dict[str, str] = {}
    agent_bodies: dict[str, str] = {}
    agent_skills: dict[str, list[str]] = {}

    for role in roles:
        with open(os.path.join(root, ".claude", "agents", f"{role}.md"), encoding="utf-8") as f:
            front, body = split_md(f.read())
        agent_fronts[role] = front
        agent_bodies[role] = body
        agent_skills[role] = fm_list(front, "skills")

        # Arm 4: orchestrator in no agent's skills:.
        if "orchestrator" in agent_skills[role]:
            problems.append(f".claude/agents/{role}.md: skills: names orchestrator, which no agent may preload")

        # Arm 7: no isolation: worktree; every agent has disallowedTools: Agent.
        if fm_field(front, "isolation"):
            problems.append(f".claude/agents/{role}.md: sets isolation:, which no agent may")
        if "Agent" not in fm_field(front, "disallowedTools"):
            problems.append(f".claude/agents/{role}.md: disallowedTools does not contain Agent")

        # Arm 11: no Claude agent body contains the rails heading.
        if "## Standing rails" in body:
            problems.append(f".claude/agents/{role}.md: body already contains ## Standing rails")

        # Arm 12: every role in CLAUDE_MATRIX has the matching model/effort.
        if role in CLAUDE_MATRIX:
            want_model, want_effort = CLAUDE_MATRIX[role]
            got_model = fm_field(front, "model")
            got_effort = fm_field(front, "effort")
            if got_model != want_model or got_effort != want_effort:
                problems.append(
                    f".claude/agents/{role}.md: model/effort is {got_model}/{got_effort}, "
                    f"CLAUDE_MATRIX wants {want_model}/{want_effort}"
                )

        # Arm 2: every skills: name resolves to .claude/skills/<name>/SKILL.md.
        for skill in agent_skills[role]:
            skill_md = os.path.join(root, ".claude", "skills", skill, "SKILL.md")
            if not os.path.isfile(skill_md):
                problems.append(f".claude/agents/{role}.md: skills: names {skill}, which has no SKILL.md")

    # Arm 3: no preloaded skill (or the orchestrator skill) sets disable-model-invocation.
    preloaded = {"orchestrator"} | {s for names in agent_skills.values() for s in names}
    for skill in sorted(preloaded):
        skill_md = os.path.join(root, ".claude", "skills", skill, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue
        with open(skill_md, encoding="utf-8") as f:
            front, _ = split_md(f.read())
        if fm_field(front, "disable-model-invocation"):
            problems.append(f".claude/skills/{skill}/SKILL.md: preloaded skill sets disable-model-invocation")

    # Arm 6: every SKILL.md frontmatter starts at line 1.
    skills_dir = os.path.join(root, ".claude", "skills")
    if os.path.isdir(skills_dir):
        for skill in skill_names(root):
            skill_md = os.path.join(skills_dir, skill, "SKILL.md")
            if os.path.isfile(skill_md):
                with open(skill_md, encoding="utf-8") as f:
                    text = f.read()
                if not text.startswith("---\n"):
                    problems.append(f".claude/skills/{skill}/SKILL.md: frontmatter does not start on line 1")

        # Arm 13: Cursor carries no orchestrator surface. This is the mechanical
        # half of "Cursor is a worker runtime": the ruling is only real if a
        # regenerated tree cannot quietly grow the routing graph back.
        for rel in CURSOR_FORBIDDEN_PATHS:
            if os.path.exists(os.path.join(root, rel)):
                problems.append(
                    f"{rel}: exists — Cursor is a worker runtime and may carry no orchestrator surface"
                )

        # Arm 14: no .cursor/agents/<role>.md for a role outside CURSOR_MATRIX.
        cursor_agents = os.path.join(root, ".cursor", "agents")
        if os.path.isdir(cursor_agents):
            for entry in sorted(os.listdir(cursor_agents)):
                if not entry.endswith(".md"):
                    continue
                role = entry[:-3]
                if role not in CURSOR_MATRIX:
                    problems.append(
                        f".cursor/agents/{entry}: role {role} is not dispatched to Cursor — orphan agent file"
                    )

        # Arm 8: no .claude/skills/* entry is a symlink.
        for entry in sorted(os.listdir(skills_dir)):
            if entry.startswith("."):
                continue
            p = os.path.join(skills_dir, entry)
            if os.path.islink(p):
                problems.append(f".claude/skills/{entry}: is a symlink")

    return problems


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    check = "--check" in argv
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if "--root" in argv:
        idx = argv.index("--root") + 1
        if idx >= len(argv):
            print("usage: sync-agent-config.py [--check] [--root DIR]", file=sys.stderr)
            return 2
        root = os.path.abspath(argv[idx])

    plan = run(root, write=not check)
    for note in plan.notes:
        print(note)

    problems = list(plan.problems)
    if check:
        problems += extra_checks(root)

    for p in problems:
        print(f"DRIFT   {p}")

    if problems:
        print(f"\n{len(problems)} problem(s). Regenerate: {REGEN_CMD}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
