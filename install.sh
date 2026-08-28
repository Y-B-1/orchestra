#!/usr/bin/env bash
# Merge-mode install for the orchestra roster. Run from the TARGET project root.
# Never replaces a filled AGENTS.md, host hooks, or non-orchestra skills.
set -uo pipefail
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; FAIL=1; }

SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$(pwd)"

ORCHESTRA_SKILLS="orchestrator design plan execute diagnose audit gates release cleanup pr-review"
ORCHESTRA_HOOKS="block-dangerous.py block-nested-subagents.py heal-orchestra-docs.py session-start.py"

merge_copy() {
  if [ "$SRC" = "$DST" ]; then
    say "== 0. Source is the target (package repo) — skip copy"
    return
  fi
  say "== 0. Merge-copy from $SRC (keep host AGENTS.md, host hooks, extra skills)"
  mkdir -p "$DST/.cursor/agents" "$DST/.cursor/rules" "$DST/.cursor/hooks" "$DST/.cursor/skills" "$DST/docs/orchestra"
  for f in "$SRC"/.cursor/agents/*.md; do
    cp "$f" "$DST/.cursor/agents/"
  done
  for skill in $ORCHESTRA_SKILLS; do
    if [ -d "$SRC/.cursor/skills/$skill" ]; then
      mkdir -p "$DST/.cursor/skills/$skill"
      cp -R "$SRC/.cursor/skills/$skill/." "$DST/.cursor/skills/$skill/"
    fi
  done
  cp "$SRC/.cursor/rules/orchestra-router.mdc" "$DST/.cursor/rules/orchestra-router.mdc"
  for h in $ORCHESTRA_HOOKS; do
    cp "$SRC/.cursor/hooks/$h" "$DST/.cursor/hooks/$h"
  done
  if [ -d "$SRC/docs/orchestra" ]; then
    cp -R "$SRC/docs/orchestra/." "$DST/docs/orchestra/"
  fi
  if [ -f "$SRC/docs/flow.html" ]; then
    mkdir -p "$DST/docs"
    cp "$SRC/docs/flow.html" "$DST/docs/flow.html"
  fi
  python3 - "$SRC" "$DST" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
frag_path = os.path.join(src, ".cursor", "hooks.json")
host_path = os.path.join(dst, ".cursor", "hooks.json")
frag = json.load(open(frag_path))
if os.path.isfile(host_path):
    host = json.load(open(host_path))
else:
    host = {"version": 1, "hooks": {}}
host.setdefault("version", 1)
host.setdefault("hooks", {})
for event, entries in (frag.get("hooks") or {}).items():
    existing = host["hooks"].setdefault(event, [])
    by_cmd = {os.path.basename(e.get("command", "")): i for i, e in enumerate(existing) if e.get("command")}
    for e in entries:
        cmd = os.path.basename(e.get("command", ""))
        if cmd in by_cmd:
            existing[by_cmd[cmd]] = e
        else:
            existing.append(e)
os.makedirs(os.path.dirname(host_path), exist_ok=True)
json.dump(host, open(host_path, "w"), indent=2)
print("merged .cursor/hooks.json (host entries kept; orchestra commands upserted)")
PY
  if [ ! -f "$DST/AGENTS.md" ]; then
    cp "$SRC/docs/orchestra/AGENTS.framework.md" "$DST/AGENTS.md"
    say "created AGENTS.md from framework — fill the project slots"
  else
    python3 - "$SRC" "$DST" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
path = os.path.join(dst, "AGENTS.md")
text = open(path).read()
if "## Orchestra" in text:
    print("AGENTS.md already has ## Orchestra — left intact")
    raise SystemExit(0)
frame = open(os.path.join(src, "docs", "orchestra", "AGENTS.framework.md")).read()
if "## Orchestra" in frame:
    part = frame.split("## Orchestra", 1)[1]
    nxt = part.find("\n## ")
    block = "## Orchestra" + (part if nxt < 0 else part[:nxt]).rstrip() + "\n"
else:
    block = "## Orchestra\n\nRouting: `.cursor/skills/orchestrator/flow.json`.\n"
with open(path, "a") as f:
    f.write("\n" + block if text.endswith("\n") else "\n\n" + block)
print("appended ## Orchestra to existing AGENTS.md (product slots untouched)")
PY
  fi
  if [ ! -f "$DST/docs/AGENT-MEMORY.md" ] && [ ! -f "$DST/docs/agent-memory.md" ]; then
    mkdir -p "$DST/docs"
    cp "$SRC/docs/orchestra/AGENT-MEMORY.framework.md" "$DST/docs/AGENT-MEMORY.md"
    say "created docs/AGENT-MEMORY.md from framework"
  fi
}

merge_copy

say "== 1. Hooks executable"
chmod +x .cursor/hooks/*.py 2>/dev/null || bad "could not chmod .cursor/hooks/*.py"
chmod +x docs/orchestra/generate-flow-html.py 2>/dev/null || true

say "== 2. Guardrail self-test (deny + ask + allow)"
out=$(echo '{"command":"git push --force"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "force push not denied: $out"
out=$(echo '{"command":"git push origin main"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -Eq '"(ask|deny)"' || bad "protected push not gated: $out"
out=$(echo '{"command":"git status"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "git status not allowed: $out"
out=$(echo '{"command":"sh -c \"git push --force\""}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "interpreter-wrapped force push not denied: $out"
out=$(echo '{"command":"env CI=1 git push --force"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "env-prefixed force push not denied: $out"
out=$(echo '{"command":"gh pr merge 42 --squash"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -Eq '"(ask|deny)"' || bad "gh pr merge not gated: $out"
out=$(echo '{"command":"az repos pr update --id 42 --status completed"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -Eq '"(ask|deny)"' || bad "az repos pr completion not gated: $out"
out=$(echo '{"command":"glab mr merge 42"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -Eq '"(ask|deny)"' || bad "glab mr merge not gated: $out"
out=$(echo '{"command":"az repos pr show --id 42"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "read-only az repos command wrongly gated: $out"
out=$(echo '{"command":"git push origin main"}' | CURSOR_CLOUD_AGENT=1 ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "headless protected push not denied (ask must degrade to deny in cloud): $out"

say "== 3. Nested-subagent self-test (documented payload: subagent_id + parent_conversation_id)"
rm -f .orchestra/subagent-children.json
echo '{"subagent_id":"child-A","parent_conversation_id":"main-1","subagent_type":"builder"}' | ./.cursor/hooks/block-nested-subagents.py >/dev/null
out=$(echo '{"subagent_id":"child-B","parent_conversation_id":"main-1","subagent_type":"reviewer"}' | ./.cursor/hooks/block-nested-subagents.py)
echo "$out" | grep -q '"allow"' || bad "sibling spawn from orchestrator denied: $out"
out=$(echo '{"subagent_id":"grandchild","parent_conversation_id":"child-A","subagent_type":"scout"}' | ./.cursor/hooks/block-nested-subagents.py)
echo "$out" | grep -q '"deny"' || bad "nested spawn not denied: $out"
rm -f .orchestra/subagent-children.json
# conversation_id is the parent/session — recording it as a child would deny every later dispatch
echo '{"parent_conversation_id":"main-1","conversation_id":"main-1"}' | ./.cursor/hooks/block-nested-subagents.py >/dev/null
out=$(echo '{"subagent_id":"child-B","parent_conversation_id":"main-1","subagent_type":"reviewer"}' | ./.cursor/hooks/block-nested-subagents.py)
echo "$out" | grep -q '"allow"' || bad "conversation_id must not be recorded as a child (would poison orchestrator fan-out): $out"
rm -f .orchestra/subagent-children.json

say "== 3b. failClosed + sessionStart JSON"
python3 - <<'PY' || FAIL=1
import json, sys
h = json.load(open(".cursor/hooks.json"))
ok = True
for event in ("beforeShellExecution", "subagentStart"):
    entries = (h.get("hooks") or {}).get(event) or []
    if not any(e.get("failClosed") for e in entries):
        print(f"FAIL: {event} missing failClosed: true")
        ok = False
ss = (h.get("hooks") or {}).get("sessionStart") or []
if not any("session-start.py" in (e.get("command") or "") for e in ss):
    print("FAIL: sessionStart hook missing")
    ok = False
sys.exit(0 if ok else 1)
PY
out=$(echo '{}' | python3 .cursor/hooks/session-start.py)
python3 -c "import json,sys; json.loads(sys.argv[1])" "$out" || bad "session-start.py did not print JSON: $out"
# heal must not clobber a filled charter
if grep -q '## Who you are' AGENTS.md 2>/dev/null; then
  before=$(wc -c < AGENTS.md | tr -d ' ')
  echo '{}' | python3 .cursor/hooks/heal-orchestra-docs.py >/dev/null
  after=$(wc -c < AGENTS.md | tr -d ' ')
  [ "$after" -lt "$before" ] && bad "heal-orchestra-docs.py shrank AGENTS.md (must never clobber filled slots)"
fi

say "== 4. Model pinning (judgement inherit; the rest pinned + force-default-model)"
for f in builder reviewer gatekeeper releaser scout researcher janitor; do
  grep -q '^model: inherit' ".cursor/agents/$f.md" && bad "$f.md is 'model: inherit' — pin a tier id (see .cursor/skills/orchestrator/models.md)"
  grep -q '^force-default-model: true' ".cursor/agents/$f.md" || bad "$f.md missing force-default-model: true (Task inherit would override YAML)"
done
say "  note: shipped defaults assume grok-4.6 / composer-2.5 / gpt-5.6-luna are on your plan."
say "  Confirm in Cursor's model picker; YAML model: is what Cursor honors — see models.md."
for f in architect planner red-teamer auditor builder-max pr-reviewer; do
  grep -q '^model: inherit' ".cursor/agents/$f.md" || say "note: $f.md not 'inherit' — intentional?"
  grep -q '^force-default-model: true' ".cursor/agents/$f.md" && bad "$f.md is judgement — must not set force-default-model (session ceiling inherit)"
done
grep -q '^is_background: true' .cursor/agents/researcher.md && bad "researcher.md must not force is_background: true (intake Q&A is foreground)"

say "== 4b. Phase skills locked (disable-model-invocation)"
[ -f "$SRC/VERSION" ] || bad "package VERSION file missing at $SRC/VERSION"
for skill in $ORCHESTRA_SKILLS; do
  f=".cursor/skills/$skill/SKILL.md"
  [ -f "$f" ] || { bad "missing skill $f"; continue; }
  grep -q '^disable-model-invocation: true' "$f" || bad "$f missing disable-model-invocation: true (workers must not auto-load orchestrator playbooks)"
done

say "== 5. Graph + reference consistency"
python3 - <<'PY' || FAIL=1
import json, re, os, sys
d = json.load(open('.cursor/skills/orchestrator/flow.json'))
s = set(d['states']); roles = set(d['roles']); ok = True
if (d.get('states') or {}).get('intake', {}).get('match') != 'first':
    print("FAIL: intake.match must be 'first' (exclusive classification)")
    ok = False
for k, v in d['states'].items():
    for disp in [v.get('dispatch', '')] + [r.get('dispatch', '') for r in v.get('routes', [])]:
        for tok in re.split(r'[+|]', disp):
            base = tok.strip().split(':')[0].split('@')[0]
            if base and base not in roles: print(f"FAIL: unknown role {base} in {k}"); ok = False
    for r in v.get('routes', []):
        for e in (r.get('next'), r.get('back_to')):
            if e and e not in s: print(f"FAIL: dangling edge {k} -> {e}"); ok = False
for role, path in d['roles'].items():
    if role != 'orchestrator' and not os.path.exists(path.split(' ')[0]):
        print(f"FAIL: missing agent file for {role}"); ok = False
for dead in ('scout-recon', 'research', 'red-team', 'build-wave', 'review-gate'):
    if os.path.isdir(f'.cursor/skills/{dead}'): print(f"FAIL: retired skill present: {dead}"); ok = False
if not os.path.exists('.cursor/skills/orchestrator/briefs.md'): print("FAIL: briefs.md missing"); ok = False
if 'review.pr' not in s: print("FAIL: missing review.pr state"); ok = False
if 'pr-reviewer' not in roles: print("FAIL: missing pr-reviewer role"); ok = False
if not os.path.exists('.cursor/skills/pr-review/SKILL.md'): print("FAIL: pr-review skill missing"); ok = False
briefs = open('.cursor/skills/orchestrator/briefs.md').read() if os.path.exists('.cursor/skills/orchestrator/briefs.md') else ''
if '## pr-reviewer' not in briefs: print("FAIL: briefs.md missing ## pr-reviewer"); ok = False
sys.exit(0 if ok else 1)
PY
if [ -f docs/orchestra/generate-flow-html.py ]; then
  python3 docs/orchestra/generate-flow-html.py --check || {
    if [ "$SRC" = "$DST" ]; then
      python3 docs/orchestra/generate-flow-html.py && python3 docs/orchestra/generate-flow-html.py --check \
        || bad "flow.html still missing states after regenerate"
    else
      bad "docs/flow.html missing flow.json states — copy the generated file from the package"
    fi
  }
fi

say "== 6. Gitignore"
touch .gitignore
grep -q '^\.orchestra/\*' .gitignore || { printf '.orchestra/*\n!.orchestra/delivery.json\n!.orchestra/package-version\n' >> .gitignore; say "added .orchestra/* (except delivery.json and package-version) to .gitignore"; }
grep -q '^!\.orchestra/delivery.json' .gitignore || { echo '!.orchestra/delivery.json' >> .gitignore; say "tracked .orchestra/delivery.json exception"; }
grep -q '^!\.orchestra/package-version' .gitignore || { echo '!.orchestra/package-version' >> .gitignore; say "tracked .orchestra/package-version exception"; }
grep -q '^\.cursor/worktrees/' .gitignore || { echo ".cursor/worktrees/" >> .gitignore; say "added .cursor/worktrees/ to .gitignore"; }

say "== 6b. Package version stamp"
mkdir -p .orchestra
ver=$(tr -d '[:space:]' < "$SRC/VERSION" 2>/dev/null || echo "unknown")
{
  printf '%s\n' "$ver"
  desc=$(git -C "$SRC" describe --always --abbrev=12 2>/dev/null || true)
  [ -n "$desc" ] && printf 'git: %s\n' "$desc"
} > .orchestra/package-version
say "wrote .orchestra/package-version: $(tr '\n' ' ' < .orchestra/package-version)"

say "== 7. Delivery declaration"
if grep -q 'Delivery: <declare' AGENTS.md 2>/dev/null; then
  if [ -f .orchestra/delivery.json ]; then
    say "note: AGENTS.md Delivery slot is still the placeholder — fill it from .orchestra/delivery.json when ready (not a FAIL)"
  else
    say "note: AGENTS.md Delivery slot is a framework placeholder; writing delivery.json next"
  fi
fi
if [ ! -f .orchestra/delivery.json ]; then
  mkdir -p .orchestra
  remote=$(git config --get remote.origin.url 2>/dev/null || echo "")
  case "$remote" in
    *github.com*)                      provider=github;       ssg=false ;;
    *dev.azure.com*|*visualstudio.com*) provider=azure-devops; ssg=false ;;
    *gitlab*)                          provider=gitlab;       ssg=false ;;
    "")                                provider=plain-git;    ssg=false ;;
    *)                                 provider=plain-git;    ssg=false ;;
  esac
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
  [ "$provider" = plain-git ] && landing=direct || landing=pr
  printf '{\n  "provider": "%s",\n  "protected_branches": ["%s"],\n  "landing": "%s",\n  "server_side_gate": %s,\n  "deploy": { "production": "approval" },\n  "deploy_commands": []\n}\n' \
    "$provider" "$branch" "$landing" "$ssg" > .orchestra/delivery.json
  say "wrote .orchestra/delivery.json — detected provider: $provider (remote: ${remote:-none})"
  say "  EDIT IT: confirm protected branches, set deploy policy per environment, list deploy_commands"
  say "  server_side_gate defaults to false. Set true ONLY if a host branch policy already runs the fast set."
  [ "$provider" = azure-devops ] && say "  Azure: a branch policy with build validation is the recommended cloud gate — create it, then set server_side_gate true"
fi
if [ ! -f .orchestra/state.json ] && [ -f docs/orchestra/state.example.json ]; then
  cp docs/orchestra/state.example.json .orchestra/state.json
  say "seeded .orchestra/state.json from docs/orchestra/state.example.json (gitignored)"
fi

say "== 8. Manual steps (cannot be verified here)"
say "  - Pin the orchestrator skill as a Custom Mode so routing stays on every turn."
say "  - Start one background sub-agent in Cursor and note where its state file lands; record that path in .orchestra/state.json as subagent_state_path."
say "  - If you run cloud agents: confirm headless detection. The hook treats CURSOR_CLOUD_AGENT / CURSOR_BACKGROUND_AGENT / CURSOR_AGENT_ID / CI as headless (ask -> deny). If cloud runs set none of these, add \"headless\": true to .orchestra/delivery.json for that repo, or the approval floor silently weakens there."
say "  - Cloud landing needs server_side_gate: a host branch policy running the fast set. Without it, cloud agents cannot land on a protected branch at all (by design). Do not set server_side_gate true just because the remote is Azure."
say "  - Re-run this script after every Cursor update (hook payload schemas can change silently — check .orchestra/hook-failures.log; sessionStart also surfaces it)."
say "  - Living hosts: this installer merges. It will not overwrite a filled AGENTS.md, extra skills, or non-orchestra hook entries."

[ "$FAIL" -eq 0 ] && say "INSTALL OK" || say "INSTALL INCOMPLETE — fix the FAIL lines above"
exit "$FAIL"
