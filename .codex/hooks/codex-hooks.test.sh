#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOKS="$ROOT/.codex/hooks"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_source() {
  local payload=$1
  local source=$2
  local output
  local status
  set +e
  output=$(cd "$ROOT" && printf '%s' "$payload" | "$HOOKS/run-source-hook.sh" "$source" 2>&1)
  status=$?
  set -e
  printf '%s\n%s' "$status" "$output"
}

forbidden='{"session_id":"codex-hooks-test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
forbidden_result=$(run_source "$forbidden" '.claude/hooks/block-dangerous.py')
[[ $forbidden_result == *'"permissionDecision": "deny"'* ]] || fail "destructive command was not denied through the wrapper: $forbidden_result"
[[ $forbidden_result == *"hard reset discards work"* ]] || fail "destructive denial reason was not surfaced: $forbidden_result"

benign='{"session_id":"codex-hooks-test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}'
benign_result=$(run_source "$benign" '.claude/hooks/block-dangerous.py')
[[ $benign_result == *'"permissionDecision": "allow"'* ]] || fail "benign command was denied through the wrapper: $benign_result"

SOURCE_ROOT="$TMP_ROOT/source-wrapper"
git init -q "$SOURCE_ROOT"
mkdir -p "$SOURCE_ROOT/.claude/hooks" "$SOURCE_ROOT/.codex/hooks"
cp "$ROOT/.claude/hooks/block-dangerous.py" "$SOURCE_ROOT/.claude/hooks/"
cp "$HOOKS/run-source-hook.sh" "$SOURCE_ROOT/.codex/hooks/"
bypass_payload='{"session_id":"bypass-test","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
set +e
bypass_out=$(cd "$SOURCE_ROOT" && printf '%s' "$bypass_payload" | .codex/hooks/run-source-hook.sh .claude/hooks/block-dangerous.py 2>&1)
bypass_status=$?
set -e
[[ $bypass_out == *'"permissionDecision": "deny"'* ]] || fail "Codex permission_mode bypass reached a source guard: $bypass_status $bypass_out"
mkdir -p "$SOURCE_ROOT/.claude"
touch "$SOURCE_ROOT/.claude/.bypass-guards"
set +e
marker_out=$(cd "$SOURCE_ROOT" && printf '%s' "$benign" | .codex/hooks/run-source-hook.sh .claude/hooks/block-dangerous.py 2>&1)
marker_status=$?
set -e
[[ $marker_status == 2 && $marker_out == *'.bypass-guards'* ]] || fail "source wrapper silently honored the bypass marker: $marker_status $marker_out"

ROUTING_ROOT="$TMP_ROOT/routing"
mkdir -p "$ROUTING_ROOT/docs/orchestra"
patch_four='{"session_id":"four-files","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/a.ts\n*** Update File: src/b.ts\n*** Add File: src/c.ts\n*** Delete File: src/d.ts\n*** End Patch"}}'
patch_a='{"session_id":"four-files","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/a.ts\n*** End Patch"}}'
patch_b='{"session_id":"four-files","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/b.ts\n*** End Patch"}}'
patch_c='{"session_id":"four-files","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: src/c.ts\n*** End Patch"}}'
patch_d='{"session_id":"four-files","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Delete File: src/d.ts\n*** End Patch"}}'
for payload in "$patch_a" "$patch_b" "$patch_c"; do
  routing_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$payload")
  [[ $routing_out == *'"permissionDecision": "allow"'* ]] || fail "one of the first three apply_patch targets was denied: $routing_out"
done
routing_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_d")
[[ $routing_out == *'"permissionDecision": "deny"'* ]] || fail "the fourth distinct apply_patch target was not denied: $routing_out"

state_exempt='{"session_id":"state-exempt","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/a.ts\n*** Update File: src/b.ts\n*** Add File: src/c.ts\n*** Update File: docs/orchestra/STATE.md\n*** End Patch"}}'
state_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$state_exempt")
[[ $state_out == *'"permissionDecision": "deny"'* ]] || fail "tracked STATE.md was exempted from the native routing threshold: $state_out"

