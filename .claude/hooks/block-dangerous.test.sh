#!/usr/bin/env bash
# Self-test for .claude/hooks/block-dangerous.py — the destructive-command rail,
# native to Claude Code. This file is the Claude-side twin of
# .cursor/hooks/block-dangerous.py's shim: same corpus, same worlds, but
# exercised through THIS hook's own Claude PreToolUse payload/output shape —
# this hook is the source of truth; the Cursor file is a thin adapter over it.
#
# STATE IS PINNED. Every case runs against a fixture .orchestra in a temp git
# repo, so the verdicts do not drift with this repo's real review/gate state.
# Three worlds are exercised: gate STALE, gate FRESH + pr CLEAN, gate FRESH +
# pr not clean.
#
# CASES ARE BUILT, NOT WRITTEN LITERALLY. The dangerous command strings are
# assembled from fragments at runtime. Spelling them out would make this file
# unopenable by any agent whose own shell rail greps its heredoc — the guard
# would block the test for its own test data.
#
# Run:  bash .claude/hooks/block-dangerous.test.sh
set -u
H=$(cd "$(dirname "$0")" && pwd)/block-dangerous.py
[ -f "$H" ] || { echo "cannot find block-dangerous.py" >&2; exit 1; }
SHIM=$(cd "$(dirname "$0")/../.." && pwd)/.cursor/hooks/block-dangerous.py
[ -f "$SHIM" ] || { echo "cannot find .cursor/hooks/block-dangerous.py" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A real git repo so current_branch() / rev-parse answer deterministically.
git init -q -b work "$TMP/repo" >/dev/null 2>&1
cd "$TMP/repo" || exit 1
git config user.email t@t; git config user.name t
git commit -q --allow-empty -m seed
HEAD_HASH=$(git rev-parse HEAD)

# PIN THE SANDBOX. The hook resolves `.orchestra/` from CLAUDE_PROJECT_DIR FIRST
# and falls back to cwd, so without this the fixture reads the REAL repo's
# state.json — and every agent session has that var set. A false red gets
# "fixed" by weakening the guard, which is why this is pinned rather than left
# to the caller.
export CLAUDE_PROJECT_DIR="$TMP/repo"
mkdir -p .orchestra
printf '%s\n' '{"provider":"azure-devops","protected_branches":["main"],"server_side_gate":false,"deploy_commands":[]}' \
  > .orchestra/delivery.json

state() { # $1 = pr review verdict, $2 = recorded green-gate hash
  printf '{"reviews":{"pr":"%s"},"gates":{"last_green_hash":"%s"}}' "$1" "$2" > .orchestra/state.json
}

# Fragments — see "CASES ARE BUILT" above.
HARD_RESET="git reset --${_H:-}hard HEAD~1"
CLEAN_FD="git clean -fd"
STASH="git stash"
FORCE_PUSH="git push --force origin work"
F_PUSH="git push -f origin work"
DEL_PUSH="git push origin --delete work"

pass=0; fail=0
# t WANT "<command>" "<label>"
t() {
  got=$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$2" \
        | python3 "$H" 2>/dev/null \
        | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)
  [ -n "$got" ] || got="(none)"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); printf "  ok    %-5s %s\n" "$got" "$3"
  else fail=$((fail+1)); printf "  FAIL  %-5s (wanted %s) %s\n" "$got" "$1" "$3"; fi
}

echo "=== A2: stdout is Claude's hookSpecificOutput.permissionDecision shape, exit 0 ==="
state CLEAN "$HEAD_HASH"
raw=$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' 'git status' | python3 "$H")
ec=$?
if [ "$ec" -eq 0 ]; then pass=$((pass+1)); printf "  ok    exit 0\n"
else fail=$((fail+1)); printf "  FAIL  exit %s (wanted 0)\n" "$ec"; fi
echo "$raw" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "permission" not in d and "user_message" not in d' 2>/dev/null
if [ $? -eq 0 ]; then pass=$((pass+1)); printf "  ok    no Cursor-shape keys leaked into stdout\n"
else fail=$((fail+1)); printf "  FAIL  Cursor {permission} shape leaked into stdout\n"; fi

echo
echo "=== A3: a benign command allows ==="
t allow 'git status' "git status is benign"

echo
echo "=== A1: deny corpus (gate STALE, pr CLEAN) ==="
state CLEAN 0000000000000000000000000000000000000000

