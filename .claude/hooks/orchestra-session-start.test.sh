#!/usr/bin/env bash
# Proves orchestra-session-start.py hands the orchestrator identity block ONLY to
# the main session. A worker that receives it is told to dispatch sub-agents,
# which is how a fan-out becomes a fork bomb.
#
# Also proves the block POINTS AT the project skill `.claude/skills/orchestrator/`
# and no longer FORBIDS it. The hook is now a belt-and-braces reminder, not the
# only channel: the skill carries its own model-invocable `description`.
HOOK="$(dirname "$0")/orchestra-session-start.py"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
check() { # name | payload | expect-ctx(yes|no)
  out=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$ROOT" python3 "$HOOK" 2>/dev/null)
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
ctx() { printf '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$ROOT" python3 "$HOOK" 2>/dev/null; }
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
  CLAUDE_PROJECT_DIR="$1" printf '{"hook_event_name":"SessionStart"}' | \
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
: > "$d/.claude/hooks/routing-context.md"
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"ROUTING-CONTEXT MISSING"*) pass=$((pass+1)); echo "  ok    R2b    emptied routing-context.md reddens visibly";;
  *) fail=$((fail+1)); echo "  FAIL  R2b    emptied routing-context.md silently swallowed: ${out:0:80}";;
esac

d=$(sandbox)
rm -f "$d/.claude/hooks/heal-orchestra-docs.py"
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"heal"*) pass=$((pass+1)); echo "  ok    R3     missing heal module surfaces a warning";;
  *) fail=$((fail+1)); echo "  FAIL  R3     missing heal module silently swallowed: ${out:0:80}";;
esac

echo "=== the optional host addendum follows the package block ==="
d=$(sandbox)
printf 'HOST-ONLY-ADDENDUM-TEXT' > "$d/.claude/hooks/routing-context.host.md"
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"ORCHESTRA-ROUTE-V1"*"HOST-ONLY-ADDENDUM-TEXT"*) pass=$((pass+1)); echo "  ok    HOST   routing-context.host.md text follows the package block";;
  *) fail=$((fail+1)); echo "  FAIL  HOST   host addendum missing or out of order: ${out:0:120}";;
esac

d=$(sandbox)
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"routing-context.host"*) fail=$((fail+1)); echo "  FAIL  HOSTN  a host addendum marker leaked with no host file present";;
  *) pass=$((pass+1)); echo "  ok    HOSTN  absent routing-context.host.md leaves no marker";;
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
  printf '%s' "$d"
}

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

d=$(sandbox2)
unset ORCHESTRA_UPSTREAM_CHECKOUT
out=$(sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"upstream-drift] skipped: sibling checkout not found at (ORCHESTRA_UPSTREAM_CHECKOUT unset)"*) pass=$((pass+1)); echo "  ok    DRIFT  unset env var skips with a reason, exits clean";;
  *) fail=$((fail+1)); echo "  FAIL  DRIFT  unset env var did not skip cleanly: ${out: -120}";;
esac

echo "=== Part 8.4: claude-doctor-on-version-change reminder ==="
d=$(sandbox2)
printf '9.9.9' > "$d/docs/orchestra/claude-version.stamp"
mkdir -p "$d/bin"
cat > "$d/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "0.0.1 (Claude Code) DOCTOR_STUB"
STUB
chmod +x "$d/bin/claude"
# DOCTOR_STUB: the mismatched arm never depends on a real claude — a stub
# binary on PATH makes the reminder observable on hosts without claude too.
out=$(PATH="$d/bin:$PATH" ORCHESTRA_UPSTREAM_CHECKOUT="$d/no-such-sibling" sandbox_run "$d")
rm -rf "$d"
case "$out" in
  *"version changed since 9.9.9"*"run \`claude doctor\`"*) pass=$((pass+1)); echo "  ok    DOCTOR mismatched stamp prints the reminder";;
  *) fail=$((fail+1)); echo "  FAIL  DOCTOR mismatched stamp did not print the reminder: ${out: -160}";;
esac

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

echo; echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