printf '# Orchestra state\nstatus: **OPEN**\n' > "$ROUTING_ROOT/docs/orchestra/STATE.md"
open_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_four")
[[ $open_out == *'"permissionDecision": "deny"'* ]] || fail "tracked STATE.md incorrectly authorized Codex routing: $open_out"

outside_patch='{"session_id":"outside-root","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: ../escape.ts\n*** End Patch"}}'
outside_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$outside_patch")
[[ $outside_out == *'"permissionDecision": "deny"'* ]] || fail "outside-root patch target was not denied: $outside_out"

malformed_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<'not-json')
[[ $malformed_out == *'"permissionDecision": "deny"'* ]] || fail "malformed mutating hook input failed open: $malformed_out"
missing_session='{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/missing.ts\n*** End Patch"}}'
missing_out=$(CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$missing_session")
[[ $missing_out == *'"permissionDecision": "deny"'* ]] || fail "missing session id failed open: $missing_out"

worker_out=$(ORCHESTRA_CODEX_WORKER=1 CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_four")
[[ $worker_out == *'"permissionDecision": "allow"'* ]] || fail "explicit Codex worker marker did not authorize ticket routing: $worker_out"
orca_worker_out=$(ORCA_WORKTREE_ID=wt-1 CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_four")
[[ $orca_worker_out == *'"permissionDecision": "allow"'* ]] || fail "Orca worker environment did not authorize ticket routing: $orca_worker_out"
orca_coordinator_out=$(ORCA_WORKTREE_ID=wt-1 ORCA_WORKSPACE_ID=workspace-1 CLAUDE_PROJECT_DIR="$ROUTING_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_four")
[[ $orca_coordinator_out == *'"permissionDecision": "deny"'* ]] || fail "Orca coordinator environment was mistaken for a worker: $orca_coordinator_out"

BASH_ROOT="$TMP_ROOT/bash-routing"
mkdir -p "$BASH_ROOT"
bash_a='{"session_id":"bash-files","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf x > src/a.ts"}}'
bash_b='{"session_id":"bash-files","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf x | tee src/b.ts"}}'
bash_c='{"session_id":"bash-files","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sed -i s/x/y/ src/c.ts"}}'
bash_d='{"session_id":"bash-files","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf x >> src/d.ts"}}'
for payload in "$bash_a" "$bash_b" "$bash_c"; do
  bash_out=$(CLAUDE_PROJECT_DIR="$BASH_ROOT" "$HOOKS/require-open-run.py" <<<"$payload")
  [[ $bash_out == *'"permissionDecision": "allow"'* ]] || fail "one of the first three Bash write targets was denied: $bash_out"
done
bash_out=$(CLAUDE_PROJECT_DIR="$BASH_ROOT" "$HOOKS/require-open-run.py" <<<"$bash_d")
[[ $bash_out == *'"permissionDecision": "deny"'* ]] || fail "fourth Bash write target was not denied: $bash_out"
outside_bash='{"session_id":"outside-bash","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf x > /tmp/codex-routing-escape"}}'
outside_bash_out=$(CLAUDE_PROJECT_DIR="$BASH_ROOT" "$HOOKS/require-open-run.py" <<<"$outside_bash")
[[ $outside_bash_out == *'"permissionDecision": "deny"'* ]] || fail "outside-root Bash write target was filtered instead of denied: $outside_bash_out"

PERSIST_ROOT="$TMP_ROOT/persist"
mkdir -p "$PERSIST_ROOT"
printf 'not a directory\n' > "$PERSIST_ROOT/.orchestra"
persist_out=$(CLAUDE_PROJECT_DIR="$PERSIST_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_a")
[[ $persist_out == *'"permissionDecision": "deny"'* ]] || fail "routing persistence error failed open: $persist_out"

LEASE_ROOT="$TMP_ROOT/lease"
git init -q "$LEASE_ROOT"
mkdir -p "$LEASE_ROOT/docs/orchestra"
printf 'status: **OPEN**\n' > "$LEASE_ROOT/docs/orchestra/STATE.md"
set +e
lease_open_out=$("$HOOKS/coordinator-lease.py" acquire --root "$LEASE_ROOT" --session-id lease-owner 2>&1)
lease_open_status=$?
set -e
[[ $lease_open_status != 0 && $lease_open_out == *'STATE.md is OPEN'* ]] || fail "lease acquired over an OPEN tracked run: $lease_open_status $lease_open_out"
printf 'status: **CLOSED**\n' > "$LEASE_ROOT/docs/orchestra/STATE.md"
"$HOOKS/coordinator-lease.py" acquire --root "$LEASE_ROOT" --session-id lease-owner >/dev/null
printf 'status: **OPEN**\n' > "$LEASE_ROOT/docs/orchestra/STATE.md"
"$HOOKS/coordinator-lease.py" acquire --root "$LEASE_ROOT" --session-id lease-owner >/dev/null
leased_out=$(CLAUDE_PROJECT_DIR="$LEASE_ROOT" "$HOOKS/require-open-run.py" <<<"$patch_four")
[[ $leased_out == *'"permissionDecision": "deny"'* ]] || fail "lease belonging to a different session authorized routing: $leased_out"
lease_patch=${patch_four//four-files/lease-owner}
leased_out=$(CLAUDE_PROJECT_DIR="$LEASE_ROOT" "$HOOKS/require-open-run.py" <<<"$lease_patch")
[[ $leased_out == *'"permissionDecision": "allow"'* ]] || fail "matching common-dir lease did not authorize routing: $leased_out"
set +e
other_lease_out=$("$HOOKS/coordinator-lease.py" acquire --root "$LEASE_ROOT" --session-id other-session 2>&1)
other_lease_status=$?
set -e
[[ $other_lease_status != 0 && $other_lease_out == *'lease already belongs'* ]] || fail "another session took over a live lease: $other_lease_status $other_lease_out"
"$HOOKS/coordinator-lease.py" status --root "$LEASE_ROOT" --session-id lease-owner >/dev/null
lease_status_out=$("$HOOKS/coordinator-lease.py" status --root "$LEASE_ROOT" --session-id other-session)
[[ $lease_status_out != *'lease-owner'* ]] || fail "lease status exposed the owner session id: $lease_status_out"
"$HOOKS/coordinator-lease.py" release --root "$LEASE_ROOT" --session-id lease-owner >/dev/null

worker_worktree_commands=(
  'git worktree add ../other feature'
  '/usr/bin/git worktree remove ../other'
  'env git worktree prune'
  'command git worktree move ../one ../two'
  'git -C /tmp/repo worktree repair'
)
for command in "${worker_worktree_commands[@]}"; do
  worker_worktree=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  worker_guard_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_worktree")
  [[ $worker_guard_out == *'"permissionDecision": "deny"'* ]] || fail "worker git worktree mutation was not denied ($command): $worker_guard_out"
done

worker_control_commands=(
  'python3 .codex/hooks/coordinator-lease.py status --session-id worker'
  'cat .git/codex-orchestra/coordinator-lease.json'
  'rm .orchestra/routing/parent.json'
)
for command in "${worker_control_commands[@]}"; do
  worker_control=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  worker_control_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_control")
  [[ $worker_control_out == *'"permissionDecision": "deny"'* ]] || fail "worker reached coordinator control state ($command): $worker_control_out"
done

worker_state_patches=(
  $'{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Update File: docs/orchestra/STATE.md\\n*** End Patch"}}'
  $'{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Update File: ./docs/orchestra/../orchestra/STATE.md\\n*** End Patch"}}'
  $'{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Update File: .orchestra/state.json\\n*** End Patch"}}'
  $'{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Update File: ./.orchestra/./state.json\\n*** End Patch"}}'
)
for payload in "${worker_state_patches[@]}"; do
  worker_state_out=$(ORCHESTRA_CODEX_WORKER=1 CLAUDE_PROJECT_DIR="$ROOT" "$HOOKS/worker-guard.py" <<<"$payload")
  [[ $worker_state_out == *'"permissionDecision": "deny"'* ]] || fail "worker apply_patch reached coordinator state: $worker_state_out"
done

worker_state_commands=(
  'cat docs/orchestra/STATE.md'
  "cat '$ROOT/docs/orchestra/STATE.md'"
  'sed -n 1p ./docs/orchestra/../orchestra/STATE.md'
  'cd docs/orchestra && rg status STATE.md'
  'printf x > .orchestra/state.json'
  'python3 -c '\''open("./.orchestra/./state.json", "w").write("x")'\'''
  'cd .orchestra && cat state.json'
)
for command in "${worker_state_commands[@]}"; do
  worker_state=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  worker_state_out=$(ORCHESTRA_CODEX_WORKER=1 CLAUDE_PROJECT_DIR="$ROOT" "$HOOKS/worker-guard.py" <<<"$worker_state")
  [[ $worker_state_out == *'"permissionDecision": "deny"'* ]] || fail "worker Bash reached coordinator state ($command): $worker_state_out"
done
coordinator_state_out=$(CLAUDE_PROJECT_DIR="$ROOT" "$HOOKS/worker-guard.py" <<<"${worker_state_patches[0]}")
[[ $coordinator_state_out == *'"permissionDecision": "allow"'* ]] || fail "main coordinator was blocked from its state: $coordinator_state_out"
worker_near_state='{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat docs/orchestra/STATE.md.bak .orchestra/state.json.bak"}}'
worker_near_state_out=$(ORCHESTRA_CODEX_WORKER=1 CLAUDE_PROJECT_DIR="$ROOT" "$HOOKS/worker-guard.py" <<<"$worker_near_state")
[[ $worker_near_state_out == *'"permissionDecision": "allow"'* ]] || fail "worker was blocked from non-control lookalike paths: $worker_near_state_out"

no_env_worker_cases=(
  "$ROOT/docs/orchestra|Bash|cat STATE.md"
  "$ROOT/docs/orchestra|Bash|printf x > STATE.md"
  "$ROOT/docs/orchestra|apply_patch|*** Begin Patch
*** Update File: STATE.md
*** End Patch"
  "$ROOT/.orchestra|Bash|cat state.json"
  "$ROOT/.orchestra|Bash|printf x > state.json"
  "$ROOT/.orchestra|apply_patch|*** Begin Patch
*** Update File: state.json
*** End Patch"
  "$ROOT|Bash|printf x > docs/orchestra/STA''TE.md"
  "$ROOT|Bash|printf x > .orchestra/sta''te.json"
)
for worker_case in "${no_env_worker_cases[@]}"; do
  case_cwd=${worker_case%%|*}
  case_remainder=${worker_case#*|}
  case_tool=${case_remainder%%|*}
  case_command=${case_remainder#*|}
  case_payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":sys.argv[2],"tool_input":{"command":sys.argv[3]}}))' "$case_cwd" "$case_tool" "$case_command")
  case_out=$(env -u CLAUDE_PROJECT_DIR ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$case_payload")
  [[ $case_out == *'"permissionDecision": "deny"'* ]] || fail "no-env worker reached coordinator state ($case_cwd: $case_command): $case_out"
done
no_env_coordinator_payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"coordinator","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Update File: STATE.md\\n*** End Patch"}}))' "$ROOT/docs/orchestra")
no_env_coordinator_out=$(env -u CLAUDE_PROJECT_DIR -u ORCHESTRA_CODEX_WORKER -u ORCHESTRA_CODEX_READ_ONLY -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID "$HOOKS/worker-guard.py" <<<"$no_env_coordinator_payload")
[[ $no_env_coordinator_out == *'"permissionDecision": "allow"'* ]] || fail "no-env main coordinator was blocked from its state: $no_env_coordinator_out"
no_env_near_state_payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":"cat STATE.md.bak"}}))' "$ROOT/docs/orchestra")
no_env_near_state_out=$(env -u CLAUDE_PROJECT_DIR ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$no_env_near_state_payload")
[[ $no_env_near_state_out == *'"permissionDecision": "allow"'* ]] || fail "no-env worker was blocked from non-control cwd lookalike: $no_env_near_state_out"

worker_dynamic_commands=(
  'cat docs/orchestra/STAT?.md'
  'tee docs/orchestra/STAT*.md'
  'sed -i s/x/y/ docs/orchestra/STAT[E].md'
  'cat docs/orchestra/STAT[^X].md'
  'cat docs/orchestra/STAT[[:alpha:]].md'
  'printf x > .orchestra/stat{e}.json'
  'cat docs/{orchestra,other}/STATE.md'
  'cat $WORKER_INPUT_PATH'
  'echo `pwd`'
  'cat ~+/docs/orchestra/STATE.md'
  "bash -o posix -c 'cat docs/orchestra/STAT?.md'"
  'cat <(printf literal)'
  'cat >(printf literal)'
  'cat docs/orchestra/@(STATE).md'
  "rg 'STAT?.md' src"
  'printf "%s" "*.md"'
  'printf "%s" "$value"'
  '(bash)'
  '( sh )'
  '(python3)'
  '(exec bash)'
  'bash 0<&0'
  'sh 3<&0'
  'python3 0<&0'
  'printf literal 2>&1'
  'printf "%s" "(literal)"'
)
worker_dynamic_commands+=("$(python3 -c 'print("cat docs/orchestra/STA\\\\\\nTE.md", end="")')")
for command in "${worker_dynamic_commands[@]}"; do
  dynamic_payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$ROOT" "$command")
  dynamic_out=$(env -u CLAUDE_PROJECT_DIR ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$dynamic_payload")
  [[ $dynamic_out == *'"permissionDecision": "deny"'* && $dynamic_out == *'literal-only'* ]] || fail "worker dynamic shell syntax did not fail closed ($command): $dynamic_out"
done
literal_worker='{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf literal"}}'
literal_worker_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$literal_worker")
[[ $literal_worker_out == *'"permissionDecision": "allow"'* ]] || fail "literal worker Bash control was denied: $literal_worker_out"
coordinator_dynamic='{"session_id":"coordinator","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf %s \\"*.md\\""}}'
coordinator_dynamic_out=$(env -u ORCHESTRA_CODEX_WORKER -u ORCHESTRA_CODEX_READ_ONLY -u ORCA_WORKTREE_ID -u ORCA_WORKSPACE_ID "$HOOKS/worker-guard.py" <<<"$coordinator_dynamic")
[[ $coordinator_dynamic_out == *'"permissionDecision": "allow"'* ]] || fail "main coordinator was subjected to worker literal-only Bash policy: $coordinator_dynamic_out"

worker_interactive_commands=(
  'bash'
  'zsh -i'
  'python3'
  'node --interactive'
  'bash -s'
  'bash -s ignored-argument'
  'sh -s'
  'python3 -'
  'python3 - ignored-argument'
  'node -'
  'bash --noprofile'
  'exec bash'
  'env bash -s'
  'command sh -s'
  '/bin/bash --noprofile'
  'env -i bash -s'
  '/usr/bin/env bash -s'
  'command -- bash -s'
  'sudo -u nobody bash -s'
  'nohup bash -s'
  'bash /dev/stdin'
  'python3 /dev/stdin'
  'bash /proc/self/fd/0'
  'python3 /dev/fd/0'
  'python3 -q'
  'python3.14 -q'
  'tclsh8.5'
  'psql-17 database'
)
for command in "${worker_interactive_commands[@]}"; do
  worker_interactive=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  worker_interactive_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_interactive")
  [[ $worker_interactive_out == *'"permissionDecision": "deny"'* ]] || fail "worker opened an unchecked interactive session ($command): $worker_interactive_out"
done
worker_noninteractive_commands=(
  # `print(1)` is independently denied by the literal-only parentheses rule;
  # `pass` isolates the interpreter payload classification exercised here.
  'python3 -c pass'
  'python3 script.py'
  'node -e 1'
  'python3.14 -c pass'
  'tclsh8.5 script.tcl'
  'psql-17 -f query.sql'
  'npm run build'
  'npm test'
)
for command in "${worker_noninteractive_commands[@]}"; do
  worker_noninteractive=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  worker_noninteractive_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_noninteractive")
  [[ $worker_noninteractive_out == *'"permissionDecision": "allow"'* ]] || fail "noninteractive literal command was denied ($command): $worker_noninteractive_out"
done
python3 - "$HOOKS/worker-guard.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("worker_guard", sys.argv[1])
worker_guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker_guard)

stdin_cases = [
    "python3 -u",
    "node --no-warnings",
    "bash -O extglob",
    "bash -o posix",
    "zsh -o shwordsplit",
    "bash --rcfile startup.sh",
    "python3 -W ignore",
    "python3 -W warning.py",
    "python3 -X dev",
    "node --require helper.js",
    "ruby -r helper.rb",
    "python3 script",
    "bash script",
    "node --redirect-warnings /tmp/warnings.js",
    "node --unknown script.js",
    "python3 --unknown script.py",
    "bash --unknown script.sh",
    "/bin/csh",
    "/bin/tcsh",
    "/bin/csh -f",
    "/bin/tcsh -v",
    "sqlite3",
    "sqlite3 database.db",
    "sqlite3 -readonly database.db",
    "psql",
    "psql database",
    "psql -d database",
    "psql postgresql://localhost/database",
    "python3.14",
    "/opt/runtime/bin/python3.14 -q",
    "perl5.34",
    "perl5.34 -w",
    "tclsh",
    "tclsh8.5 -encoding utf-8",
    "wish8.6",
    "node22 --no-warnings",
    "ruby3.3 -w",
    "php8.4 -n",
    "sqlite3.45 database.db",
    "psql-17",
]
noninteractive_cases = [
    "python3 -u script.py",
    "python3 -W ignore script.py",
    "python3 -X dev script.py",
    "python3 -m package",
    "node script.js",
    "node --no-warnings script.js",
    "node --require helper.js script.js",
    "ruby -e 1",
    "ruby script.rb",
    "perl -e 1",
    "perl script.pl",
    "php script.php",
    "bash -c pass",
    "bash script.sh",
    "bash ./script",
    "bash -O extglob script.sh",
    "bash -o posix script.sh",
    "zsh -o shwordsplit script.sh",
    "/bin/csh -c pass",
    "/bin/tcsh -c pass",
    "/bin/csh script.csh",
    "/bin/tcsh -f script.tcsh",
    'sqlite3 database.db "select 1"',
    "sqlite3 database.db < query.sql",
    'psql -d database -c "select 1"',
    'psql --command="select 1" database',
    "psql -f query.sql",
    "psql -d database < query.sql",
    "python3.14 -q script.py",
    "/opt/runtime/bin/python3.14 script.py",
    "perl5.34 -e 1",
    "perl5.34 script.pl",
    "tclsh -encoding utf-8 script.tcl",
    "wish8.6 script.tcl",
    "node22 -e 1",
    "node22 script.js",
    "ruby3.3 script.rb",
    "php8.4 script.php",
    'sqlite3.45 database.db "select 1"',
    'psql-17 -d database -c "select 1"',
]

for command in stdin_cases:
    if not worker_guard.stdin_capable_command(command):
        raise SystemExit(f"stdin-capable alias was not classified: {command}")
for command in noninteractive_cases:
    if worker_guard.stdin_capable_command(command):
        raise SystemExit(f"modeled noninteractive alias was rejected: {command}")
PY
worker_tty='{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"bash -lc cat","tty":true}}'
worker_tty_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_tty")
[[ $worker_tty_out == *'"permissionDecision": "deny"'* ]] || fail "worker opened a TTY whose later stdin would bypass hooks: $worker_tty_out"
worker_stdin_bridge=$(python3 -c 'import json; print(json.dumps({"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"bash -lc '\''read cmd; eval \"$cmd\"'\''"}}))')
worker_stdin_bridge_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_stdin_bridge")
[[ $worker_stdin_bridge_out == *'"permissionDecision": "deny"'* ]] || fail "worker opened a persistent shell stdin bridge: $worker_stdin_bridge_out"

worker_mcp='{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"mcp__filesystem__write_file","tool_input":{"path":"src/forbidden.ts"}}'
worker_mcp_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_mcp")
[[ $worker_mcp_out == *'"permissionDecision": "deny"'* ]] || fail "worker inherited an unguarded MCP tool: $worker_mcp_out"
worker_local='{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"write_file","tool_input":{"path":"src/forbidden.ts"}}'
worker_local_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$worker_local")
[[ $worker_local_out == *'"permissionDecision": "deny"'* ]] || fail "worker inherited an unguarded local tool: $worker_local_out"
readonly_patch=${patch_a//four-files/readonly}
readonly_out=$(ORCHESTRA_CODEX_WORKER=1 ORCHESTRA_CODEX_READ_ONLY=1 "$HOOKS/worker-guard.py" <<<"$readonly_patch")
[[ $readonly_out == *'"permissionDecision": "deny"'* ]] || fail "read-only worker apply_patch was not denied: $readonly_out"

readonly_shell_writes=(
  'printf x > src/forbidden.ts'
  'printf x | tee src/forbidden.ts'
  'sed -i s/x/y/ src/forbidden.ts'
  'touch src/forbidden.ts'
  'mkdir src/forbidden'
  'cp src/a.ts src/forbidden.ts'
  'mv src/a.ts src/forbidden.ts'
  'rm src/forbidden.ts'
  'chmod +x src/forbidden.ts'
  'git add src/forbidden.ts'
  'git commit -m forbidden'
  'git switch feature'
  'npm run build'
  'npx prettier --write src/forbidden.ts'
  'git config user.name forbidden'
  'git update-ref refs/heads/forbidden HEAD'
  'git diff --output=src/forbidden.patch'
  'rsync src/a.ts src/forbidden.ts'
  'tar -xf archive.tar'
  'unzip archive.zip'
  'file -C -m custom.magic'
  'file --compile -m custom.magic'
)
for command in "${readonly_shell_writes[@]}"; do
  readonly_shell_payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"readonly","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  readonly_shell_out=$(ORCHESTRA_CODEX_WORKER=1 ORCHESTRA_CODEX_READ_ONLY=1 "$HOOKS/worker-guard.py" <<<"$readonly_shell_payload")
  [[ $readonly_shell_out == *'"permissionDecision": "deny"'* ]] || fail "read-only worker shell mutation was allowed ($command): $readonly_shell_out"
done

readonly_safe_commands=(
  'git status --short'
  'git diff -- src/file.ts'
  'git log -1 --oneline'
  'git show HEAD:src/file.ts'
  'git ls-files src'
  'git rev-parse --show-toplevel'
  'git worktree list'
  'rg -n pattern src'
  'sed -n 1,20p src/file.ts'
  'cat src/file.ts'
  'head -n 5 src/file.ts'
  'tail -n 5 src/file.ts'
  'find src -maxdepth 1 -type f'
  'ls -la'
  'pwd'
  'wc -l src/file.ts'
  'stat src/file.ts'
  'file src/file.ts'
  'readlink AGENTS.md'
  'shasum src/file.ts'
  'printf diagnostic'
)
for command in "${readonly_safe_commands[@]}"; do
  readonly_safe_payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id":"readonly","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")
  readonly_safe_out=$(ORCHESTRA_CODEX_WORKER=1 ORCHESTRA_CODEX_READ_ONLY=1 "$HOOKS/worker-guard.py" <<<"$readonly_safe_payload")
  [[ $readonly_safe_out == *'"permissionDecision": "allow"'* ]] || fail "safe read-only inspection was denied ($command): $readonly_safe_out"
done
marker_command='{"session_id":"worker","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"touch .claude/.bypass-guards"}}'
marker_guard_out=$(ORCHESTRA_CODEX_WORKER=1 "$HOOKS/worker-guard.py" <<<"$marker_command")
[[ $marker_guard_out == *'"permissionDecision": "deny"'* ]] || fail "worker bypass-marker creation was not denied: $marker_guard_out"
orca_marker_guard_out=$(ORCA_WORKTREE_ID=wt-1 "$HOOKS/worker-guard.py" <<<"$marker_command")
[[ $orca_marker_guard_out == *'"permissionDecision": "deny"'* ]] || fail "Orca worker environment did not activate the worker guard: $orca_marker_guard_out"

SESSION_ROOT="$TMP_ROOT/session"
mkdir -p "$SESSION_ROOT"
printf 'unchanged\n' > "$SESSION_ROOT/marker"
before=$(find "$SESSION_ROOT" -type f -print -exec shasum {} \; | sort)
session_payload='{"session_id":"session-start","hook_event_name":"SessionStart","source":"startup"}'
session_out=$(CLAUDE_PROJECT_DIR="$SESSION_ROOT" "$HOOKS/session-start.py" <<<"$session_payload")
after=$(find "$SESSION_ROOT" -type f -print -exec shasum {} \; | sort)
[[ $before == "$after" ]] || fail "SessionStart mutated the filesystem"
[[ $session_out == *'inactive'* && $session_out == *'explicit'* ]] || fail "SessionStart did not disclose explicit opt-in: $session_out"
[[ $session_out == *'session-start'* && $session_out == *'coordinator-lease.py acquire'* ]] || fail "SessionStart omitted the explicit session-bound lease command: $session_out"

SUBAGENT_ROOT="$TMP_ROOT/subagent"
mkdir -p "$SUBAGENT_ROOT/docs/orchestra"
printf '%s\n' '{"roles":{"builder":{"model":"gpt-5.6-sol","effort":"high"}}}' > "$SUBAGENT_ROOT/docs/orchestra/codex-models.json"
mkdir -p "$SUBAGENT_ROOT/.codex/agents"
printf 'sandbox_mode = "read-only"\n' > "$SUBAGENT_ROOT/.codex/agents/auditor.toml"
subagent_payload='{"session_id":"subagent-start","hook_event_name":"SubagentStart","agent_id":"agent-1","agent_type":"builder","model":"gpt-5.6-luna","model_reasoning_effort":"low"}'
subagent_out=$(CLAUDE_PROJECT_DIR="$SUBAGENT_ROOT" "$HOOKS/subagent-start.py" <<<"$subagent_payload")
[[ $subagent_out == *'not the Orchestra coordinator'* && $subagent_out == *'must not spawn subagents'* ]] || fail "worker-negative context is missing: $subagent_out"
[[ $subagent_out == *'Model policy mismatch'* && $subagent_out == *'cannot stop startup'* ]] || fail "model mismatch warning or advisory limitation is missing: $subagent_out"

official_subagent_payload='{"session_id":"subagent-start","hook_event_name":"SubagentStart","agent_id":"agent-2","agent_type":"builder","permission_mode":"workspace-write"}'
official_subagent_out=$(CLAUDE_PROJECT_DIR="$SUBAGENT_ROOT" "$HOOKS/subagent-start.py" <<<"$official_subagent_payload")
[[ $official_subagent_out != *'Model policy mismatch'* ]] || fail "missing undocumented model fields caused a false mismatch: $official_subagent_out"
readonly_subagent_payload='{"session_id":"subagent-start","hook_event_name":"SubagentStart","agent_id":"agent-3","agent_type":"auditor","permission_mode":"workspace-write"}'
readonly_subagent_out=$(CLAUDE_PROJECT_DIR="$SUBAGENT_ROOT" "$HOOKS/subagent-start.py" <<<"$readonly_subagent_payload")
[[ $readonly_subagent_out != *'Model policy mismatch'* ]] || fail "approval-oriented permission_mode caused a false sandbox mismatch: $readonly_subagent_out"

echo "codex hook self-test: PASS"
