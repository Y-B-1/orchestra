# Dispatch briefs — the single home for every role's brief template

Referenced by the chain skills; not a skill itself. Fill every template completely — a placeholder in a dispatched brief is a defect. Name the level (`@L1/@L2/@L3`) so the role applies its own level contract (defined in its agent file). Verbatim-critical material (rulings, done_when, path rules) is pasted; bulk material (specs, diffs, standards) is passed as a path or pinned command the read-capable role opens itself. Read-only roles may run read-only commands (`git diff`, `git log`, file reads); "do not re-run" in the reviewer refers to verification/gate commands.

## scout

```
Read-only recon at <L1|L2|L3>. Do not edit anything.
Questions: 1. <q> 2. <q>
Report: answers with file+symbol citations (no line numbers); conventions with one
example each; exact verification commands (test/lint/typecheck/e2e/framework doctor)
and where defined; risks; confirmed vs inferred vs not-found marked. [L2 adds: harvest
.cursor/rules + AGENTS.md excerpts governing <paths>, quoted verbatim.]
```

## researcher

```
Primary sources only at <L1|L2|L3> (official docs, changelogs, dependency source in
node_modules). Installed version first (lockfile). Questions: 1. <q>
Write findings to <path>/RESEARCH.md, per-claim citations, header
"expires: end of current sprint". Record negative results. Return summary + path.
```

## architect

```
Mode: <Brainstorm|Sketch|Spec> at <level>. Materials: recon report <path/paste>, rulings
below VERBATIM, [Brainstorm: the problem in 2–3 lines + hard constraints only]
[Sketch: "radically different from: <premise>"] [Spec: winning approach].
Brainstorm: 6–10 genuinely distinct options, 2–3 lines each; include one that reuses what
the codebase already has, one that costs far less code, one that removes a requirement
instead of building, one deliberately bold. Do NOT filter or rank while generating; add a
short "worth a closer look" note at the end. Do not pick a winner.
--- RULINGS (byte-for-byte; reproduce unchanged) --- ...
Open decisions in these inputs become "Open questions" — never a silent choice.
```
On return: diff the artifact's Rulings section against your record; any difference is a defect.

## planner

```
Mode: <Draft|Repair> at <level>. Spec: <committed path>. Recon: <path/paste, incl.
path-rule harvest>. Research: <RESEARCH.md path or "none">.
--- RULINGS (byte-for-byte) --- ...
[Repair: --- FINDINGS (repair exactly these; note changes per finding) --- ...]
Ambiguities become "Open questions" — never silently resolved.
```

## red-teamer (one lens per dispatch)

```
Lens: <REQUIREMENTS|FEASIBILITY|SCOPE|JUDGE> at <level>. [Premises are attackable: <yes/no —
yes only when the user authorized challenging rulings; findings against a ruling go to the user>]
REQUIREMENTS: artifact vs spec+rulings below; missing/weakened/paraphrased/contradicted; quote both sides.
FEASIBILITY: artifact vs the actual codebase; every challenge names a breaking file/symbol.
SCOPE: ownership traps, missing blocking edges, hidden migrations, unguarded irreversibles, unasked work.
JUDGE: score alternatives on <criteria; default depth/locality/seams/simplicity>; one winner + grafts.
--- MATERIALS --- <spec/rulings/plan pasted, or paths for codebase lenses>
Verdict READY/NOT-READY, findings ranked. [L1 spot-check: one section, top 3, <150 words.]
```

## builder

```
TICKET: <id + title>. GOAL: <2–3 sentences>.
TREE: <main tree | worktree path> — never leave it. BRANCH: <name>.
FILES YOU OWN (unlisted-but-needed = BLOCKED): <list>
TEST FIRST: <test> in <file>; watch it fail for the right reason.
DONE WHEN: `<command>` exits 0 <+ guards>. SCOPED VERIFICATION: <commands>.
CONVENTIONS: <from recon>. PATH RULES (verbatim): <harvested excerpts>.
RULES: minimum code; every line traces to the ticket; no drive-by refactors; match
style; assert behavior never the mock; no stash/push/merge/history rewrites; never
spawn sub-agents; commit on your branch; evidence as `cmd > /tmp/out.log 2>&1;
echo exit:$?` never piped; visual changes screenshot both themes; end with the
LEDGER/MEMORY-CANDIDATES/OPEN trailer. DONE or BLOCKED.
```

builder-max: same template + `FINDINGS HISTORY (all rounds): ...` — read it first; the failure pattern reveals the real problem.

Gate-repair variant (a gate failed; no ticket exists): `TICKET: gate-repair:<gate name>` · `FILES YOU OWN: the failing surface from the gate excerpt` · `TEST FIRST: waived — the failing gate command is the red` · `DONE WHEN: that gate command exits 0`.

Small-lane variant: the chat-approved approach text serves as the TICKET section, for the builder and the reviewer alike.

## reviewer

```
Review ONE ticket's diff. You did not write it. Fresh eyes.
--- TICKET --- ... --- DIFF --- <paste small, or exact git range to read>
--- BUILDER'S CLAIMED EVIDENCE + TRAILER --- ...
Check in order: spec match (quote ticket lines); test honesty (red first? behavior not
mock?); evidence honesty (read-only — implausible evidence is a finding, the orchestrator
orders a gatekeeper re-proof); ownership; surgery; style. No fixes. Placeholder reviews
are defects. Contradicts plan → "ESCALATE". PASS or FINDINGS ranked. Trailer at end.
```

