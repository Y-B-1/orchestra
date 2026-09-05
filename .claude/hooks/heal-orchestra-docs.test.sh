#!/usr/bin/env bash
# Direct unit coverage of the native heal module's public surface — SPEC-native.md
# §1 moved this file from `.cursor/hooks/`; R3 (the failure-visible arm for a
# MISSING module) lives in orchestra-session-start.test.sh by deliberate design
# — that is where the failure is observed. This file instead proves the module
# ITSELF is importable and its two entry points exist and run cleanly, so a
# broken move (bad syntax, a renamed function) reddens here first.
HOOK="$(dirname "$0")/heal-orchestra-docs.py"
pass=0; fail=0
check() { # name | condition(0/1)
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "  ok    $1";
  else fail=$((fail+1)); echo "  FAIL  $1"; fi
}

echo "=== the module imports and exposes heal_agents/heal_memory ==="
out=$(python3 - "$HOOK" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("heal_orchestra_docs", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert callable(mod.heal_agents), "heal_agents missing/not callable"
assert callable(mod.heal_memory), "heal_memory missing/not callable"
print("OK")
PY
)
check "importable, exposes heal_agents and heal_memory" $([ "$out" = "OK" ]; echo $?)

echo "=== running as a sessionStart hook prints {} and exits 0 ==="
out=$(printf '{}' | python3 "$HOOK" 2>/dev/null)
rc=$?
check "prints valid JSON" $(printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' > /dev/null 2>&1; echo $?)
check "exits 0" $rc

echo; echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
