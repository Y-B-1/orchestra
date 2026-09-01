#!/usr/bin/env bash
# Self-test for sync-agent-config.py — the one Python generator: .claude/ is
# source, .cursor/ is generated. Builds a fixture host in a scratch dir, runs
# the generator against it with --root, and asserts every generated family,
# --check idempotency, and each SPEC arm 1/1b/1c/2/3/4/6/7/8/11 mutation.
#
# Run:  bash docs/orchestra/sync-agent-config.test.sh
set -u
GEN=./docs/orchestra/sync-agent-config.py
[ -f "$GEN" ] || { echo "run from the repo root" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/host"

pass=0; fail=0
ok() { pass=$((pass+1)); printf "  ok    %s\n" "$1"; }
bad() { fail=$((fail+1)); printf "  FAIL  %s : %s\n" "$1" "$2"; }

# --- fixture -----------------------------------------------------------

build_fixture() {
  local dst="$1"
  mkdir -p "$dst/.claude/agents" "$dst/.claude/skills/orchestrator/references" \
           "$dst/.claude/skills/orchestrator/scripts" "$dst/.claude/rules" \
           "$dst/.cursor/skills/orchestrator"

  cat > "$dst/.claude/agents/scout.md" <<'EOF'
---
name: scout
description: fixture scout — read-only recon.
model: claude-sonnet-5
effort: low
disallowedTools: Agent
---
You are the fixture Scout.
EOF

  cat > "$dst/.claude/agents/builder.md" <<'EOF'
---
name: builder
description: fixture builder — implements one ticket.
model: claude-sonnet-5
effort: medium
disallowedTools: Agent
skills:
  - orchestra-rails
  - rule-x
---
You are the fixture Builder.
EOF

  cat > "$dst/.claude/skills/orchestrator/SKILL.md" <<'EOF'
---
name: orchestrator
description: Route this repo's work through Orchestra.
---
Fixture orchestrator body. See references/design.md.
EOF

  cat > "$dst/.claude/skills/orchestrator/references/standing-rails.md" <<'EOF'
Honest exit codes, always. Commit only when the brief assigns it. Scratch
files live in the session scratchpad, never a tracked path.
EOF

  cat > "$dst/.claude/skills/orchestrator/references/design.md" <<'EOF'
# Design reference

Fixture design playbook text.
EOF

  cat > "$dst/.claude/skills/orchestrator/scripts/x.py" <<'EOF'
#!/usr/bin/env python3
print("fixture script x")
EOF

  cat > "$dst/.claude/rules/x.md" <<'EOF'
---
paths:
  - "src/x/**"
---
# Rule X

Fixture rule x body text.
EOF

  cat > "$dst/.cursor/skills/orchestrator/models.md" <<'EOF'
Fixture Cursor pool economics — hand-maintained, never generated.
EOF
}

expect_drift() { # dir label needle
  local dir="$1" label="$2" needle="$3"
  local log="$TMP/$(basename "$dir").log"
  python3 "$GEN" --root "$dir" --check > "$log" 2>&1
  local code=$?
  if [ "$code" -eq 1 ] && grep -q -- "$needle" "$log"; then
    ok "$label"
  else
    bad "$label" "exit=$code needle='$needle' log: $(cat "$log")"
  fi
}

# --- build + first write -----------------------------------------------

build_fixture "$ROOT"

write_log="$TMP/write.log"
python3 "$GEN" --root "$ROOT" > "$write_log" 2>&1
code=$?
[ "$code" -eq 0 ] && ok "write exits 0" || bad "write exits 0" "exit $code: $(cat "$write_log")"

echo "=== each of the five generated families is written and printed ==="
check_written() {
  local rel="$1"
  if [ -f "$ROOT/$rel" ] && grep -q "wrote.*$rel" "$write_log"; then
    ok "wrote $rel"
  else
    bad "wrote $rel" "missing file or print line"
  fi
}
check_written ".claude/skills/orchestra-rails/SKILL.md"
check_written ".claude/skills/rule-x/SKILL.md"
check_written ".cursor/agents/scout.md"
check_written ".cursor/agents/builder.md"
check_written ".cursor/rules/x.mdc"
check_written ".cursor/skills/orchestrator/SKILL.md"
check_written ".cursor/skills/orchestrator/references/design.md"
check_written ".cursor/skills/orchestrator/references/standing-rails.md"
check_written ".cursor/skills/orchestrator/scripts/x.py"
check_written ".cursor/skills/orchestra-rails/SKILL.md"
check_written ".cursor/skills/rule-x/SKILL.md"

echo "=== CURSOR_ONLY_FILES: models.md untouched and skipped ==="
if grep -q "models.md" "$write_log"; then
  bad "models.md untouched" "was printed as written"
else
  ok "models.md untouched"
fi
if grep -q "Fixture Cursor pool economics" "$ROOT/.cursor/skills/orchestrator/models.md"; then
  ok "models.md content preserved"
else
  bad "models.md content preserved" "content changed"
fi

echo "=== --check exit 0 after a clean write ==="
check_log="$TMP/check.log"
python3 "$GEN" --root "$ROOT" --check > "$check_log" 2>&1
code=$?
[ "$code" -eq 0 ] && ok "--check exit 0" || bad "--check exit 0" "exit $code: $(cat "$check_log")"

echo "=== a second write is a no-op ==="
marker="$TMP/marker"
touch "$marker"
write2_log="$TMP/write2.log"
python3 "$GEN" --root "$ROOT" > "$write2_log" 2>&1
stale=$(find "$ROOT" -newer "$marker")
if [ -z "$stale" ] && ! grep -q "wrote" "$write2_log"; then
  ok "second write touches nothing"
else
  bad "second write touches nothing" "stale files: $stale ; log: $(cat "$write2_log")"
fi

echo "=== a rules-less root prints rules: none found ==="
NOROOT="$TMP/norules"
build_fixture "$NOROOT"
rm -rf "$NOROOT/.claude/rules"
noroot_out=$(python3 "$GEN" --root "$NOROOT" 2>&1)
if echo "$noroot_out" | grep -q "^rules: none found$"; then
  ok "rules: none found"
else
  bad "rules: none found" "$noroot_out"
fi

echo "=== importable pure functions ==="
py_out=$(python3 - "$ROOT" <<'PY'
import importlib.util, sys
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("sac", "docs/orchestra/sync-agent-config.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

src = mod.orchestra_rails_source(root)
assert set(src.keys()) == {"name", "sourceRel", "description", "body"}, src.keys()
assert src["name"] == "orchestra-rails", src
assert src["sourceRel"] == ".claude/skills/orchestrator/references/standing-rails.md", src
assert src["description"] == mod.ORCHESTRA_RAILS_DESCRIPTION, src

claude_text = (
    "---\n"
    "name: scout\n"
    "description: fixture scout.\n"
    "model: claude-sonnet-5\n"
    "effort: low\n"
    "disallowedTools: Agent\n"
    "---\n"
    "Body.\n"
)
out = mod.render_agent("scout", claude_text, "Rails body.")
front, _ = mod.split_md(out)
assert "readonly: true" in front, front
assert "effort" not in front, front

print("OK")
PY
)
if [ "$py_out" = "OK" ]; then
  ok "orchestra_rails_source + render_agent (readonly role) importable and correct"
else
  bad "orchestra_rails_source + render_agent (readonly role) importable and correct" "$py_out"
fi

# --- mutations, each starting from a fresh copy of the clean fixture ---

echo "=== SPEC arm mutations turn --check red ==="

d="$TMP/arm1"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.cursor/skills/orchestrator/references/design.md"
t = open(p).read()
open(p, "w").write(t.replace("Fixture", "Mutated", 1))
PY
expect_drift "$d" "arm1: mirror content differs (design.md hand-edited)" "references/design.md"

d="$TMP/arm1b"; cp -r "$ROOT" "$d"
mkdir -p "$d/.cursor/skills/design"
expect_drift "$d" "arm1b: orphan .cursor/skills dir with no .claude source" ".cursor/skills/design"

d="$TMP/arm1c"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.cursor/agents/scout.md"
t = open(p).read()
open(p, "w").write(t.replace("readonly: true\n", "", 1))
PY
expect_drift "$d" "arm1c: readonly: true dropped from a generated Cursor agent" "scout.md"

d="$TMP/arm2"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.claude/agents/builder.md"
t = open(p).read()
open(p, "w").write(t.replace("orchestra-rails", "orchestra-railz", 1))
PY
expect_drift "$d" "arm2: skills: typo resolves to nothing" "orchestra-railz"

d="$TMP/arm3"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import re, sys
p = sys.argv[1] + "/.claude/skills/orchestrator/SKILL.md"
t = open(p).read()
t = re.sub(r"\n---\n", "\ndisable-model-invocation: true\n---\n", t, count=1)
open(p, "w").write(t)
PY
expect_drift "$d" "arm3: disable-model-invocation on a preloaded skill" "disable-model-invocation"

d="$TMP/arm4"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.claude/agents/builder.md"
t = open(p).read()
open(p, "w").write(t.replace("  - orchestra-rails\n", "  - orchestra-rails\n  - orchestrator\n", 1))
PY
expect_drift "$d" "arm4: orchestrator added to an agent's skills:" "builder.md"

d="$TMP/arm6"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.claude/skills/orchestrator/SKILL.md"
t = open(p).read()
open(p, "w").write("\n" + t)
PY
expect_drift "$d" "arm6: blank line prepended before SKILL.md frontmatter" "orchestrator/SKILL.md"

d="$TMP/arm7"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.claude/agents/scout.md"
t = open(p).read()
open(p, "w").write(t.replace("disallowedTools: Agent\n", "", 1))
PY
expect_drift "$d" "arm7: disallowedTools: Agent dropped from an agent" "scout.md"

d="$TMP/arm8"; cp -r "$ROOT" "$d"
ln -s orchestrator "$d/.claude/skills/orchestrator-link"
expect_drift "$d" "arm8: .claude/skills/* entry is a symlink" "orchestrator-link"

d="$TMP/arm11"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.claude/agents/scout.md"
t = open(p).read()
open(p, "w").write(t + "\n## Standing rails\nPasted back in by mistake.\n")
PY
expect_drift "$d" "arm11: rails heading pasted back into a Claude agent body" "scout.md"

d="$TMP/arm12"; cp -r "$ROOT" "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.claude/agents/scout.md"
t = open(p).read()
t = t.replace("model: claude-sonnet-5\n", "model: claude-fable-5\n", 1)
t = t.replace("effort: low\n", "effort: high\n", 1)
open(p, "w").write(t)
PY
expect_drift "$d" "arm12: agent model/effort mismatches CLAUDE_MATRIX" "scout"

echo "=== minor: missing .cursor/skills/orchestrator/models.md prints a note, exit 0 ==="
d="$TMP/nomd"; cp -r "$ROOT" "$d"
rm "$d/.cursor/skills/orchestrator/models.md"
nomd_out=$(python3 "$GEN" --root "$d" 2>&1)
nomd_code=$?
if [ "$nomd_code" -eq 0 ] && echo "$nomd_out" | grep -q "^note:.*models.md"; then
  ok "missing models.md prints a note, exit 0"
else
  bad "missing models.md prints a note, exit 0" "exit=$nomd_code out: $nomd_out"
fi

echo "=== minor: --root with no value is a usage error, not a traceback ==="
badroot_out=$(python3 "$GEN" --root 2>&1)
badroot_code=$?
if [ "$badroot_code" -ne 0 ] && ! echo "$badroot_out" | grep -q "Traceback"; then
  ok "--root with no value: usage error, not a traceback"
else
  bad "--root with no value: usage error, not a traceback" "exit=$badroot_code out: $badroot_out"
fi

echo "=== minor: an agent role absent from CURSOR_MATRIX prints a note, not silently skipped ==="
d="$TMP/ghost"; cp -r "$ROOT" "$d"
cat > "$d/.claude/agents/ghost.md" <<'EOF'
---
name: ghost
description: fixture role with no CURSOR_MATRIX entry.
model: claude-sonnet-5
effort: medium
disallowedTools: Agent
---
You are the fixture Ghost.
EOF
ghost_out=$(python3 "$GEN" --root "$d" 2>&1)
if echo "$ghost_out" | grep -q "^note:.*ghost"; then
  ok "role absent from CURSOR_MATRIX prints a note"
else
  bad "role absent from CURSOR_MATRIX prints a note" "$ghost_out"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
