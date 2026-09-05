#!/usr/bin/env python3
"""Generate the NON-CLAUDE runtime assets from the Claude sources.

⚠ THE MODEL MATRIX ROUTES WORK TO RUNTIMES THAT COULD NOT READ THE ROLE.
`docs/orchestra/orca-runtimes.json` sends builder, builder-frontend, scout and
researcher to OpenCode — but OpenCode never reads `.claude/agents/`
(RESEARCH-multi-cli-orchestration.md, Limitation 1: a child reads
`AGENTS.md`/`CLAUDE.md` and its OWN config, not Claude's). So the role brief
that makes a builder a builder reached exactly one of the four runtimes it is
dispatched to, and the audit finding f2 ("generators/checkers absent") was the
symptom.

WHAT THIS WRITES (every output is tracked in git; nothing here is hand-edited):

  .opencode/agents/<role>.md    one file per role whose chain has an `opencode`
                                step. Verified against opencode.ai/docs/agents
                                (2026-09-02): project agents live in
                                `.opencode/agents/`, the FILENAME is the agent
                                id, and the supported frontmatter is
                                `description` / `mode` / `model` / `temperature`
                                / `permission`. Body = the Claude role brief
                                verbatim, plus the rule files the Claude
                                `skills:` preload would have carried — that
                                preload does not travel, so the paths are named
                                and the worker is told to read them.

  .agents/skills/<name>/SKILL.md  the five rule-carrier skills, mirrored from
                                `.claude/skills/`. Verified against
                                opencode.ai/docs/skills (2026-09-02): OpenCode
                                loads `.opencode/skills/`, `.claude/skills/`
                                AND `.agents/skills/`; `.agents/` is the
                                runtime-neutral one, so it is the copy a future
                                runtime finds too.

  .cursor/agents/<role>.md      one file per role whose chain has a `cursor`
                                step — and ONLY those roles: a Cursor agent
                                file for a role never dispatched to Cursor is
                                an orphan that drifts (2026-09-03 audit found
                                8). Frontmatter is the Cursor grammar
                                (`name` / `description` / `model` /
                                `readonly`); the model is the first cursor
                                step's slug translated to the picker spelling,
                                and `worker-start --model` still overrides it
                                for fallback rungs (no `force-default-model`).
                                Body = the Claude role brief verbatim, plus
                                the carried-rules block, same as OpenCode.

  .codex/agents/<role>.toml     all seventeen Codex-native worker/lane roles.
                                Body = the Claude role body verbatim, followed
                                by exact startup reads for its neutral rule
                                carriers. Model and effort come from the
                                separate native contract, never Orca routes.

  .codex/AGENTS-NOTE.md         ownership and activation boundary for the
                                generated native Codex worker definitions.

USAGE
  python3 scripts/generate-runtimes.py            # write the assets
  python3 scripts/generate-runtimes.py --check    # exit 1 on any drift
  python3 scripts/generate-runtimes.py --out DIR  # write under DIR instead
                                                  # (same relative paths — this
                                                  # is what the drift test uses)

DETERMINISM IS THE CONTRACT. Sorted iteration, LF endings, one trailing
newline: `--out` into a temp dir must produce bytes identical to the tracked
tree, or `src/lib/orcaRuntimeAssets.test.ts` reddens.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RUNTIMES_JSON = os.path.join("docs", "orchestra", "orca-runtimes.json")
CODEX_MODELS_JSON = os.path.join("docs", "orchestra", "codex-models.json")
CLAUDE_AGENTS = os.path.join(".claude", "agents")
CLAUDE_SKILLS = os.path.join(".claude", "skills")

# The rule carriers that must exist for a non-Claude runtime too. Kept explicit
# rather than globbed: `react-doctor` and `orchestrator` are NOT mirrored here
# (the first is a drifted third copy this repo already argued about; the second
# is main-session-only and a worker must never load it).
RULE_CARRIER_SKILLS = (
    "orchestra-rails",
    "rule-e2e",
    "rule-engine-boundary",
    "rule-migrations",
    "rule-pipeline",
)

# Where a preloaded skill's real content lives, for a runtime that cannot
# preload it. Anything not listed falls back to the skill's own SKILL.md.
SKILL_SOURCE_PATHS = {
    "orchestra-rails": ".claude/skills/orchestrator/references/standing-rails.md",
}


def banner(sources: list[str]) -> str:
    src = " + ".join(sources)
    return (
        f"<!-- GENERATED from {src} — DO NOT EDIT THIS FILE.\n"
        f"     Regenerate: python3 scripts/generate-runtimes.py -->"
    )


def toml_banner(sources: list[str]) -> str:
    src = " + ".join(sources)
    return (
        f"# GENERATED from {src} - DO NOT EDIT THIS FILE.\n"
        "# Regenerate: python3 scripts/generate-runtimes.py"
    )


def read(root: str, rel: str) -> str:
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        return f.read()


def split_frontmatter(raw: str) -> tuple[dict[str, str], list[str], str]:
    """(scalar fields, `skills:` list, body). Enough YAML for these files.

    Deliberately not a YAML parser: the agent files are generated-adjacent and
    flat, and a dependency here would have to be installed in every runtime
    that runs the check.
    """
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", raw, re.DOTALL)
    if not m:
        return {}, [], raw
    fields: dict[str, str] = {}
    skills: list[str] = []
    in_skills = False
    for line in m.group(1).split("\n"):
        item = re.match(r"^\s+-\s*(\S.*)$", line)
        if in_skills and item:
            skills.append(item.group(1).strip())
            continue
        in_skills = False
        kv = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if not kv:
            continue
        key, value = kv.group(1), kv.group(2).strip()
        if key == "skills" and value == "":
            in_skills = True
            continue
        fields[key] = value
    return fields, skills, m.group(2)


def runtime_roles(runtimes: dict, runtime: str) -> list[tuple[str, dict]]:
    """(role, first step on `runtime`) for every role routed to it, sorted."""
    out = []
    for role, chain in sorted(runtimes["roles"].items()):
        for step in chain:
            if step.get("runtime") == runtime:
                out.append((role, step))
                break
    return out


def agent_source(root: str, role: str) -> str:
    """The `.claude/agents/*.md` a role's brief comes from.

    A VARIANT ROLE HAS NO FILE OF ITS OWN. `builder-frontend`, `builder-speed`
    and `builder-sensitive` are lanes of the builder in the model matrix, not
    separate roles — the matrix varies the runtime and model, never the brief.
    So the variant falls back to its base role's file, and the generated
    frontmatter says which lane it is.
    """
    exact = os.path.join(CLAUDE_AGENTS, f"{role}.md")
    if os.path.isfile(os.path.join(root, exact)):
        return exact
    base = role.split("-")[0]
    fallback = os.path.join(CLAUDE_AGENTS, f"{base}.md")
    if os.path.isfile(os.path.join(root, fallback)):
        return fallback
    raise SystemExit(
        f"no .claude/agents source for role '{role}' (tried {exact} and {fallback}). "
        f"Add the agent file, or take the role out of {RUNTIMES_JSON}."
    )


def carried_rules(root: str, skills: list[str]) -> list[str]:
    """The source path behind each preloaded skill, in frontmatter order."""
    paths = []
    for name in skills:
        rel = SKILL_SOURCE_PATHS.get(name)
        if rel is None:
            rule = name[len("rule-"):] if name.startswith("rule-") else name
            candidate = f".claude/rules/{rule}.md"
            rel = candidate if os.path.isfile(os.path.join(root, candidate)) else f".claude/skills/{name}/SKILL.md"
        paths.append(rel)
    return paths


# Orca model slug -> Cursor picker spelling. Only documented picker forms:
# effort brackets exist for Grok; the fast toggle is a dispatch-time property
# (worker-start), so the -fast slug maps to the same picker id.
CURSOR_MODEL_SLUGS = {
    "cursor-grok-4.6-high": "grok-4.6[effort=high]",
    "cursor-grok-4.6-xhigh": "grok-4.6[effort=xhigh]",
    "cursor-grok-4.6-high-fast": "grok-4.6[effort=high]",
    "composer-2.5": "composer-2.5[fast=false]",
}

# Roles whose brief is read-only recon/judgement — Cursor's `readonly: true`.
CURSOR_READONLY_ROLES = {"auditor", "red-teamer", "reviewer", "scout"}

# These roles only inspect and report. Document-producing roles stay writable,
# as do gatekeeper (test/build artifacts), builders, and releaser.
CODEX_READONLY_ROLES = {
    "auditor",
    "pr-reviewer",
    "red-teamer",
    "reviewer",
    "scout",
}


def cursor_agent(root: str, role: str, step: dict) -> str:
    src_rel = agent_source(root, role)
    fields, skills, body = split_frontmatter(read(root, src_rel))
    lane = "" if src_rel.endswith(f"{role}.md") else (
        f"\n\n**This is the `{role}` lane of `{fields.get('name', role)}`** — the model matrix "
        f"varies the runtime and model for this lane, never the brief above."
    )
    rules = carried_rules(root, skills)
    carried = (
        "\n\n## Rules that do not travel — read them yourself\n\n"
        "Claude preloads these as skills; Cursor loads `.cursor/rules/*.mdc` on touch but has no "
        "preload, so read each file before your first edit. A rule you did not read still binds you.\n\n"
        + "\n".join(f"- `{p}`" for p in rules)
        + "\n- `AGENTS.md` (the repo charter — a symlink to `CLAUDE.md`)\n"
    ) if rules else "\n\n- `AGENTS.md` (the repo charter — a symlink to `CLAUDE.md`)\n"

    model = CURSOR_MODEL_SLUGS.get(step["model"], step["model"])
    head = [
        "---",
        f"name: {role}",
        f"description: {fields.get('description', '').strip()}",
    ]
    if role in CURSOR_READONLY_ROLES:
        head.append("readonly: true")
    head += [
        f"model: {model}",
        "---",
        "",
        banner([src_rel, RUNTIMES_JSON]),
        "",
    ]
    return "\n".join(head) + "\n" + body.strip() + lane + carried


def opencode_agent(root: str, role: str, step: dict) -> str:
    src_rel = agent_source(root, role)
    fields, skills, body = split_frontmatter(read(root, src_rel))
    lane = "" if src_rel.endswith(f"{role}.md") else (
        f"\n\n**This is the `{role}` lane of `{fields.get('name', role)}`** — the model matrix "
        f"varies the runtime and model for this lane, never the brief above."
    )
    rules = carried_rules(root, skills)
    if rules:
        carried = (
            "\n\n## Rules that do not travel — read them yourself\n\n"
            "Claude preloads these as skills; OpenCode has no such preload, so read each "
            "file before your first edit. A rule you did not read still binds you.\n\n"
            + "\n".join(f"- `{p}`" for p in rules)
            + "\n- `AGENTS.md` (the repo charter — a symlink to `CLAUDE.md`)\n"
        )
    else:
        carried = "\n\n- `AGENTS.md` (the repo charter — a symlink to `CLAUDE.md`)\n"

    head = [
        "---",
        f"description: {fields.get('description', '').strip()}",
        "mode: subagent",
        f"model: {step['model']}",
        "---",
        "",
        banner([src_rel, RUNTIMES_JSON]),
        "",
    ]
    return "\n".join(head) + "\n" + body.strip() + lane + carried


def codex_agent(root: str, role: str, policy: dict[str, str]) -> str:
    """A native Codex custom-agent TOML generated from one Claude role body."""
    import json

    src_rel = agent_source(root, role)
    fields, skills, body = split_frontmatter(read(root, src_rel))
    if "'''" in body:
        raise SystemExit(f"{src_rel} contains triple apostrophes; cannot embed it verbatim in TOML")

    startup_paths = ["AGENTS.md"] + [f".agents/skills/{name}/SKILL.md" for name in skills]
    startup = (
        "\n## Codex worker startup\n\n"
        "Before acting on the dispatched brief, read these files in order:\n\n"
        + "\n".join(f"- `{path}`" for path in startup_paths)
        + "\n\nThis is a dispatched worker, not the Orchestra coordinator. Do not load the "
        "Codex coordinator skill, route work, or delegate. Native subagents are disabled "
        "for this worker below.\n"
    )

    head = [
        toml_banner([src_rel, CODEX_MODELS_JSON]),
        f"name = {json.dumps(role)}",
        f"description = {json.dumps(fields.get('description', '').strip())}",
        f"model = {json.dumps(policy['model'])}",
        f"model_reasoning_effort = {json.dumps(policy['effort'])}",
    ]
    if role in CODEX_READONLY_ROLES:
        head.append('sandbox_mode = "read-only"')
    head += [
        "developer_instructions = '''",
        body + startup,
        "'''",
        "",
        "[agents]",
        "enabled = false",
        "",
        "[shell_environment_policy.set]",
        f"ORCHESTRA_CODEX_WORKER = {json.dumps(role)}",
    ]
    if role in CODEX_READONLY_ROLES:
        head.append('ORCHESTRA_CODEX_READ_ONLY = "1"')
    return "\n".join(head)


def mirrored_skill(root: str, name: str) -> str:
    src_rel = os.path.join(CLAUDE_SKILLS, name, "SKILL.md")
    raw = read(root, src_rel)
    m = re.match(r"^(---\n.*?\n---\n)(.*)$", raw, re.DOTALL)
    if not m:
        raise SystemExit(f"{src_rel} has no frontmatter; OpenCode would skip the skill")
    return m.group(1) + "\n" + banner([src_rel]) + "\n\n" + m.group(2).lstrip("\n")


CODEX_NOTE = """# Codex worker assets are generated

