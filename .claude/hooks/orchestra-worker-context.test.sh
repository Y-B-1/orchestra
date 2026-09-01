#!/usr/bin/env bash
# Self-test for orchestra-worker-context.py — layer 3 of the worker-routing
# guard (SPEC-claude-native §3): every SubagentStart gets the negative
# injected, including a sub-agent dispatched without a named definition
# (the one case `skills:` preload cannot cover).
#
# Run:  bash .claude/hooks/orchestra-worker-context.test.sh
set -u
H=./.claude/hooks/orchestra-worker-context.py
[ -f "$H" ] || { echo "run from the repo root" >&2; exit 1; }

TMPROOT=$(mktemp -d)
PROJDIR="$TMPROOT/has space"
mkdir -p "$PROJDIR"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0; fail=0

echo "=== a real SubagentStart payload gets the negative injected ==="
out=$(printf '%s' '{"hook_event_name":"SubagentStart","session_id":"s","agent_id":"a4e8098b04426409c","agent_type":"builder"}' \
  | CLAUDE_PROJECT_DIR="$PROJDIR" python3 "$H")
if printf '%s' "$out" | grep -q 'Do not load the orchestrator skill'; then
  pass=$((pass+1)); printf "  ok    additionalContext carries the negative\n"
else
  fail=$((fail+1)); printf "  FAIL  additionalContext missing the negative: %s\n" "$out"
fi
if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="SubagentStart"' 2>/dev/null; then
  pass=$((pass+1)); printf "  ok    hookEventName is SubagentStart\n"
else
  fail=$((fail+1)); printf "  FAIL  output is not valid hookSpecificOutput JSON: %s\n" "$out"
fi

echo
echo "=== an unnamed worker (no agent_type at all) still gets it ==="
out=$(printf '%s' '{"hook_event_name":"SubagentStart","agent_id":"a4e8098b04426409c"}' \
  | CLAUDE_PROJECT_DIR="$PROJDIR" python3 "$H")
if printf '%s' "$out" | grep -q 'Do not load the orchestrator skill'; then
  pass=$((pass+1)); printf "  ok    unnamed worker still gets the negative\n"
else
  fail=$((fail+1)); printf "  FAIL  unnamed worker missed the negative: %s\n" "$out"
fi

echo
echo "=== fails OPEN, never bricks the sub-agent's start ==="
rm -f "$PROJDIR/.orchestra/hook-failures.log"
out=$(printf '%s' 'not json at all' | CLAUDE_PROJECT_DIR="$PROJDIR" python3 "$H")
code=$?
if [ "$code" = "0" ] && [ "$out" = "{}" ]; then
  pass=$((pass+1)); printf "  ok    malformed stdin prints {} and exits 0\n"
else
  fail=$((fail+1)); printf "  FAIL  malformed stdin: exit=%s out=%s\n" "$code" "$out"
fi
if [ -f "$PROJDIR/.orchestra/hook-failures.log" ] && grep -q 'orchestra-worker-context' "$PROJDIR/.orchestra/hook-failures.log"; then
  pass=$((pass+1)); printf "  ok    hook-failures.log line written\n"
else
  fail=$((fail+1)); printf "  FAIL  hook-failures.log not written under CLAUDE_PROJECT_DIR\n"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
