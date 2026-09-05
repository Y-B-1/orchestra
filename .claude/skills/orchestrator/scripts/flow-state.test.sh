#!/usr/bin/env bash
# Proves flow-state.py lets the orchestrator read `flow.json` ONE STATE AT A TIME.
# The graph is 48 KB / 30 states; inlining it into SKILL.md would spend the whole
# compaction-survivable budget on routing data the session needs one block of.
#
# It also proves the two things that break silently:
#  - the script resolves references/flow.json RELATIVE TO ITSELF, so it works from
#    any cwd (the orchestrator runs from the repo root, worktrees, anywhere);
#  - it survives a SPACE in the repo path (this repo lives under "Work Automation").
S="$(cd "$(dirname "$0")" && pwd)/flow-state.py"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok    $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL  $1 — $2"; }

run() { ( cd / && python3 "$S" "$@" 2>&1 ); }   # cd / proves self-relative resolution

echo "=== --list ==="
out=$(run --list); rc=$?
[ "$rc" -eq 0 ] && ok "--list exits 0" || bad "--list exits 0" "exit $rc"
case "$out" in *intake*) ok "--list names the entry state";; *) bad "--list names the entry state" "no 'intake'";; esac
n=$(printf '%s\n' "$out" | grep -c '^  ')
[ "$n" -ge 25 ] && ok "--list names every state ($n)" || bad "--list names every state" "only $n"

echo "=== one state ==="
out=$(run intake); rc=$?
[ "$rc" -eq 0 ] && ok "a known state exits 0" || bad "a known state exits 0" "exit $rc"
case "$out" in *'"if"'*) ok "a known state prints its routes";; *) bad "a known state prints its routes" "no routes in output";; esac
# the whole graph must NOT come back for one state
[ "$(printf '%s' "$out" | wc -c)" -lt 20000 ] && ok "one state is not the whole graph" || bad "one state is not the whole graph" "output >= 20 KB"

echo "=== plan.pickup ==="
out=$(run plan.pickup); rc=$?
[ "$rc" -eq 0 ] && ok "plan.pickup exits 0" || bad "plan.pickup exits 0" "exit $rc"
case "$out" in *scout*) ok "plan.pickup names scout";; *) bad "plan.pickup names scout" "no 'scout'";; esac
case "$out" in *plan.redteam*) ok "plan.pickup names plan.redteam";; *) bad "plan.pickup names plan.redteam" "no 'plan.redteam'";; esac

echo "=== --meta ==="
out=$(run --meta roles); rc=$?
[ "$rc" -eq 0 ] && ok "--meta roles exits 0" || bad "--meta roles exits 0" "exit $rc"
case "$out" in *builder*) ok "--meta roles names the roster";; *) bad "--meta roles names the roster" "no 'builder'";; esac

echo "=== the failure direction (a check that cannot go red is not a check) ==="
out=$(run no-such-state); rc=$?
[ "$rc" -eq 1 ] && ok "an unknown state exits 1" || bad "an unknown state exits 1" "exit $rc"
case "$out" in *intake*) ok "an unknown state lists what IS available";; *) bad "an unknown state lists what IS available" "no state names offered";; esac
out=$(run --meta no-such-key); rc=$?
[ "$rc" -eq 1 ] && ok "an unknown --meta key exits 1" || bad "an unknown --meta key exits 1" "exit $rc"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && ok "no argument exits 1" || bad "no argument exits 1" "exit $rc"

echo; echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
