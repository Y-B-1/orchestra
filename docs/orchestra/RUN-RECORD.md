# The run record — how a session opens, stamps and closes one

A run is resumable only if it left a record. Orchestra keeps **two** run-record files with
different jobs, and `flow.json` names the exact transition that writes each one. This page is the
digest; `state_files` in the graph is the source, and the phase playbooks under
`.claude/skills/orchestrator/references/` say it again at the point of use.

## The two files (plus the two declarations beside them)

| File | Committed? | Writer | Job |
| --- | --- | --- | --- |
| `docs/orchestra/STATE.md` | Yes — inside batch-closing commits | Orchestrator, **sole** | Human working memory for ONE run. Pointers, never content. |
| `.orchestra/state.json` | **No — gitignored** | Orchestrator, **sole**; read by the hooks and the janitor | Machine record: gate hashes, red-team verdicts, review verdicts, flakes. |
| `.orchestra/delivery.json` | Yes (gitignore exception) | Install / a human | Per-repo delivery declaration: provider, protected branches, landing, deploy policy. |
| `.orchestra/package-version` | Yes (gitignore exception) | `install.sh` | Which Orchestra package this repo merged. |

⚠ **`git ls-files .orchestra/` lists only `delivery.json` and `package-version`.** Those are the two
`.gitignore` exceptions under `.orchestra/*`; the listing is not evidence that `state.json` is
missing. Look at the **directory**. A recon that read the git listing instead produced a brief on
2026-09-01 asserting no run record existed while a 6 KB `state.json` sat on disk.

Sole-writer is not decoration. A worker that writes either file races the orchestrator, and neither
file has a merge strategy. A worker with something to record puts it in its report trailer; the
orchestrator transcribes.

## Open — at dispatch, not at close

- **Full chain:** the run opens when the lane is chosen. On entry, if `STATE.md` already carries an
  OPEN run, **reconcile before acting**: compare its stamp against `git rev-parse HEAD`,
  `git status --porcelain` and `git worktree list`. On mismatch, believe the tree and rewrite the
  stamp — a stamp records what a session *said*, the tree records what happened.
- **Small lane:** `small.build` opens a minimal entry **at dispatch** — lane, branch, next action.
  That entry is the whole reason an interrupted small task is resumable.
- **Trivial lane:** no `STATE.md` obligation at all. One reversible file, evidence-gated DONE, END.
- **Autonomy:** cannot start without a ledger — `docs/plans/<feature>-ledger.md`, or the path
  `STATE.md` points at. No ledger is NOT-READY, not a smaller run.

## Stamp — the transitions that write, and the key each one owns

| Flow state | Writes |
| --- | --- |
| `plan.redteam` | `redteam.verdicts` / `.rounds` / `.run_ids`. **A plan is not executable without a red-team record.** |
| `review.ticket` | `reviews.<ticket>` = the fresh reviewer's verdict, and the same line in the ledger. |
| `gates.fast` | `gates.reports[<commit hash>]` = the report; on green, `gates.last_green_hash` = that hash. |
| `review.pr` | `reviews.pr` = `CLEAN` or `BLOCKED` (plus worst severity). |
| `execute.wave-close` | Rewrites `docs/orchestra/STATE.md`, stamped. |
| `gates.full` | Appends the result pointer to `STATE.md`. |

Two of those keys are **read by a shell hook, not by a human**: `reviews.pr = CLEAN` is what the
merge guard reads as merge authorization, and a protected-branch push is denied while
`gates.last_green_hash` differs from HEAD. Writing them casually is granting a permission.
`gates.last_green_hash` moves for a docs-only commit **only** with the voiding rule stated in the
report line, because any commit after a green run voids that run as evidence.

The stamp line is the first line of `STATE.md` and is not optional:

```
# STATE — <project> (written-at: <ISO timestamp> @ <git HEAD short hash>)
```

Without both halves the reconcile step above has nothing to compare, and the file degrades into a
summary of a session nobody can locate.

## Close

- `small.close` — set `gates.last_green_hash` at HEAD exactly as `gates.fast` does, record the review
  verdict, rewrite `STATE.md` closing the entry, and add a memory line to `docs/AGENT-MEMORY.md`
  **only if a trap was found**.
- `terminal.final` — worktrees inspected (the **directory**, never the merged-ness of the branch) and
  removed, memory committed, ledger stamped CLOSED, expired `RESEARCH.md` removed, and `STATE.md`
  rewritten to **idle** — keeping any `deferred:` line, which is the one thing that outlives a run.
- A deliberate stop mid-run is a close too: write `STATE.md` and the ledger *before* clearing. In the
  boundary order — continue → clear → handoff → subagent → compact — "handoff" **is** this write.

## Hygiene

`STATE.md` holds pointers: a spec path, a ledger anchor, a next action. Its 120-line ceiling is a
smoke alarm, not an eviction trigger — over the line means content is being duplicated that already
has a home (the spec, the ledger, `AGENT-MEMORY.md`). Quote a ruling verbatim only when it fits one
line; otherwise point at it. A trimmed quote is worse than a pointer.

`STATE.md` is a working-tree file between closes. It is committed only inside batch-closing commits,
so a diff that carries `STATE.md` alone and nothing else is usually a stamp that got ahead of the
work it claims.
