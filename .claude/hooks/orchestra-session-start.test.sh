#!/usr/bin/env bash
# Proves orchestra-session-start.py hands the orchestrator identity block ONLY to
# the main session. A worker that receives it is told to dispatch sub-agents,
# which is how a fan-out becomes a fork bomb.
#
# The same silence is now owed to an ORCA-DISPATCHED worker, which is a full
# session (no agent_id/agent_type) and was therefore handed the block. Every
# invocation below runs with ORCA_WORKTREE_ID/ORCA_WORKSPACE_ID CLEARED so the
# arms mean the same thing whoever runs them — a test run from inside an Orca
# worker pane would otherwise see its own environment.
#
# Also proves the block POINTS AT the project skill `.claude/skills/orchestrator/`
# and no longer FORBIDS it. The hook is now a belt-and-braces reminder, not the
# only channel: the skill carries its own model-invocable `description`.
HOOK="$(dirname "$0")/orchestra-session-start.py"
pass=0; fail=0
check() { # name | payload | expect-ctx(yes|no)
  out=$(printf '%s' "$2" | env -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID python3 "$HOOK" 2>/dev/null)
  if [ "$3" = yes ]; then
    case "$out" in *"Orchestra main session"*) pass=$((pass+1)); echo "  ok    CTX    $1";;
      *) fail=$((fail+1)); echo "  FAIL  CTX    $1 — expected the identity block, got: ${out:0:60}";; esac
  else
    case "$out" in *"Orchestra main session"*) fail=$((fail+1)); echo "  FAIL  SILENT $1 — a worker was handed the orchestrator block";;
      *) pass=$((pass+1)); echo "  ok    SILENT $1";; esac
  fi
}
echo "=== the main session gets the block ==="
check "bare session payload"            '{"hook_event_name":"SessionStart"}'                               yes
check "empty agent fields"              '{"agent_id":"","agent_type":""}'                                  yes
echo "=== every worker shape stays silent ==="
check "named worker (agent_type)"       '{"agent_type":"builder"}'                                         no
check "named worker (agentType)"        '{"agentType":"builder"}'                                          no
check "UNNAMED worker (agent_id only)"  '{"agent_id":"a4e8098b04426409c"}'                                 no
check "UNNAMED worker (agentId only)"   '{"agentId":"a4e8098b04426409c"}'                                  no
check "both fields present"             '{"agent_id":"abc","agent_type":"scout"}'                          no
echo "=== the block points at the project skill, and does not forbid it ==="
ctx() { printf '{"hook_event_name":"SessionStart"}' | env -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID python3 "$HOOK" 2>/dev/null; }
has() { # name | needle | expect(yes|no)
  case "$(ctx)" in
    *"$2"*) if [ "$3" = yes ]; then pass=$((pass+1)); echo "  ok    HAS    $1";
            else fail=$((fail+1)); echo "  FAIL  ABSENT $1 — found \"$2\" in the injected block"; fi;;
    *)      if [ "$3" = no ]; then pass=$((pass+1)); echo "  ok    ABSENT $1";
            else fail=$((fail+1)); echo "  FAIL  HAS    $1 — expected \"$2\" in the injected block"; fi;;
  esac
}
has "names the project orchestrator skill" '.claude/skills/orchestrator/SKILL.md' yes
has "no longer forbids that skill"         'Do not add'                           no
has "does not send the session to Cursor"  '.cursor/skills/orchestrator'          no
has "still names the worker definitions"   '.claude/agents/'                      yes
has "still demands maximum parallelism"    'Maximize parallelism'                 yes

echo "=== THE ORCA SEAM: a dispatched worker is not the main session ==="
# Ground truth for the marker (2026-09-02, `orca orchestration worker-list`): a
# supervised worker pane has ORCA_WORKTREE_ID and no ORCA_WORKSPACE_ID; the
# coordinator pane has both. Both arms are asserted — an arm that cannot go red
# in one direction is not a check.
orca_run() { # env-assignments... -> hook output
  printf '{"hook_event_name":"SessionStart"}' | env -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID "$@" python3 "$HOOK" 2>/dev/null
}

out=$(orca_run ORCA_WORKTREE_ID='wsid::/Users/x/orca/workspaces/repo/wt')
case "$out" in
  *"Orchestra main session"*) fail=$((fail+1)); echo "  FAIL  ORCA   a dispatched worker was handed the orchestrator block";;
  *"Orca worker session"*)    pass=$((pass+1)); echo "  ok    ORCA   worker pane gets the one-line worker notice, not the block";;
  *) fail=$((fail+1)); echo "  FAIL  ORCA   worker pane got neither notice nor block: ${out:0:80}";;
esac

