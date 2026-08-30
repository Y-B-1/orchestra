#!/usr/bin/env python3
"""Claude PreToolUse adapter — same floor as .cursor/hooks/block-dangerous.py."""
import os
import runpy

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
os.environ["ORCHESTRA_HOOK_RUNTIME"] = "claude"
runpy.run_path(
    os.path.join(root, ".cursor", "hooks", "block-dangerous.py"),
    run_name="__main__",
)
