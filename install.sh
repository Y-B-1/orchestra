#!/usr/bin/env bash
# Verified install for the orchestra roster. Run from the TARGET project root
# after copying .cursor/ and AGENTS.md in. Fails loudly on anything unverified.
set -uo pipefail
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; FAIL=1; }

say "== 1. Hooks executable"
chmod +x .cursor/hooks/*.py 2>/dev/null || bad "could not chmod .cursor/hooks/*.py"

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

say "== 3. Nested-subagent self-test (synthetic payload)"
rm -f .orchestra/subagent-children.json
echo '{"parent_conversation_id":"main-1","conversation_id":"child-A"}' | ./.cursor/hooks/block-nested-subagents.py >/dev/null
out=$(echo '{"parent_conversation_id":"child-A","conversation_id":"grandchild"}' | ./.cursor/hooks/block-nested-subagents.py)
echo "$out" | grep -q '"deny"' || bad "nested spawn not denied: $out"
rm -f .orchestra/subagent-children.json

say "== 4. Model pinning (judgement roles inherit; the rest pinned)"
for f in builder reviewer gatekeeper releaser scout researcher janitor; do
  grep -q '^model: inherit' ".cursor/agents/$f.md" && bad "$f.md still 'model: inherit' — pin it to your plan's tier (see README)"
done
for f in architect planner red-teamer auditor builder-max; do
  grep -q '^model: inherit' ".cursor/agents/$f.md" || say "note: $f.md not 'inherit' — intentional?"
done

say "== 5. Graph + reference consistency"
python3 - <<'PY' || FAIL=1
import json, re, os, sys
d = json.load(open('.cursor/skills/orchestrator/flow.json'))
s = set(d['states']); roles = set(d['roles']); ok = True
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
sys.exit(0 if ok else 1)
PY

say "== 6. Gitignore"
touch .gitignore
grep -q '^\.orchestra/\*' .gitignore || { printf '.orchestra/*\n!.orchestra/delivery.json\n' >> .gitignore; say "added .orchestra/* (except delivery.json) to .gitignore"; }
grep -q '^\.cursor/worktrees/' .gitignore || { echo ".cursor/worktrees/" >> .gitignore; say "added .cursor/worktrees/ to .gitignore"; }

say "== 7. Delivery declaration"
grep -q 'Delivery: <declare' AGENTS.md 2>/dev/null && bad "AGENTS.md Delivery line is still the placeholder — declare the repo's landing rule and deploy policy"
if [ ! -f .orchestra/delivery.json ]; then
  mkdir -p .orchestra
  remote=$(git config --get remote.origin.url 2>/dev/null || echo "")
  case "$remote" in
    *github.com*)                      provider=github;       ssg=false ;;
    *dev.azure.com*|*visualstudio.com*) provider=azure-devops; ssg=true  ;;
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
  [ "$provider" = azure-devops ] && say "  Azure: server_side_gate=true assumes a branch policy with build validation on '$branch' — create it, or set false"
fi

say "== 8. Manual steps (cannot be verified here)"
say "  - Start one background sub-agent in Cursor and note where its state file lands; record that path in .orchestra/state.json as subagent_state_path."
say "  - Re-run this script after every Cursor update (hook payload schemas can change silently — check .orchestra/hook-failures.log)."

[ "$FAIL" -eq 0 ] && say "INSTALL OK" || say "INSTALL INCOMPLETE — fix the FAIL lines above"
exit "$FAIL"