case "$out" in
  *"Do NOT load the \`orchestrator\` skill"*) pass=$((pass+1)); echo "  ok    ORCA   the worker notice forbids loading the skill";;
  *) fail=$((fail+1)); echo "  FAIL  ORCA   the worker notice does not forbid the skill: ${out:0:120}";;
esac

out=$(orca_run ORCA_WORKTREE_ID='wsid::/Users/x/repo' ORCA_WORKSPACE_ID='wsid::/Users/x/repo')
case "$out" in
  *"Orchestra main session"*) pass=$((pass+1)); echo "  ok    ORCA   the coordinator pane still gets the block";;
  *) fail=$((fail+1)); echo "  FAIL  ORCA   the coordinator pane lost the block: ${out:0:80}";;
esac

out=$(orca_run ORCA_WORKSPACE_ID='wsid::/Users/x/repo')
case "$out" in
  *"Orchestra main session"*) pass=$((pass+1)); echo "  ok    ORCA   a non-Orca session (no worktree id) is untouched";;
  *) fail=$((fail+1)); echo "  FAIL  ORCA   a non-Orca session lost the block: ${out:0:80}";;
esac

echo "=== R1: the routing constitution is injected verbatim, not a pointer ==="
has "carries the routing sentinel"         'ORCHESTRA-ROUTE-V1'                   yes

echo "=== R2/R3: sandbox reddens on a missing file rather than staying silent ==="
sandbox() {
  # Build a minimal repo root with our own hooks dir; caller mutates it.
  d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks"
  cp "$HOOK" "$d/.claude/hooks/orchestra-session-start.py"
  cp "$(dirname "$0")/routing-context.md" "$d/.claude/hooks/routing-context.md"
  cp "$(dirname "$0")/heal-orchestra-docs.py" "$d/.claude/hooks/heal-orchestra-docs.py"
  printf '%s' "$d"
}
sandbox_run() { # dir
  printf '{"hook_event_name":"SessionStart"}' | \
    CLAUDE_PROJECT_DIR="$1" env -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID \
    CLAUDE_PROJECT_DIR="$1" python3 "$1/.claude/hooks/orchestra-session-start.py" 2>/dev/null
}

d=$(sandbox)
rm -f "$d/.claude/hooks/routing-context.md"
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"ROUTING-CONTEXT MISSING"*) pass=$((pass+1)); echo "  ok    R2     missing routing-context.md reddens visibly";;
  *) fail=$((fail+1)); echo "  FAIL  R2     missing routing-context.md silently swallowed: ${out:0:80}";;
esac

d=$(sandbox)
rm -f "$d/.claude/hooks/heal-orchestra-docs.py"
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"heal"*) pass=$((pass+1)); echo "  ok    R3     missing heal module surfaces a warning";;
  *) fail=$((fail+1)); echo "  FAIL  R3     missing heal module silently swallowed: ${out:0:80}";;
esac

echo "=== Part 7.3: upstream-drift line ==="
sandbox2() {
  # Same shape as sandbox() but also carries .claude/agents +
  # .claude/skills/orchestrator + docs/orchestra/claude-version.stamp, so the
  # drift and doctor-reminder checks have a real repo layout to read — plus a
  # SEPARATE "upstream/" copy (under $d/upstream) so the comparison is between
  # two distinct trees, not a directory diffed against itself.
  d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks" "$d/docs/orchestra" "$d/upstream/.claude"
  cp "$HOOK" "$d/.claude/hooks/orchestra-session-start.py"
  cp "$(dirname "$0")/routing-context.md" "$d/.claude/hooks/routing-context.md"
  cp "$(dirname "$0")/heal-orchestra-docs.py" "$d/.claude/hooks/heal-orchestra-docs.py"
  cp -r "$ROOT/.claude/agents" "$d/.claude/agents"
  cp -r "$ROOT/.claude/skills/orchestrator" "$d/.claude/skills/orchestrator" 2>/dev/null || mkdir -p "$d/.claude/skills/orchestrator"
  cp -r "$d/.claude/agents" "$d/upstream/.claude/agents"
  cp -r "$d/.claude/skills" "$d/upstream/.claude/skills"
  printf '{"model":"claude-fable-5","effortLevel":"low"}' > "$d/.claude/settings.json"
  printf '%s' "$d"
}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

d=$(sandbox2)
out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/upstream" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"Orchestra fork ahead of upstream by 0 files"*) pass=$((pass+1)); echo "  ok    DRIFT  identical checkout reports 0 files";;
  *) fail=$((fail+1)); echo "  FAIL  DRIFT  identical checkout did not report 0: ${out: -120}";;
esac

d=$(sandbox2)
printf 'drift' >> "$d/.claude/agents/builder.md"
out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/upstream" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"Orchestra fork ahead of upstream by 1 files"*) pass=$((pass+1)); echo "  ok    DRIFT  one changed file reports 1";;
  *) fail=$((fail+1)); echo "  FAIL  DRIFT  expected 1 file drift: ${out: -120}";;
