#!/usr/bin/env bash
# Self-test for orchestra-block-nested.py — the no-nested-subagents rail.
#
# WHY THIS FILE EXISTS (wave D2, 2026-08-31). The hook shipped with no test and
# keyed on `agent_type` alone. Nothing could tell you whether it still fired:
# the deny path and the allow path both exit 0 (the DECISION is in the JSON
# body, not the exit code), so a schema drift would disarm it in total silence.
# Every case below asserts on permissionDecision, which is the only thing that
# is actually load-bearing.
#
# The WORKER fixture is a REAL captured PreToolUse payload (Claude Code,
# 2026-08-31, from inside a builder subagent) with tool_name swapped to Agent.
# If a future Claude Code stops sending agent_id, case "bare worker" goes red.
#
# Run:  bash .claude/hooks/orchestra-block-nested.test.sh
set -u
H="$(dirname "$0")/orchestra-block-nested.py"
[ -f "$H" ] || { echo "hook not found next to this test" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
# t WANT '<json payload>' '<label>'
t() {
  got=$(printf '%s' "$2" | python3 "$H" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)
  [ -n "$got" ] || got="(no decision emitted)"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); printf "  ok    %-5s %s\n" "$got" "$3"
  else fail=$((fail+1)); printf "  FAIL  %-5s (wanted %s) %s\n" "$got" "$1" "$3"; fi
}

echo "=== a WORKER must not fan out ==="
t deny '{"hook_event_name":"PreToolUse","tool_name":"Agent","session_id":"s","agent_id":"a4e8098b04426409c","agent_type":"builder","permission_mode":"auto"}' \
  "real captured worker payload — id AND type"
t deny '{"tool_name":"Agent","agent_id":"a4e8098b04426409c"}' \
  "bare worker — agent_id only, NO agent_type (the D2 hole: this used to ALLOW)"
t deny '{"tool_name":"Task","agent_id":"a4e8098b04426409c"}' \
  "the Task spelling of the same tool"
t deny '{"tool_name":"Agent","agentId":"a4e8098b04426409c"}' \
  "camelCase agentId"
t deny '{"tool_name":"Agent","agent_type":"builder"}' \
  "legacy: type only, no id — still a worker"
t deny '{"tool_name":"Agent","agentType":"builder"}' \
  "camelCase agentType"

echo
echo "=== the MAIN SESSION owns all fan-out ==="
t allow '{"hook_event_name":"PreToolUse","tool_name":"Agent","session_id":"s","permission_mode":"auto"}' \
  "no identity field at all — the orchestrator dispatching"
t allow '{"tool_name":"Agent","agent_id":"","agent_type":""}' \
  "identity keys present but EMPTY — still the main session"

echo
echo "=== only Agent/Task are gated ==="
t allow '{"tool_name":"Bash","agent_id":"a4e8098b04426409c"}' \
  "a worker running Bash is not fanning out"
t allow '{"tool_name":"Read","agent_id":"a4e8098b04426409c"}' \
  "a worker reading a file is not fanning out"

echo
echo "=== fails OPEN, never bricks the session ==="
t allow 'not json at all' "unparseable stdin"
t allow '{}' "empty object"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
