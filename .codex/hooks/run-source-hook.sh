#!/usr/bin/env bash
set -euo pipefail

SOURCE=${1:-}
case "$SOURCE" in
  .claude/hooks/*.sh|.claude/hooks/*.py) ;;
  *)
    echo "Codex source-hook wrapper: expected a .claude/hooks script" >&2
    exit 2
    ;;
esac

ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || {
  echo "Codex source-hook wrapper: cannot resolve the repository root" >&2
  exit 2
}
TARGET="$ROOT/$SOURCE"
if [[ ! -x "$TARGET" ]]; then
  echo "Codex source-hook wrapper: source hook is missing or not executable: $SOURCE" >&2
  exit 2
fi

if [[ -e "$ROOT/.claude/.bypass-guards" ]]; then
  echo "Codex source-hook wrapper: .claude/.bypass-guards is forbidden for Codex sessions" >&2
  exit 2
fi

INPUT=$(cat)
if ! SANITIZED=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
payload = json.load(sys.stdin)
payload.pop("permission_mode", None)
payload.pop("permissionMode", None)
json.dump(payload, sys.stdout, separators=(",", ":"))
'); then
  echo "Codex source-hook wrapper: malformed hook payload" >&2
  exit 2
fi

export CLAUDE_PROJECT_DIR="$ROOT"
printf '%s' "$SANITIZED" | "$TARGET"