esac

d=$(sandbox2)
out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/no-such-sibling" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"upstream-drift] skipped: sibling checkout not found"*) pass=$((pass+1)); echo "  ok    DRIFT  missing sibling skips with a reason, exits clean";;
  *) fail=$((fail+1)); echo "  FAIL  DRIFT  missing sibling did not skip cleanly: ${out: -120}";;
esac

echo "=== Part 8.4: claude-doctor-on-version-change reminder ==="
if command -v claude >/dev/null 2>&1; then
  d=$(sandbox2)
  printf '9.9.9' > "$d/docs/orchestra/claude-version.stamp"
  out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/no-such-sibling" sandbox_run "$d")
  rm -rf "$d"
  case "$out" in
    *"version changed since 9.9.9"*"run \`claude doctor\`"*) pass=$((pass+1)); echo "  ok    DOCTOR mismatched stamp prints the reminder";;
    *) fail=$((fail+1)); echo "  FAIL  DOCTOR mismatched stamp did not print the reminder: ${out: -160}";;
  esac
else
  echo "  skip  DOCTOR \`claude\` not on PATH — cannot test the mismatched-stamp arm"
fi

d=$(sandbox2)
current=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$current" ]; then
  printf '%s' "$current" > "$d/docs/orchestra/claude-version.stamp"
  out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/no-such-sibling" sandbox_run "$d")
  case "$out" in
    *"run \`claude doctor\`"*) fail=$((fail+1)); echo "  FAIL  DOCTOR matching stamp still printed the reminder";;
    *) pass=$((pass+1)); echo "  ok    DOCTOR matching stamp stays silent";;
  esac
else
  echo "  skip  DOCTOR \`claude\` not on PATH — cannot test the matching-stamp arm"
fi
rm -rf "$d"

echo "=== MODEL-GUARD: the confirmation line (ruling 2026-09-02, U11) ==="
d=$(sandbox2)
out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/upstream" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"[model] main session: claude-fable-5 / effort low"*"matrix OK"*"from settings.json"*)
    pass=$((pass+1)); echo "  ok    MODEL  on-matrix settings.json reads OK, names its source";;
  *) fail=$((fail+1)); echo "  FAIL  MODEL  on-matrix settings.json did not print OK: ${out: -160}";;
esac

d=$(sandbox2)
printf '{"model":"claude-wrong-tier-5","effortLevel":"high"}' > "$d/.claude/settings.json"
out=$(ORCHESTRA_UPSTREAM_CHECKOUT="$d/upstream" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"[model] main session: claude-wrong-tier-5 / effort high"*"VIOLATION"*)
    pass=$((pass+1)); echo "  ok    MODEL  off-matrix settings.json prints VIOLATION";;
  *) fail=$((fail+1)); echo "  FAIL  MODEL  off-matrix settings.json did not print VIOLATION: ${out: -160}";;
esac

d=$(sandbox2)
out=$(printf '{"hook_event_name":"SessionStart","model":"claude-sonnet-5","effort":{"level":"medium"}}' | \
  env -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID \
  CLAUDE_PROJECT_DIR="$d" ORCHESTRA_UPSTREAM_CHECKOUT="$d/upstream" python3 "$d/.claude/hooks/orchestra-session-start.py" 2>/dev/null)
rm -rf "$d"
case "$out" in
  *"[model] main session: claude-sonnet-5 / effort medium"*"VIOLATION"*"from payload"*)
    pass=$((pass+1)); echo "  ok    MODEL  a payload-carried model wins over settings.json, names its source";;
  *) fail=$((fail+1)); echo "  FAIL  MODEL  payload model was not read/preferred: ${out: -200}";;
esac

# DOCTOR_STUB: the doctor-reminder arm must never depend on a real `claude`.
# A stub binary on PATH makes the reminder observable on hosts without Claude
# Code installed, so this test stays green in CI and on a fresh machine.
d=$(sandbox2)
printf '9.9.9\n' > "$d/docs/orchestra/claude-version.stamp"
mkdir -p "$d/bin"
cat > "$d/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "0.0.1 (Claude Code) DOCTOR_STUB"
STUB
chmod +x "$d/bin/claude"
out=$(PATH="$d/bin:$PATH" ORCHESTRA_UPSTREAM_CHECKOUT="$d/no-such-sibling" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"version changed since 9.9.9"*"claude doctor"*)
    pass=$((pass+1)); echo "  ok    DOCTOR mismatched stamp prints the reminder";;
  *) fail=$((fail+1)); echo "  FAIL  DOCTOR mismatched stamp did not print the reminder: ${out: -160}";;
esac

echo; echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
