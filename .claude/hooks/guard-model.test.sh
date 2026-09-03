#!/usr/bin/env bash
# Self-test for guard-model.py — the main-session model lock (MODEL-GUARD,
# ruling 2026-09-02 U11: fable 5.1 at low effort, invoked every time, hook or
# guardrail, not up for debate).
#
# Run:  bash .claude/hooks/guard-model.test.sh
set -u
H=./.claude/hooks/guard-model.py
[ -f "$H" ] || { echo "run from the repo root" >&2; exit 1; }

pass=0; fail=0
t() { # want(allow|deny) | payload | label | [env=VAL]
  want="$1"; payload="$2"; label="$3"; env_arg="${4:-}"
  got=$(printf '%s' "$payload" | env $env_arg python3 "$H" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)
  [ -n "$got" ] || got="(no decision)"
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf "  ok    %-5s %s\n" "$got" "$label"
  else fail=$((fail+1)); printf "  FAIL  %-5s (wanted %s) %s\n" "$got" "$want" "$label"; fi
}

echo "=== a switch to the locked model+effort is allowed ==="
t allow '{"hook_event_name":"PreModelSwitch","to_model":"claude-fable-5","effort":{"level":"low"}}' \
  "fable-5 / low — on matrix (U14)"
t allow '{"hook_event_name":"PreModelSwitch","to_model":"claude-fable-5"}' \
  "fable-5, no effort field on the payload"

echo
echo "=== a switch off the locked model is denied ==="
t deny '{"hook_event_name":"PreModelSwitch","to_model":"claude-wrong-tier-5","effort":{"level":"low"}}' \
  "wrong-tier-5 — the exact scenario the ruling names"
t deny '{"hook_event_name":"PreModelSwitch","to_model":"claude-sonnet-5","effort":{"level":"medium"}}' \
  "sonnet-5 — a builder model requested for the main session"

echo
echo "=== a switch to the right model but wrong effort is denied ==="
t deny '{"hook_event_name":"PreModelSwitch","to_model":"claude-fable-5","effort":{"level":"high"}}' \
  "fable-5 at high effort"

echo
echo "=== escape hatch: ORCHESTRA_MODEL_UNLOCK=1 in the process env allows anything ==="
t allow '{"hook_event_name":"PreModelSwitch","to_model":"claude-wrong-tier-5"}' \
  "wrong-tier-5 with the escape hatch set" "ORCHESTRA_MODEL_UNLOCK=1"

echo
echo "=== fails OPEN, never bricks the session ==="
t allow 'not json at all' "unparseable stdin"
t allow '{"hook_event_name":"PreModelSwitch"}' "no to_model on the payload at all"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