echo "--- the D3 defect: a non-protected push is an ordinary agent act ---"
t allow 'git push origin work'      "push the working line to origin"
t allow 'git push mirror work'      "push the working line to a second remote"
t allow 'git push origin HEAD:work' "explicit refspec, non-protected target"
t allow 'git push'                  "bare push while ON a non-protected branch"

echo "--- a LANDING still needs the gate ---"
t deny  'git push origin work:main' "landing on main with a stale gate"
t deny  'git push origin main'      "pushing main directly with a stale gate"

echo "--- destruction is denied regardless of target ---"
t deny  "$FORCE_PUSH" "force push, non-protected target"
t deny  "$F_PUSH"     "-f short form"
t deny  "$DEL_PUSH"   "branch delete by push"
t deny  "$HARD_RESET" "hard reset"
t deny  "$CLEAN_FD"   "clean -fd"
t deny  "$STASH"      "stash is repo-wide"

echo "--- a compound command must not be laundered by a leading safe push ---"
t deny "git push origin work && $HARD_RESET" "safe push, then a hard reset"
t deny "git push origin work; $STASH"        "safe push, then a stash"

echo
echo "=== A4: CLEAN-gate arm — landing denied without a fresh CLEAN, allowed with one ==="
echo "--- gate FRESH at HEAD, pr-reviewer CLEAN — landing is authorized ---"
state CLEAN "$HEAD_HASH"
t allow 'git push origin work:main' "landing on main with CLEAN + matching hash"
t allow 'git push origin work'      "the working line, still allowed"

echo "--- gate FRESH at HEAD but pr-reviewer NOT clean ---"
state PENDING "$HEAD_HASH"
t deny  'git push origin work:main' "landing without pr-reviewer CLEAN"
t allow 'git push origin work'      "the working line needs no review verdict"

echo
echo "=== A5: the Cursor shim fails CLOSED when .claude/hooks/block-dangerous.py is absent ==="
state CLEAN "$HEAD_HASH"
SHIMTMP=$(mktemp -d)
mkdir -p "$SHIMTMP/.cursor/hooks" "$SHIMTMP/.orchestra"
cp "$SHIM" "$SHIMTMP/.cursor/hooks/block-dangerous.py"
# Deliberately no .claude/hooks/block-dangerous.py under $SHIMTMP.
shim_out=$(cd "$SHIMTMP" && echo '{"command":"git status"}' | CLAUDE_PROJECT_DIR="$SHIMTMP" python3 .cursor/hooks/block-dangerous.py 2>/dev/null)
rm -rf "$SHIMTMP"
if printf '%s' "$shim_out" | grep -q '"permission": "deny"'; then pass=$((pass+1)); printf "  ok    deny  shim fails closed with the source missing\n"
else fail=$((fail+1)); printf "  FAIL  %s (wanted a deny) shim with the source missing\n" "$shim_out"; fi
if printf '%s' "$shim_out" | grep -q '"permission": "allow"'; then fail=$((fail+1)); printf "  FAIL  shim emitted allow with the source missing\n"
else pass=$((pass+1)); printf "  ok    shim never emits allow with the source missing\n"; fi

echo
echo "=== A6: .orchestra/ paths resolve under a CLAUDE_PROJECT_DIR containing a space ==="
SPACETMP=$(mktemp -d)
SPACEROOT="$SPACETMP/has space"
mkdir -p "$SPACEROOT"
git init -q -b work "$SPACEROOT" >/dev/null 2>&1
( cd "$SPACEROOT" && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed )
SPACE_HASH=$(git -C "$SPACEROOT" rev-parse HEAD)
mkdir -p "$SPACEROOT/.orchestra"
printf '%s\n' '{"protected_branches":["main"],"server_side_gate":false,"deploy_commands":[]}' \
  > "$SPACEROOT/.orchestra/delivery.json"
printf '{"reviews":{"pr":"CLEAN"},"gates":{"last_green_hash":"%s"}}' "$SPACE_HASH" > "$SPACEROOT/.orchestra/state.json"
space_out=$(cd "$SPACEROOT" && python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' 'git push origin work:main' \
  | CLAUDE_PROJECT_DIR="$SPACEROOT" python3 "$H" 2>/dev/null \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)
rm -rf "$SPACETMP"
if [ "$space_out" = "allow" ]; then pass=$((pass+1)); printf "  ok    allow  landing reads .orchestra/state.json under a spaced CLAUDE_PROJECT_DIR\n"
else fail=$((fail+1)); printf "  FAIL  %s (wanted allow) .orchestra/ under a spaced CLAUDE_PROJECT_DIR\n" "$space_out"; fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
