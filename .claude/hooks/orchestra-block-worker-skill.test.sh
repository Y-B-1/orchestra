#!/usr/bin/env bash
# Self-test for orchestra-block-worker-skill.py — layer 2 of the worker-routing
# guard (SPEC-claude-native §3): a worker must not invoke the orchestrator skill.
#
# Unlike orchestra-block-nested.py, this hook's decision is the EXIT CODE plus
# a stderr message (PreToolUse deny-by-exit-2), not a JSON permissionDecision
# body — so each case here asserts on exit code, and the deny cases also assert
# the exact stderr text.
#
# Run:  bash .claude/hooks/orchestra-block-worker-skill.test.sh
set -u
H=./.claude/hooks/orchestra-block-worker-skill.py
[ -f "$H" ] || { echo "run from the repo root" >&2; exit 1; }

TMPROOT=$(mktemp -d)
PROJDIR="$TMPROOT/has space"
mkdir -p "$PROJDIR"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0; fail=0
last_err=""

# t WANT_EXIT '<json payload>' '<label>'
t() {
  err_file=$(mktemp)
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$PROJDIR" python3 "$H" 2>"$err_file" 1>/dev/null
  got=$?
  last_err=$(cat "$err_file"); rm -f "$err_file"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); printf "  ok    %-3s %s\n" "$got" "$3"
  else fail=$((fail+1)); printf "  FAIL  %-3s (wanted %s) %s\n" "$got" "$1" "$3"; fi
}

echo "=== a WORKER invoking the orchestrator skill is denied ==="
t 2 '{"hook_event_name":"PreToolUse","tool_name":"Skill","agent_id":"a4e8098b04426409c","agent_type":"builder","tool_input":{"skill":"orchestrator"}}' \
  "worker, id AND type, orchestrator skill"
want='Worker sub-agents do not route. Execute your brief; your rails are preloaded.'
if [ "$last_err" = "$want" ]; then pass=$((pass+1)); printf "  ok    stderr matches exactly\n"
else fail=$((fail+1)); printf "  FAIL  stderr: %q (wanted %q)\n" "$last_err" "$want"; fi

echo
echo "=== a WORKER invoking any OTHER skill is fine ==="
t 0 '{"tool_name":"Skill","agent_id":"a4e8098b04426409c","tool_input":{"skill":"react-doctor"}}' \
  "worker, orchestrator's not the target — react-doctor allowed"

echo
echo "=== the MAIN SESSION owns routing ==="
t 0 '{"tool_name":"Skill","tool_input":{"skill":"orchestrator"}}' \
  "no identity field at all — the orchestrator invoking itself"

echo
echo "=== agent_type alone is still a worker (legacy label-only case) ==="
t 2 '{"tool_name":"Skill","agent_type":"builder","tool_input":{"skill":"orchestrator"}}' \
  "type only, no id — still denied"

echo
echo "=== tool_input.name is accepted as well as .skill ==="
t 2 '{"tool_name":"Skill","agent_id":"a4e8098b04426409c","tool_input":{"name":"orchestrator"}}' \
  "skill name via tool_input.name"

echo
echo "=== fails OPEN, never bricks the session ==="
rm -f "$PROJDIR/.orchestra/hook-failures.log"
t 0 'not json at all' "unparseable stdin exits 0"
if [ -f "$PROJDIR/.orchestra/hook-failures.log" ] && grep -q 'orchestra-block-worker-skill' "$PROJDIR/.orchestra/hook-failures.log"; then
  pass=$((pass+1)); printf "  ok    hook-failures.log line written\n"
else
  fail=$((fail+1)); printf "  FAIL  hook-failures.log not written under CLAUDE_PROJECT_DIR\n"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
