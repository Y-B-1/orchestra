## Standing rails (every dispatch — your brief does not restate these)

`CLAUDE.md`, `~/.claude/CLAUDE.md` and this repo's project rules are already loaded in your
context — sub-agents do not start empty. Read them there; never ask a brief to quote them back
to you. Any `skills` your definition preloads carry the path-scoped `.claude/rules/*.md`, which do
NOT travel to a sub-agent on their own. On top of all of that:

1. **Capture exit codes directly, never through a pipe.** Run each command as
   `cmd > /tmp/<name>.log 2>&1; echo exit:$?` and quote that code. A gate piped through `grep`,
   `tail`, or `head` reports the filter's status and hides the failure. Never run
   the host's full test suite unfiltered — name the spec files.
2. **Commit only when your brief assigns it.** By default you leave your work staged or
   uncommitted in the tree and the orchestrator commits at wave close — concurrent workers
   sharing one checkout share a single git index, so an unassigned commit races a sibling's.
   When your brief explicitly assigns you the commit, stage only the paths it names —
   `git add <path>`, never `-A`/`.`/`-u`, never `commit -a` — and never run any `git stash`
   subcommand, including `stash list` (worktrees share one ref store; stash is repo-wide, and
   the stash hook denies the word outright, even for a read-only `list`).
2b. **Workers never run `git worktree` commands (A30, hook-enforced 2026-09-04).** Worktrees
   are the orchestrator's instrument: it creates them, inspects the DIRECTORY, and removes
   them. When siblings hold the tree unbuildable, verify on a `git archive HEAD | tar -x`
   copy with node_modules symlinked.
2c. **A pr-reviewer CLEAN counts only with its record file (audit B3, 2026-09-04).** The
   exit-door reviewer writes its verdict to `docs/orchestra/reviews/<batch>.md` and the
   orchestrator records that path in `.orchestra/state.json` `reviews.pr_record`; the
   landing guard denies a protected merge/deploy without an existing record file.
3. **Leave no scratch in the repo.** Working notes, logs, and throwaway scripts belong in the
   session scratchpad directory, never at a tracked path.
