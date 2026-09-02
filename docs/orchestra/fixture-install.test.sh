#!/usr/bin/env bash
# Proves install.sh keeps a Cursor-only host working (SPEC §7): every .cursor/**
# file present before install is present after, with the same frontmatter keys,
# and every line that differs traces to a named row in this file's allowed-delta
# list. Runs anywhere with bash, python3, git, diff, tar — no Node, no
# hard-coded home-directory path, no machine-specific input (repair round 2's
# portability contract).
set -uo pipefail
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; FAIL=1; }

UP="$(cd "$(dirname "$0")/../.." && pwd)"                          # package root, resolved from this script's own location — never hard-coded
SCRATCH="${SCRATCH:-$(mktemp -d)}"                                 # honour the caller's scratch dir; default to a fresh temp dir when unset
export PYTHONDONTWRITEBYTECODE=1                                   # every python3 the two installs spawn must never write .cursor/hooks/__pycache__/*.pyc — machine- and version-specific bytes that must never reach cursor.diff

FIX="$SCRATCH/fixture"; rm -rf "$FIX"; mkdir -p "$FIX/pkg-old" "$FIX/old" "$FIX/new"
git -C "$UP" archive 5860b59 | tar -x -C "$FIX/pkg-old"           # the pre-port package, read-only extraction

mkhost() {
  git -C "$1" init -q
  git -C "$1" -c user.name=fixture -c user.email=f@x commit -q --allow-empty -m init
  git -C "$1" remote add origin https://github.com/example/host.git
}
mkhost "$FIX/old"
mkhost "$FIX/new"

( cd "$FIX/old" && bash "$FIX/pkg-old/install.sh" )       > "$FIX/install-old.log"    2>&1; old_exit=$?;   echo "old-exit:$old_exit"
( cd "$FIX/new" && bash "$FIX/pkg-old/install.sh" )       > "$FIX/install-new-0.log"  2>&1; seed_exit=$?;  echo "seed-exit:$seed_exit"
( cd "$FIX/new" && bash "$UP/install.sh" )                > "$FIX/install-new.log"    2>&1; new_exit=$?;   echo "new-exit:$new_exit"
[ "$new_exit" -eq 0 ] || bad "the ported install.sh exited $new_exit on the upgraded host"
[ "$seed_exit" -eq 0 ] || bad "the pre-port install.sh (seeding the 0.3.0 host) exited $seed_exit"
if [ "$old_exit" -ne 0 ]; then
  say "note: the 0.3.0 install itself exited $old_exit — recorded, never patched around; see install-old.log"
fi

( cd "$FIX" && diff -r old/.cursor new/.cursor ) > "$FIX/cursor.diff" 2>&1; diff_exit=$?; echo "diff-exit:$diff_exit"

diff "$FIX/cursor.diff" "$UP/docs/orchestra/fixtures/cursor-diff.expected" > "$FIX/expect.log" 2>&1; expect_exit=$?; echo "expect-exit:$expect_exit"
[ "$expect_exit" -eq 0 ] || { bad "cursor.diff does not match the committed expectation:"; cat "$FIX/expect.log"; }

( cd "$FIX/new" && python3 docs/orchestra/sync-agent-config.py --check ) > "$FIX/check.log" 2>&1; check_exit=$?; echo "check-exit:$check_exit"
[ "$check_exit" -eq 0 ] || { bad "sync-agent-config.py --check failed on the upgraded host:"; cat "$FIX/check.log"; }

grep -nE '__pycache__|\.pyc\b' "$FIX/cursor.diff" >/dev/null 2>&1; pyc_in_diff=$?; echo "pyc-in-diff:$pyc_in_diff"
[ "$pyc_in_diff" -eq 1 ] || bad "cursor.diff carries a __pycache__/.pyc hunk — PYTHONDONTWRITEBYTECODE did not reach every python3"

find "$FIX/old" "$FIX/new" -name '__pycache__' -o -name '*.pyc' 2>/dev/null | grep . >/dev/null 2>&1; pyc_on_disk=$?; echo "pyc-on-disk:$pyc_on_disk"
[ "$pyc_on_disk" -eq 1 ] || bad "a __pycache__/.pyc file survives on a fixture host"

# --- row-2: the three stale top-level orchestrator files are pruned (r3-2) ---
row2=$(grep -c '^Only in old/.cursor/skills/orchestrator: ' "$FIX/cursor.diff")
[ "$row2" = "3" ] || bad "expected 3 'Only in old/.cursor/skills/orchestrator:' lines (flow.json, briefs.md, STATE.template.md), got $row2"

# --- row 9: files that must NEVER appear as an actual diff hunk (CURSOR_ONLY / hand-maintained) ---
# Scoped to real diff-header/Only-in lines for the exact path — a prose mention
# of the same path inside an unrelated agent-body hunk is not a hit.
row9=$(python3 - "$FIX/cursor.diff" <<'PY'
import re, sys
paths = ["skills/orchestrator/models.md", "hooks.json", "hooks/session-start.py", "hooks/block-nested-subagents.py"]
text = open(sys.argv[1]).read()
hits = []
for p in paths:
    base = p.rsplit("/", 1)[-1]
    if re.search(rf"^diff -r .*{re.escape(p)} ", text, re.M):
        hits.append(p)
    if re.search(rf"^Only in (old|new)/\.cursor[^:]*: {re.escape(base)}$", text, re.M):
        hits.append(p)
print("\n".join(hits))
PY
)
[ -z "$row9" ] || bad "cursor.diff carries a real hunk for a CURSOR_ONLY path: $row9"

# --- row 11: upgrade-path prune arms (round 3) — .claude/ and docs/ prunes, checked on new/ directly since diff -r only covers .cursor/ ---
n=$(grep -c 'orchestra-block-dangerous' "$FIX/new/.claude/settings.json" 2>/dev/null); [ -z "$n" ] && n=0
[ "$n" = "0" ] || bad ".claude/settings.json on the upgraded host still names orchestra-block-dangerous.py"
grep -q 'removed stale .claude/hooks/orchestra-block-dangerous.py' "$FIX/install-new.log" || bad "install-new.log missing the orchestra-block-dangerous.py prune note"

ls "$FIX/new/.claude/hooks/orchestra-block-dangerous.py" >/dev/null 2>&1 && bad "stale .claude/hooks/orchestra-block-dangerous.py survives on the upgraded host"
ls "$FIX/new/.claude/orchestra-router.md" >/dev/null 2>&1 && bad "stale .claude/orchestra-router.md survives on the upgraded host"
ls "$FIX/new/docs/orchestra/generate-claude-agents.py" >/dev/null 2>&1 && bad "stale docs/orchestra/generate-claude-agents.py survives on the upgraded host"

for stale in flow.json briefs.md STATE.template.md; do
  ls "$FIX/new/.cursor/skills/orchestrator/$stale" >/dev/null 2>&1 && bad "stale .cursor/skills/orchestrator/$stale survives on the upgraded host"
done

# --- the CLAUDE.md routing note (A23 #2): printed only on the upgrade, never on the fresh 0.3.0 install ---
grep -q 'host charter ## Orchestra block names a path removed in 0.4.0' "$FIX/install-new.log" || bad "install-new.log missing the stale-routing-pointer note"
grep -q 'host charter ## Orchestra block names a path removed in 0.4.0' "$FIX/install-old.log" && bad "install-old.log (fresh 0.3.0 install) unexpectedly prints the stale-routing-pointer note"

[ "$FAIL" -eq 0 ] && say "FIXTURE OK" || say "FIXTURE FAILED — fix the FAIL lines above"
exit "$FAIL"
