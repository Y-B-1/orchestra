#!/usr/bin/env bash
# Direct unit coverage of the native heal module's public surface — SPEC-native.md
# §1 moved this file from `.cursor/hooks/`; R3 (the failure-visible arm for a
# MISSING module) lives in orchestra-session-start.test.sh by deliberate design
# — that is where the failure is observed. This file instead proves the module
# ITSELF is importable and its two entry points exist and run cleanly, so a
# broken move (bad syntax, a renamed function) reddens here first. It also
# proves the three install.sh self-test cases (filled charter never shrinks,
# missing ## Orchestra appended, an outside AGENTS.md symlink refused) directly
# against the source, and that the Cursor shim fails loudly when the source
# it forwards to is absent.
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/heal-orchestra-docs.py"
SHIM="$HERE/../../.cursor/hooks/heal-orchestra-docs.py"
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

# Fixtures: a temp project tree with docs/orchestra/*.framework.md present, so
# heal never falls back to "no framework on disk". The AGENTS.framework.md
# fixture deliberately carries no "## Orchestra" heading, so a missing block
# exercises the module's own fallback text rather than whatever heading the
# live repo framework currently happens to have.
mk_fixture() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/docs/orchestra"
  cat > "$d/docs/orchestra/AGENTS.framework.md" <<'EOF'
# Project charter (CLAUDE.md)

Fixture framework carrying no Orchestra section, so heal falls back to its
own hardcoded block text.
EOF
  cat > "$d/docs/orchestra/AGENT-MEMORY.framework.md" <<'EOF'
# Agent memory — <project>

## How to fill

- fixture framework memory index.
EOF
  echo "$d"
}

echo "=== a filled CLAUDE.md never shrinks ==="
fx=$(mk_fixture)
cat > "$fx/CLAUDE.md" <<'EOF'
## Who you are

A filled project charter with real content that heal must not remove.

## Orchestra

When the orchestrator skill is loaded, the main session is the orchestrator.
Routing: `.claude/skills/orchestrator/references/flow.json`.
EOF
before=$(wc -c < "$fx/CLAUDE.md" | tr -d ' ')
(cd "$fx" && printf '{}' | python3 "$HOOK" >/dev/null)
after=$(wc -c < "$fx/CLAUDE.md" | tr -d ' ')
check "filled CLAUDE.md size did not shrink ($before -> $after)" $([ "$after" -ge "$before" ]; echo $?)
check "filled CLAUDE.md content preserved" $(grep -q '## Who you are' "$fx/CLAUDE.md"; echo $?)
rm -rf "$fx"

echo "=== a missing ## Orchestra block is appended ==="
fx=$(mk_fixture)
cat > "$fx/CLAUDE.md" <<'EOF'
## Who you are

A filled project charter with no Orchestra block yet.
EOF
(cd "$fx" && printf '{}' | python3 "$HOOK" >/dev/null)
check "## Orchestra appended" $(grep -q '## Orchestra' "$fx/CLAUDE.md"; echo $?)
check "appended block names the .claude flow.json path" $(grep -q '.claude/skills/orchestrator/references/flow.json' "$fx/CLAUDE.md"; echo $?)
check "original content preserved" $(grep -q '## Who you are' "$fx/CLAUDE.md"; echo $?)
rm -rf "$fx"

echo "=== AGENTS.md -> \$HOME/.claude/CLAUDE.md is refused and recreated as CLAUDE.md ==="
fx=$(mk_fixture)
cat > "$fx/CLAUDE.md" <<'EOF'
## Who you are

A filled project charter.
EOF
ln -s "$HOME/.claude/CLAUDE.md" "$fx/AGENTS.md"
(cd "$fx" && printf '{}' | python3 "$HOOK" >/dev/null)
if [ -L "$fx/AGENTS.md" ]; then
  tgt=$(readlink "$fx/AGENTS.md")
  check "AGENTS.md now symlinks to CLAUDE.md (got $tgt)" $([ "$tgt" = "CLAUDE.md" ]; echo $?)
else
  check "AGENTS.md now symlinks to CLAUDE.md (not a symlink at all)" 1
fi
rm -rf "$fx"

echo "=== Cursor shim fails loudly (never silently succeeds) when the source it forwards to is absent ==="
fx=$(mktemp -d)
mkdir -p "$fx/.cursor/hooks"
cp "$SHIM" "$fx/.cursor/hooks/heal-orchestra-docs.py"
out=$(cd "$fx" && printf '{}' | python3 .cursor/hooks/heal-orchestra-docs.py 2>&1)
rc=$?
check "shim exits non-zero with the .claude source absent" $([ "$rc" -ne 0 ]; echo $?)
check "shim never prints the success JSON when the source is absent" $(printf '%s' "$out" | grep -qx '{}'; test $? -ne 0; echo $?)
rm -rf "$fx"

echo; echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
