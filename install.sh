#!/usr/bin/env bash
# Merge-mode install for the orchestra roster. Run from the TARGET project root.
# Never replaces a filled CLAUDE.md / AGENTS.md charter, host hooks, or
# non-orchestra skills. AGENTS.md must be a symlink to project CLAUDE.md.
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
  say "== 0. Merge-copy from $SRC (keep host charter/hooks/extra skills)"
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
  # Claude Code runtime (second harness, same graph). Never copy .claude/skills/
  # — Cursor also loads that directory; a second orchestrator skill would fork the OS.
  mkdir -p "$DST/.claude/agents" "$DST/.claude/hooks"
  if [ -d "$SRC/.claude/agents" ]; then
    for f in "$SRC"/.claude/agents/*.md; do
      [ -f "$f" ] && cp "$f" "$DST/.claude/agents/"
    done
  fi
  for h in orchestra-block-dangerous.py orchestra-block-nested.py orchestra-session-start.py; do
    [ -f "$SRC/.claude/hooks/$h" ] && cp "$SRC/.claude/hooks/$h" "$DST/.claude/hooks/$h"
  done
  [ -f "$SRC/.claude/orchestra-router.md" ] && cp "$SRC/.claude/orchestra-router.md" "$DST/.claude/orchestra-router.md"
  python3 - "$SRC" "$DST" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
frag_path = os.path.join(src, "docs", "orchestra", "claude-settings.fragment.json")
host_path = os.path.join(dst, ".claude", "settings.json")
if not os.path.isfile(frag_path):
    raise SystemExit(0)
frag = json.load(open(frag_path))
if os.path.isfile(host_path):
    host = json.load(open(host_path))
else:
    host = {}
host.setdefault("hooks", {})

def basename(cmd):
    return os.path.basename((cmd or "").replace("\\", "/").replace('"', "").replace("'", ""))

for event, entries in (frag.get("hooks") or {}).items():
    existing = host["hooks"].setdefault(event, [])
    if event == "PreToolUse":
        by_matcher = {e.get("matcher"): e for e in existing if isinstance(e, dict)}
        for e in entries:
            m = e.get("matcher")
            if m in by_matcher:
                hooks = by_matcher[m].setdefault("hooks", [])
                by_cmd = {basename(h.get("command", "")): i for i, h in enumerate(hooks)}
                for h in e.get("hooks") or []:
                    cmd = basename(h.get("command", ""))
                    if cmd in by_cmd:
                        hooks[by_cmd[cmd]] = h
                    else:
                        hooks.append(h)
            else:
                existing.append(e)
        continue
    by_cmd = {}
    for i, e in enumerate(existing):
        inner = e.get("hooks") or [e]
        for h in inner:
            by_cmd[basename(h.get("command", ""))] = (i, e)
    for e in entries:
        for h in e.get("hooks") or [e]:
            cmd = basename(h.get("command", ""))
            if cmd in by_cmd:
                i, old = by_cmd[cmd]
                if "hooks" in old:
                    old["hooks"] = [h]
                else:
                    existing[i] = e
            else:
                existing.append(e)
os.makedirs(os.path.dirname(host_path), exist_ok=True)
json.dump(host, open(host_path, "w"), indent=2)
print("merged .claude/settings.json (host entries kept; orchestra Claude hooks upserted)")
PY
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
  python3 - "$DST" <<'PY'
# Named exception to "never delete host hooks": Cursor never-merge is incompatible
# with pr-reviewer CLEAN → releaser land (ralph / overnight). Strip it.
import json, os, sys
path = os.path.join(sys.argv[1], ".cursor", "hooks.json")
if not os.path.isfile(path):
    raise SystemExit(0)
host = json.load(open(path))
stripped = []
for event, entries in list((host.get("hooks") or {}).items()):
    kept = []
    for e in entries:
        cmd = os.path.basename((e.get("command") or "").replace("\\", "/"))
        if cmd == "block-pr-merge.sh":
            stripped.append(f"{event}:{e.get('command')}")
            continue
        kept.append(e)
    host["hooks"][event] = kept
if stripped:
    json.dump(host, open(path, "w"), indent=2)
    print("unwired Cursor never-merge rail:", "; ".join(stripped))
else:
    print("no block-pr-merge.sh wired (Cursor may merge after pr-reviewer CLEAN)")
PY
  # Charter: CLAUDE.md is the file; AGENTS.md is a symlink to it.
  # Heal creates/migrates and refuses a link to ~/.claude/CLAUDE.md.
  (cd "$DST" && echo '{}' | python3 .cursor/hooks/heal-orchestra-docs.py >/dev/null)
  if [ -L "$DST/AGENTS.md" ]; then
    say "charter: AGENTS.md -> $(readlink "$DST/AGENTS.md")"
  elif [ -f "$DST/CLAUDE.md" ]; then
    say "charter: CLAUDE.md present (heal left a differing AGENTS.md copy intact)"
  else
    say "note: heal did not create CLAUDE.md — check .orchestra/hook-failures.log"
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
chmod +x .claude/hooks/orchestra-*.py 2>/dev/null || bad "could not chmod .claude/hooks/orchestra-*.py"
chmod +x docs/orchestra/generate-flow-html.py 2>/dev/null || true
chmod +x docs/orchestra/generate-claude-agents.py 2>/dev/null || true

say "== 2. Guardrail self-test (deny + allow)"
out=$(echo '{"command":"git push --force"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "force push not denied: $out"
out=$(echo '{"command":"git push origin main"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "protected push not denied without CLEAN: $out"
out=$(echo '{"command":"git status"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "git status not allowed: $out"
out=$(echo '{"command":"sh -c \"git push --force\""}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "interpreter-wrapped force push not denied: $out"
out=$(echo '{"command":"env CI=1 git push --force"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "env-prefixed force push not denied: $out"
out=$(echo '{"command":"gh pr merge 42 --squash"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "gh pr merge not denied without CLEAN: $out"
out=$(echo '{"command":"az repos pr update --id 42 --status completed"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "az repos pr completion not denied without CLEAN: $out"
out=$(echo '{"command":"glab mr merge 42"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "glab mr merge not denied without CLEAN: $out"
out=$(echo '{"command":"az repos pr show --id 42"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "read-only az repos command wrongly gated: $out"
out=$(echo '{"command":"git push origin main"}' | CURSOR_CLOUD_AGENT=1 ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "headless protected push not denied without CLEAN: $out"

say "== 2b. pr-reviewer CLEAN + fresh gate authorizes headless land"
mkdir -p .orchestra
_state=.orchestra/state.json
_bak=.orchestra/state.json.install-bak
[ -f "$_state" ] && cp "$_state" "$_bak"
python3 - <<'PY' || FAIL=1
import json, os, subprocess
os.makedirs(".orchestra", exist_ok=True)
head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state = {}
if os.path.isfile(".orchestra/state.json"):
    try:
        state = json.load(open(".orchestra/state.json"))
    except Exception:
        state = {}
state.setdefault("gates", {})["last_green_hash"] = head
state.setdefault("reviews", {})["pr"] = "CLEAN"
json.dump(state, open(".orchestra/state.json", "w"), indent=2)
PY
out=$(echo '{"command":"gh pr merge 42 --squash"}' | CURSOR_CLOUD_AGENT=1 ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "CLEAN+fresh gh pr merge not allowed headless: $out"
out=$(echo '{"command":"git push origin main"}' | CURSOR_CLOUD_AGENT=1 ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "CLEAN+fresh protected push not allowed headless: $out"
if [ -f "$_bak" ]; then mv "$_bak" "$_state"; else rm -f "$_state"; fi
unset _state _bak

say "== 2c. declared deploy: deny without CLEAN; allow with CLEAN+fresh"
_del=.orchestra/delivery.json
_delbak=.orchestra/delivery.json.install-bak
[ -f "$_del" ] && cp "$_del" "$_delbak"
python3 - <<'PY' || FAIL=1
import json, os
os.makedirs(".orchestra", exist_ok=True)
d = {}
if os.path.isfile(".orchestra/delivery.json"):
    try:
        d = json.load(open(".orchestra/delivery.json"))
    except Exception:
        d = {}
d["deploy_commands"] = ["vercel deploy --prod"]
json.dump(d, open(".orchestra/delivery.json", "w"), indent=2)
PY
out=$(echo '{"command":"vercel deploy --prod"}' | ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "declared deploy not denied without CLEAN: $out"
echo "$out" | grep -q '"ask"' && bad "hook returned ask (must never ask): $out"
_state=.orchestra/state.json
_bak=.orchestra/state.json.install-bak
[ -f "$_state" ] && cp "$_state" "$_bak"
python3 - <<'PY' || FAIL=1
import json, os, subprocess
os.makedirs(".orchestra", exist_ok=True)
head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state = {}
if os.path.isfile(".orchestra/state.json"):
    try:
        state = json.load(open(".orchestra/state.json"))
    except Exception:
        state = {}
state.setdefault("gates", {})["last_green_hash"] = head
state.setdefault("reviews", {})["pr"] = "CLEAN"
json.dump(state, open(".orchestra/state.json", "w"), indent=2)
PY
out=$(echo '{"command":"vercel deploy --prod"}' | CURSOR_CLOUD_AGENT=1 ./.cursor/hooks/block-dangerous.py)
echo "$out" | grep -q '"allow"' || bad "CLEAN+fresh declared deploy not allowed: $out"
if [ -f "$_bak" ]; then mv "$_bak" "$_state"; else rm -f "$_state"; fi
if [ -f "$_delbak" ]; then mv "$_delbak" "$_del"; fi
unset _state _bak _del _delbak

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
wired = json.dumps(h)
if "block-pr-merge.sh" in wired:
    print("FAIL: block-pr-merge.sh still wired — Cursor cannot land after pr-reviewer CLEAN")
    ok = False
sys.exit(0 if ok else 1)
PY
out=$(echo '{}' | python3 .cursor/hooks/session-start.py)
python3 -c "import json,sys; json.loads(sys.argv[1])" "$out" || bad "session-start.py did not print JSON: $out"
# heal must not clobber a filled charter
if grep -q '## Who you are' CLAUDE.md 2>/dev/null || grep -q '## Who you are' AGENTS.md 2>/dev/null; then
  before=$(wc -c < CLAUDE.md 2>/dev/null | tr -d ' ')
  [ -z "$before" ] && before=$(wc -c < AGENTS.md | tr -d ' ')
  echo '{}' | python3 .cursor/hooks/heal-orchestra-docs.py >/dev/null
  after=$(wc -c < CLAUDE.md | tr -d ' ')
  [ "$after" -lt "$before" ] && bad "heal-orchestra-docs.py shrank CLAUDE.md (must never clobber filled slots)"
fi
# AGENTS.md must be a relative symlink to project CLAUDE.md, never ~/.claude/CLAUDE.md
if [ -L AGENTS.md ]; then
  t=$(readlink AGENTS.md)
  [ "$t" = "CLAUDE.md" ] || bad "AGENTS.md must symlink to CLAUDE.md (got $t)"
  case "$t" in
    /*) bad "AGENTS.md symlink is absolute — must be relative CLAUDE.md" ;;
  esac
  real=$(python3 -c "import os; print(os.path.realpath('AGENTS.md'))")
  here=$(python3 -c "import os; print(os.path.realpath('.'))")
  case "$real" in
    "$here"/*|"$here") ;;
    *) bad "AGENTS.md resolves outside the project ($real) — never ~/.claude/CLAUDE.md" ;;
  esac
elif [ -f AGENTS.md ] && [ -f CLAUDE.md ]; then
  say "note: AGENTS.md is a real file alongside CLAUDE.md (heal will not smash either)"
else
  bad "AGENTS.md missing after heal"
fi
[ -f CLAUDE.md ] || bad "CLAUDE.md missing (Cursor's AGENTS.md target)"
# heal refuses a symlink to a file outside the project
heal_tmp=$(mktemp -d)
mkdir -p "$heal_tmp/.cursor/hooks" "$heal_tmp/docs/orchestra"
cp .cursor/hooks/heal-orchestra-docs.py "$heal_tmp/.cursor/hooks/"
cp docs/orchestra/AGENTS.framework.md "$heal_tmp/docs/orchestra/"
cp docs/orchestra/AGENT-MEMORY.framework.md "$heal_tmp/docs/orchestra/" 2>/dev/null || true
ln -s "$HOME/.claude/CLAUDE.md" "$heal_tmp/AGENTS.md"
(cd "$heal_tmp" && echo '{}' | python3 .cursor/hooks/heal-orchestra-docs.py >/dev/null)
if [ -L "$heal_tmp/AGENTS.md" ]; then
  ht=$(readlink "$heal_tmp/AGENTS.md")
  [ "$ht" = "CLAUDE.md" ] || bad "heal left AGENTS.md pointing at $ht after outside-link (want CLAUDE.md)"
else
  bad "heal did not recreate AGENTS.md -> CLAUDE.md after refusing ~/.claude/CLAUDE.md"
fi
rm -rf "$heal_tmp"

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

say "== 4c. Claude layer (agents + models + no second orchestrator skill)"
[ -d .claude/skills/orchestrator ] && bad ".claude/skills/orchestrator exists — Cursor would load a second OS. Delete it; Claude reads .cursor/skills/orchestrator/SKILL.md"
python3 docs/orchestra/generate-claude-agents.py >/dev/null || bad "generate-claude-agents.py failed"
python3 - <<'PY' || FAIL=1
import os, re, sys
ok = True

def split_md(text):
    if text.startswith("---"):
        end = text.find("\n---\n", 3)
        if end != -1:
            return text[4:end], text[end + 5:]
    return "", text

def fm(front, key):
    m = re.search(rf"^{key}:\s*(.+)$", front, re.M)
    return m.group(1).strip() if m else ""

matrix = {
    "architect": ("claude-fable-5-1", "low"),
    "planner": ("claude-fable-5-1", "low"),
    "red-teamer": ("claude-fable-5-1", "low"),
    "auditor": ("claude-fable-5-1", "low"),
    "builder-max": ("claude-fable-5-1", "low"),
    "pr-reviewer": ("claude-fable-5-1", "low"),
    "scout": ("claude-sonnet-5", "low"),
    "researcher": ("claude-sonnet-5", "medium"),
    "reviewer": ("claude-fable-5-1", "low"),
    "builder": ("claude-sonnet-5", "medium"),
    "gatekeeper": ("claude-sonnet-5", "medium"),
    "janitor": ("claude-sonnet-5", "medium"),
    "releaser": ("claude-sonnet-5", "medium"),
}
for role, (model, effort) in matrix.items():
    cpath = f".cursor/agents/{role}.md"
    lpath = f".claude/agents/{role}.md"
    if not os.path.isfile(cpath) or not os.path.isfile(lpath):
        print(f"FAIL: missing agent pair for {role}")
        ok = False
        continue
    _, cb = split_md(open(cpath).read())
    lf, lb = split_md(open(lpath).read())
    if cb.strip() != lb.strip():
        print(f"FAIL: {role} Cursor/Claude bodies differ")
        ok = False
    if fm(lf, "model") != model:
        print(f"FAIL: {role} model {fm(lf, 'model')!r} want {model}")
        ok = False
    if fm(lf, "effort") != effort:
        print(f"FAIL: {role} effort {fm(lf, 'effort')!r} want {effort}")
        ok = False
    if "Agent" not in fm(lf, "disallowedTools"):
        print(f"FAIL: {role} missing disallowedTools: Agent")
        ok = False
    if "force-default-model" in lf or "grok-4.6" in lf or "composer-2.5" in lf:
        print(f"FAIL: {role} Claude file carries Cursor YAML")
        ok = False
sys.exit(0 if ok else 1)
PY
# Claude hook payloads
out=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force"}}' | python3 .claude/hooks/orchestra-block-dangerous.py)
echo "$out" | grep -q '"deny"' || bad "Claude force-push not denied: $out"
out=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Agent","agent_type":"builder"}' | python3 .claude/hooks/orchestra-block-nested.py)
echo "$out" | grep -q '"deny"' || bad "Claude nested Agent from worker not denied: $out"
out=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Agent"}' | python3 .claude/hooks/orchestra-block-nested.py)
echo "$out" | grep -q '"allow"' || bad "Claude Agent from main session denied: $out"

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
  urls=$(git remote -v 2>/dev/null | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
  # Dual-remote hosts (GitHub origin + Azure devops): Azure is the land path.
  if echo "$urls" | grep -Eq 'dev\.azure\.com|visualstudio\.com'; then
    provider=azure-devops; ssg=false
    echo "$urls" | grep -Eq 'github\.com' && \
      say "note: GitHub and Azure remotes both present — defaulting provider to azure-devops (edit delivery.json if GitHub is the gate of record)"
  elif echo "$urls" | grep -Eq 'github\.com'; then
    provider=github; ssg=false
  elif echo "$urls" | grep -Eq 'gitlab'; then
    provider=gitlab; ssg=false
  else
    provider=plain-git; ssg=false
  fi
  [ "$provider" = plain-git ] && landing=direct || landing=pr
  # Always default-protect main, never the current working branch. Overnight land
  # (e.g. Equiti azure-migration) must stay off this list so push is the deploy.
  printf '{\n  "provider": "%s",\n  "protected_branches": ["main"],\n  "landing": "%s",\n  "server_side_gate": %s,\n  "deploy": { "production": "auto" },\n  "deploy_commands": []\n}\n' \
    "$provider" "$landing" "$ssg" > .orchestra/delivery.json
  say "wrote .orchestra/delivery.json — detected provider: $provider"
  say "  protected_branches defaults to [\"main\"] (not the current branch)."
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
say "  - If you run cloud agents: confirm headless detection. The hook treats CURSOR_CLOUD_AGENT / CURSOR_BACKGROUND_AGENT / CURSOR_AGENT_ID / CI as headless (gate_fresh fail-closed when state.json is missing). If cloud runs set none of these, add \"headless\": true to .orchestra/delivery.json for that repo."
say "  - Cloud landing/deploy: pr-reviewer CLEAN + matching gates.last_green_hash allows headless PR merge, protected push, and declared deploys. Without that record, those are deny (the hook never returns ask). server_side_gate is the other path — set it true ONLY if a host branch policy already runs the fast set. Do not set it true just because the remote is Azure."
say "  - Re-run this script after every Cursor update (hook payload schemas can change silently — check .orchestra/hook-failures.log; sessionStart also surfaces it)."
say "  - Living hosts: this installer merges. It will not overwrite a filled CLAUDE.md, extra skills, or non-orchestra hook entries — except it STRIPS block-pr-merge.sh (Cursor never-merge is incompatible with ralph / pr-reviewer CLEAN land). AGENTS.md is a symlink to project CLAUDE.md — never ~/.claude/CLAUDE.md."

[ "$FAIL" -eq 0 ] && say "INSTALL OK" || say "INSTALL INCOMPLETE — fix the FAIL lines above"
exit "$FAIL"
