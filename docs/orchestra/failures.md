# Failures — the context regression suite

This file is the regression suite for the most expensive text in the repo: `CLAUDE.md`,
`.claude/rules/*.md`, and skill bodies (`.claude/skills/**`). An edit to that text has no
test today except this one.

**What goes in:** whenever a line is added to or changed in `CLAUDE.md`, `.claude/rules/*.md`,
or a skill, *because an agent failed* — record the prompt or brief that caused the failure and
the expected behavior the new line exists to produce. The janitor appends entries here from its
batch-close CONTEXT-GAP clustering (`cleanup.md` step 6): a cluster with 2+ hits proposing this
file as its fix lands as an entry, never from a single remark.

**When it is re-run:** whenever always-loaded context is edited or trimmed (a `CLAUDE.md` line,
a `.claude/rules/*.md` line, or a skill body change), re-run the prompts recorded here against
the new text — as `@L1` dispatches of the relevant role for a small number of entries, or a
Workflow when 3+. A prompt that no longer reproduces its failure confirms the edit; one that
still fails means the edit did not fix what it claims to.

## Entries

None yet.