GENERATED from .claude/agents/*.md and docs/orchestra/codex-models.json — DO NOT EDIT THIS FILE.
Regenerate: python3 scripts/generate-runtimes.py

Native Codex custom agents live in `.codex/agents/*.toml`. Each copies its
Claude role body, names the exact neutral skill mirrors it must read at startup,
pins its native model and effort, and disables nested agents.

- **Source role behavior:** `.claude/agents/<role>.md` (builder lanes reuse
  `builder.md`; `builder-max` has its own source).
- **Native model policy:** `docs/orchestra/codex-models.json`, documented by
  `docs/orchestra/codex-models.md`. This is separate from Orca fallback chains.
- **Generated files:** `.codex/agents/*.toml` and this note. Never hand-edit
  them; change a source or policy and regenerate.
- **Activation:** these are workers only. There is deliberately no
  `orchestrator.toml`; a primary Codex session coordinates only through the
  explicit opt-in coordinator skill.
- **Standalone Orca workers:** an external Orca dispatch still carries its
  complete self-contained brief and explicit model/effort flags. Project hooks
  recognize Orca's `ORCA_WORKTREE_ID` worker environment. Other external
  launchers must set `ORCHESTRA_CODEX_WORKER=<role>`; a prompt cannot set
  process environment identity.

Native Codex roles: {roles}.
"""


def outputs(root: str) -> dict[str, str]:
    """Every generated path (repo-relative) -> its exact wanted content."""
    import json

    runtimes = json.loads(read(root, RUNTIMES_JSON))
    files: dict[str, str] = {}

    for role, step in runtime_roles(runtimes, "opencode"):
        files[os.path.join(".opencode", "agents", f"{role}.md")] = opencode_agent(root, role, step)

    for role, step in runtime_roles(runtimes, "cursor"):
        files[os.path.join(".cursor", "agents", f"{role}.md")] = cursor_agent(root, role, step)

    for name in RULE_CARRIER_SKILLS:
        files[os.path.join(".agents", "skills", name, "SKILL.md")] = mirrored_skill(root, name)

    codex_policy = json.loads(read(root, CODEX_MODELS_JSON))
    roles = codex_policy.get("roles")
    if not isinstance(roles, dict) or not roles:
        raise SystemExit(f"{CODEX_MODELS_JSON} must contain a non-empty 'roles' object")
    source_roles = {
        os.path.splitext(name)[0]
        for name in os.listdir(os.path.join(root, CLAUDE_AGENTS))
        if name.endswith(".md")
    }
    missing_source_roles = sorted(source_roles - set(roles))
    if missing_source_roles:
        raise SystemExit(
            f"{CODEX_MODELS_JSON} omits Claude source role(s): "
            + ", ".join(missing_source_roles)
        )
    for role, policy in sorted(roles.items()):
        if not isinstance(policy, dict) or set(policy) != {"model", "effort"}:
            raise SystemExit(f"{CODEX_MODELS_JSON} role '{role}' must contain only model and effort")
        if not all(isinstance(policy[key], str) and policy[key] for key in ("model", "effort")):
            raise SystemExit(f"{CODEX_MODELS_JSON} role '{role}' has an empty model or effort")
        files[os.path.join(".codex", "agents", f"{role}.toml")] = codex_agent(root, role, policy)

    codex_roles = ", ".join(f"`{role}`" for role in sorted(roles))
    files[os.path.join(".codex", "AGENTS-NOTE.md")] = CODEX_NOTE.replace("{roles}", codex_roles)

    return {k: (v if v.endswith("\n") else v + "\n") for k, v in sorted(files.items())}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="exit 1 on drift, write nothing")
    ap.add_argument("--root", default=REPO_ROOT, help="repo root to read sources from")
    ap.add_argument("--out", default=None, help="write under this directory instead of --root")
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root)
    out_root = os.path.abspath(args.out) if args.out else root

    want = outputs(root)
    drift: list[str] = []
    written: list[str] = []

    codex_agents_dir = os.path.join(out_root, ".codex", "agents")
    expected_codex_agents = {
        os.path.basename(rel)
        for rel in want
        if os.path.dirname(rel) == os.path.join(".codex", "agents")
    }
    if os.path.isdir(codex_agents_dir):
        for name in sorted(os.listdir(codex_agents_dir)):
            if not name.endswith(".toml") or name in expected_codex_agents:
                continue
            rel = os.path.join(".codex", "agents", name)
            if args.check:
                drift.append(f"{rel}: orphan generated asset")
            else:
                os.remove(os.path.join(codex_agents_dir, name))
                print(f"removed {rel}")

    for rel, body in want.items():
        dst = os.path.join(out_root, rel)
        have = None
        if os.path.isfile(dst):
            with open(dst, encoding="utf-8") as f:
                have = f.read()
        if have == body:
            continue
        if args.check:
            drift.append(f"{rel}: {'missing' if have is None else 'differs from the generated content'}")
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        written.append(rel)

    for rel in written:
        print(f"wrote   {rel}")
    for line in drift:
        print(f"DRIFT   {line}")
    print(f"examined {len(want)} file(s)")

    if drift:
        print(
            f"\n{len(drift)} runtime asset(s) drifted. A generated file was hand-edited, or a "
            f"Claude source moved on without it. Regenerate: python3 scripts/generate-runtimes.py",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
