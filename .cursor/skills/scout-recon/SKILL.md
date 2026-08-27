---
name: scout-recon
description: How to brief and use the scout sub-agent for read-only codebase recon. Use before asking the user anything the code can answer, and as phase 1 of planning.
---

# Using the scout

Dispatch `scout` (readonly) whenever a question is answerable by the codebase. Multiple independent recon questions → one scout per area, dispatched in parallel.

## Brief template

```
You are doing read-only recon. Do not edit anything.
Questions:
1. <question>
2. <question>
Report: answers with file+symbol citations (no line numbers); observed conventions
(naming, tests, error handling) with one example each; exact verification commands
available (test/lint/typecheck/e2e) and where defined; risks and what you could
not determine. Mark every item confirmed / inferred / not found. Under 500 words.
```

## Rules for consuming the report

- "Inferred" and "not found" items are not facts; re-verify before a plan depends on them.
- The tooling section feeds ticket done_when commands — use the exact commands the scout quoted, never guessed ones.
- If the scout reports a product decision hiding in a question, that question goes to the user in the next frontier round.
