#!/usr/bin/env bash
# Self-test for .claude/hooks/block-dangerous.py — the destructive-command rail,
# native to Claude Code (SPEC-native.md §1). This file is the Claude-side twin of
# .cursor/hooks/block-dangerous.test.sh: same corpus, same worlds, but exercised
# through THIS hook's own Claude PreToolUse payload/output shape, since after the
# native port this file — not the Cursor one — is the source of truth.
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A real git repo so current_branch() / rev-parse answer deterministically.
git init -q -b feature "$TMP/repo" >/dev/null 2>&1
cd "$TMP/repo" || exit 1
git config user.email t@t; git config user.name t
git commit -q --allow-empty -m seed
HEAD_HASH=$(git rev-parse HEAD)

# PIN THE SANDBOX. The hook resolves `.orchestra/` from CLAUDE_PROJECT_DIR FIRST
# and falls back to cwd, so without this the fixture reads the REAL repo's
# state.json — and every agent session has that var set. The A4 arm then wants
# allow and gets deny, i.e. the gate is red in exactly the environment agents
# run it in. A false red gets "fixed" by weakening the guard, which is why this
# is pinned rather than left to the caller. `orchestra-session-start.test.sh`
# already sets it per invocation for the same reason.
export CLAUDE_PROJECT_DIR="$TMP/repo"
mkdir -p .orchestra
printf '%s\n' '{"provider":"azure-secondary","protected_branches":["main"],"server_side_gate":false,"deploy_commands":[]}' \
  > .orchestra/delivery.json

state() { # $1 = pr review verdict, $2 = recorded green-gate hash
  # B3 (2026-09-04): CLEAN also needs a review-record FILE named in reviews.pr_record.
  mkdir -p docs/orchestra/reviews
  printf 'test record\n' > docs/orchestra/reviews/test-batch.md
  printf '{"reviews":{"pr":"%s","pr_record":"docs/orchestra/reviews/test-batch.md"},"gates":{"last_green_hash":"%s"}}' "$1" "$2" > .orchestra/state.json
}
state_no_record() { # CLEAN + fresh hash but NO record file — must deny (B3)
  printf '{"reviews":{"pr":"%s"},"gates":{"last_green_hash":"%s"}}' "$1" "$2" > .orchestra/state.json
}

# Fragments — see "CASES ARE BUILT" above.
HARD_RESET="git reset --${_H:-}hard HEAD~1"
CLEAN_FD="git clean -fd"
STASH="git stash"
FORCE_PUSH="git push --force secondary feature"
F_PUSH="git push -f secondary feature"
DEL_PUSH="git push secondary --delete feature"

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
t allow 'git push secondary feature'      "push a feature branch to secondary"
t allow 'git push origin feature'      "push a feature branch to origin"
t allow 'git push secondary HEAD:feature' "explicit refspec, non-protected target"
t allow 'git push'                     "bare push while ON a non-protected branch"

echo "--- a LANDING still needs the gate ---"
t deny  'git push origin feature:main' "landing on main with a stale gate"
t deny  'git push origin main'         "pushing main directly with a stale gate"

echo "--- destruction is denied regardless of target ---"
t deny  "$FORCE_PUSH" "force push, non-protected target"
t deny  "$F_PUSH"     "-f short form"
t deny  "$DEL_PUSH"   "branch delete by push"
t deny  "$HARD_RESET" "hard reset"
t deny  "$CLEAN_FD"   "clean -fd"
t deny  "$STASH"      "stash is repo-wide"

echo "--- a compound command must not be laundered by a leading safe push ---"
t deny "git push secondary feature && $HARD_RESET" "safe push, then a hard reset"
t deny "git push secondary feature; $STASH"        "safe push, then a stash"

echo
echo "=== A4: CLEAN-gate arm — landing denied without a fresh CLEAN, allowed with one ==="
echo "--- gate FRESH at HEAD, pr-reviewer CLEAN — landing is authorized ---"
state CLEAN "$HEAD_HASH"
t allow 'git push origin feature:main' "landing on main with CLEAN + matching hash"
t allow 'git push origin main'         "pushing main directly with CLEAN + matching hash"
t allow 'git push secondary feature'      "a non-protected branch, still allowed"

echo "--- gate FRESH at HEAD, CLEAN, but NO review-record file (B3) ---"
state_no_record CLEAN "$HEAD_HASH"
t deny  'git push origin feature:main' "landing with CLEAN but no pr_record file"

echo "--- A30: a WORKER may not run git worktree commands ---"
state CLEAN "$HEAD_HASH"
got=$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","agent_id":"a-worker","tool_input":{"command":"git worktree add /tmp/x -b y"}}))' \
      | python3 "$H" 2>/dev/null \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)
if [ "$got" = "deny" ]; then pass=$((pass+1)); printf "  ok    deny  worker git worktree add (A30)\n"
else fail=$((fail+1)); printf "  FAIL  %s (wanted deny) worker git worktree add (A30)\n" "$got"; fi
t allow 'git worktree add /tmp/x -b y' "orchestrator (no agent_id) may still create worktrees"

echo "--- gate FRESH at HEAD but pr-reviewer NOT clean ---"
state PENDING "$HEAD_HASH"
t deny  'git push origin feature:main' "landing without pr-reviewer CLEAN"
t deny  'git push origin main'         "pushing main without pr-reviewer CLEAN"
t allow 'git push secondary feature'      "a non-protected branch needs no review verdict"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
