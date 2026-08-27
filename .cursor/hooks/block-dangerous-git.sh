#!/usr/bin/env bash
# Cursor beforeShellExecution hook: blocks destructive git commands.
# stdin: JSON with the command to run; stdout: permission JSON; exit 0 always.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("command",""))' 2>/dev/null || true)"

deny() {
  printf '{"permission":"deny","userMessage":"Blocked by orchestra guardrail: %s","agentMessage":"This command is blocked by the orchestra guardrail hook. Destructive git operations require the user to run them manually. Reason: %s"}' "$1" "$1"
  exit 0
}

case "$cmd" in
  *"git push --force"*|*"git push -f"*|*"push --force-with-lease"*) deny "force push" ;;
  *"git reset --hard"*)            deny "hard reset discards work" ;;
  *"git clean -f"*|*"git clean -fd"*|*"git clean -xf"*) deny "git clean deletes untracked files" ;;
  *"git branch -D"*)               deny "force branch delete" ;;
  *"git checkout ."*|*"git checkout -- ."*|*"git restore ."*) deny "bulk discard of working tree changes" ;;
  *"git stash"*)                   deny "stash is repo-wide and unsafe with worktrees" ;;
  *"git rebase"*)                  deny "history rewrite while agents may hold refs" ;;
  *"git commit --amend"*)          deny "history rewrite while agents may hold refs" ;;
esac

printf '{"permission":"allow"}'