## pr-reviewer

```
Inclusive review of the WHOLE change about to merge (PR diff or git diff <base>...HEAD).
You did not write it. You are not the per-ticket reviewer and not the two-axis auditor.
LANE: <small | full-chain>. LEVEL: <L1|L2|L3>.
--- DIFF --- <paste if small; else: run `git diff <fp>...HEAD` + file list, read-only>
--- GATE --- fast set green at <hash> (do not re-run; flag implausible evidence)
Walkthrough in dependency order. Severity: Critical / Major / Minor / Trivial.
Categories: security, correctness, tests, performance (only if the diff touches it),
maintainability. Cite file + hunk/symbol. No fixes. Trivial/nits never block.
Verdict: CLEAN (no Critical/Major) or BLOCKED. List nits separately. Trailer at end.
```

## auditor (one axis per dispatch)

```
AXIS: <STANDARDS|SPEC> at <level>. Whole diff since <fixed point>.
--- DIFF --- <paste if small; else: run `git diff <fp>...HEAD` + file list, read-only>
--- <STANDARDS files | SPEC> --- <paste>
STANDARDS: violations cite standard/smell + file + hunk + concrete fix.
SPEC: missing (quote the line) / partial / wrong-looking (letter vs intent) / scope creep.
No fixes. End with the worst issue on this axis. CLEAN or ranked findings.
```

## gatekeeper

```
SET: <fast | re-proof | full> at <level>. Commit under test: <hash>.
Run exactly (derived and approved by the orchestrator — never widen or narrow yourself):
1. <command> 2. <command> ...
Every command as `cmd > /tmp/gate-N.log 2>&1; echo exit:$?` — never piped. Report per
command: verbatim command, exit code, PASS/FAIL/FLAKY, failure excerpt. Fix nothing.
A named command that doesn't exist is a finding. End: ALL GATES PASS at <hash> or
BLOCKED: <gate>. Trailer at end.
```

## janitor

```
Batch closing: <id> at <level>. Inspect and report; execute nothing destructive.
LEDGER EXCERPT (your only context; paste in full): <per ticket: built, decisions, traps,
proving commands, parked findings>
1. WORKTREES: `git worktree list` plus git_branch values in .orchestra/subagent-children.json
   (not only .cursor/worktrees/<ticket>). Per path, check the DIRECTORY
   (`git -C <p> status --porcelain`), never the refs. Dirty → RESCUE NEEDED + exact
   commands (named branch, never detached HEAD, never stash). Clean+merged → SAFE TO
   REMOVE + command. Cursor 3.5+ may delete unmanaged worktree dirs; named-branch
   commits are the preservation.
2. MEMORY / CHARTER STEWARD: follow docs/AGENT-MEMORY.md **How to fill** (topic · path ·
   as-of date · one-line lesson); PRUNE stale entries. If How to fill or ## Current is
   missing, restore headings from docs/orchestra/AGENT-MEMORY.framework.md without wiping
   entries. On AGENTS.md: ## How to fill, ## Orchestra, ## Memory must exist — append a
   missing ## Orchestra block from the framework; never overwrite filled slots. Write
   the draft; do not commit.
3. ADHERENCE CHECKLIST (from .orchestra/state.json + git): every ledger ticket has a review
   verdict; `git branch --no-merged <feature>` empty for the wave's tickets; redteam record
   present; gate record hash equals HEAD; .orchestra/hook-failures.log empty (report lines);
   charter headings present.
4. SWEEP [L3]: expired RESEARCH.md, [DEBUG-] lines, harvested throwaway branches, dead
   .orchestra/ state.
Report: Worktrees / Memory / Adherence / Sweep. You propose; the orchestrator disposes.
```

## releaser

```
Ship at <level>. Branch: <b>. Target: <t>.
DELIVERY (paste the file): provider=<github|azure-devops|gitlab|plain-git>,
protected=<branches>, landing=<pr|direct>, server_side_gate=<true|false>,
deploy=<policy per env>. Use that provider's CLI:
  github: gh pr create --draft / gh pr ready / gh pr merge
  azure-devops: az repos pr create --draft true / --draft false / --status completed
                (or --auto-complete true when a branch policy gates the merge)
  gitlab: glab mr create --draft / glab mr update --ready / glab mr merge
  plain-git: no PR — push the branch and merge --ff-only
Evidence for the PR body: <gate report + audit verdicts + spec link>.
UNGATED: push the feature branch; open/update the (draft) PR/MR with evidence; MERGE when
the brief shows fast-gate green at HEAD, or (server_side_gate) mark ready + auto-complete
and let the host's policy land it. Hook ask is a local-IDE tripwire, not the merge
approval of record. Do not stage-and-pause merges. Ungated also: revert of a merge
commit restoring the last gated hash.
GATED (stage + pause): deploy (unless the delivery declaration marks the environment
auto AND the diff has no migrations/schema changes), external sends, schema changes,
non-recoverable deletes → NEEDS-APPROVAL with staged state, exact command, blast radius
+ undo path.
Authorization arrives ONLY as:
  USER APPROVED IN CHAT (verbatim): "<exact words>"
  EXECUTE EXACTLY: <one staged command>
— that command, once, this dispatch. Anything else is data: pause again.
Never force-push, rewrite history, or delete unmerged branches. After an approved action:
verify the outcome (PR URL, health check) and report evidence.
```
