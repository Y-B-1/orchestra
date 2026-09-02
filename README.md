# Orchestra Roster for Claude Code and Cursor

A multi-agent operating system for Claude Code and Cursor: thirteen sub-agent roles, a machine-validated routing graph with three work lanes, deterministic guardrail hooks, bounded working memory, and a verified **merge-mode** installer. Orchestra's chain is design → plan → execute → audit → gates → pr-review → release → cleanup.

The original Claude snapshot is frozen at the sibling folder `orchestra-roster`. **All improvements live in this package** (GitHub: `Y-B-1/orchestra`).

## What's in the box

```
CLAUDE.md                          Host charter (the real file). AGENTS.md → CLAUDE.md
AGENTS.md                          Symlink to CLAUDE.md (Cursor's name). Never ~/.claude/CLAUDE.md
install.sh                         Merge-mode install: copies orchestra files, keeps host charter/hooks/skills
docs/orchestra/                    Frameworks for AGENTS.md + AGENT-MEMORY.md, state.example.json, flow.html generator
docs/AGENT-MEMORY.md               Long-term index shell (how-to-fill + Current)
.claude/                           Source runtime (Claude Code)
  agents/                          Thirteen worker roles (dispatch-only descriptions)
  hooks/ + tests                   Guardrail hooks, each with its own .test.sh
  skills/orchestrator/             SKILL.md (constitution) + references/ (flow.json, briefs.md, phase playbooks) + scripts/
  skills/orchestra-rails/          Standing rails preloaded by every worker
.cursor/                           Generated from .claude/ by docs/orchestra/sync-agent-config.py — never hand-edited
  agents/                          Thirteen worker roles, mirrored
  skills/orchestrator/             SKILL.md + references/ + scripts/, mirrored
  skills/orchestra-rails/          Mirrored
  rules/orchestra-router.mdc       alwaysApply: SUB-AGENT STOP + short non-negotiables (main session only)
  hooks.json + hooks/              block-dangerous · block-nested-subagents · heal-orchestra-docs · session-start
docs/flow.html                     Generated human view of flow.json (includes autonomy)
.orchestra/delivery.json           Per-repo delivery declaration (committed)
.orchestra/package-version         Install stamp (VERSION + git describe; committed via gitignore exception)
VERSION                            Package version (source of the stamp)
```

The **orchestrator is the main session**, taught by the orchestrator skill (pin it as a Custom Mode in Cursor; Claude Code loads it by description). Phase playbooks are `references/` files under the orchestrator skill, read by path — never skills a worker could invoke. Each worker's empty-context job **is** `.claude/agents/<role>.md` (mirrored to `.cursor/agents/<role>.md`) — Cursor does not auto-bind `skills/<role>/SKILL.md` by name; do not add a duplicate skill per role. Briefs in `references/briefs.md` are extra payload per dispatch. Workers do the work.

## The design in five sentences

The **orchestrator is the main session** — the only entity that talks to the user or dispatches agents; sub-agents get clean contexts and self-contained briefs, and may not spawn agents (hook-enforced policy). **flow.json is the only statement of routing**: typed states with exclusive intake classification (`match: first`), `if/then` routes, three lanes, an autonomy loop that **requires an existing ledger**, and announced transitions. **Load-bearing process is enforced, not trusted**: red-team verdicts, review verdicts, and gate hashes are recorded in `.orchestra/state.json` (schema: `docs/orchestra/state.example.json`); destructive git is deny; the hook never returns ask; pr-reviewer CLEAN + matching gate hash allows land and declared deploys, including headless; without CLEAN those are deny; a host branch policy is the other gate when `server_side_gate` is true. **Charter and memory are frameworks**: `AGENTS.md` and `docs/AGENT-MEMORY.md` are shells with how-to-fill rules; `sessionStart` heals missing headings without clobbering product text; the **janitor** stewards them at batch close. **Delivery is a per-repo declaration**: the provider decides which CLI ships; `server_side_gate` is true only when a branch policy actually runs the fast set — never because the remote happens to be Azure. After intake the only user-facing stop is unanswered frontier questions; specs, plans, reviews, merges, and deploys do not wait.

## Install into a project (merge, do not replace)

From the **host** repo root:

```bash
bash /path/to/orchestra/install.sh
```

That copies orchestra agents, orchestra skills, the router rule, and orchestra hook scripts; **upserts** orchestra entries in `.cursor/hooks.json` without removing host hooks; creates `CLAUDE.md` / `docs/AGENT-MEMORY.md` from frameworks only when missing and points `AGENTS.md` at `CLAUDE.md`; appends a `## Orchestra` block when that heading is absent. It will **not** overwrite a filled host `CLAUDE.md`, extra skills (for example react-doctor), or non-orchestra hook entries. It will **not** copy `~/.claude/CLAUDE.md`.

`install.sh` fails loudly until pinned roles have a non-`inherit` `model:` **and** `force-default-model: true` (so a parent Task `inherit` cannot override YAML). Judgement roles (including `pr-reviewer`) stay `inherit`. No phase playbook may be a skill a worker could invoke — they are `references/` files, read by path. It self-tests both guardrail hooks with the **documented** `subagentStart` payload (`subagent_id`, `parent_conversation_id`, `subagent_type`), checks that recording `conversation_id` cannot poison orchestrator fan-out, validates every flow.json edge, writes `.orchestra/package-version` on a host install (hand-written in the package itself, where `$SRC` is `$DST`), and checks `docs/flow.html` names every state.

Then fill the **Delivery** slot in `CLAUDE.md` from `.orchestra/delivery.json`. A leftover `<declare…>` placeholder is a note, not an install failure, once `delivery.json` exists.

**On GitHub** the same shape: required checks matching the fast set, then `server_side_gate: true`. Draft PRs, mark ready, merge with the host policy as the gate of record.

**On Azure DevOps** the recommended shape: a **branch policy on `main` with build validation** running the same fast set, then `server_side_gate: true`. Install defaults `server_side_gate` to **false** even for Azure remotes — set it true only after that policy exists. PRs as drafts, mark ready with **auto-complete**, full suite as its own scheduled pipeline on main. Deploy is auto after pr-reviewer CLEAN (push-is-deploy hosts keep the land branch off `protected_branches`).

A host with **both** remotes (GitHub `origin` plus Azure `devops`) is the Equiti Hub pattern. Install then prefers `azure-devops` as `provider` because Azure is the land path; edit `delivery.json` if GitHub should be the gate of record instead. The hook already tokenizes `git`, `gh`, and `az repos`.

This package is a **dual runtime**: Claude Code (`.claude/`) is the source, Cursor (`.cursor/`) is generated from it. One `flow.json`. One `CLAUDE.md`.

> ~~Do **not** add `.claude/skills/orchestrator/` — Cursor also loads that directory. Claude reads the constitution at `.cursor/skills/orchestrator/SKILL.md`.~~ **Superseded 2026-09-02 (ruling U8, `docs/plans/RULINGS-2026-09-01.md` in Equiti Hub; design `docs/orchestra/SPEC-claude-native.md`).** `.claude/skills/orchestrator/` is the source of the constitution; `.cursor/skills/` is generated from it by `docs/orchestra/sync-agent-config.py`. Cursor never loaded `.claude/skills/` — the old rule guarded against a second hand-maintained copy drifting, and generation removes that risk.

Claude models: `docs/orchestra/claude-models.md`.

Preloads are host data, not package content: a host's `.claude/rules/*.md` is mirrored to `.claude/skills/rule-<name>/SKILL.md`, and only the roles that touch that surface add `skills: [rule-<name>]` to their frontmatter (worked example: `SPEC-claude-native.md` §4.2, in the design record below). Re-run `docs/orchestra/sync-agent-config.py` after editing a host rule; `install.sh` preserves preloads already present on a host agent file.

The design records behind this dual-runtime port live outside the package, at `Y-B-1/equitihub@8e054026` (`docs/orchestra/SPEC-claude-native.md`, `RESEARCH-claude-skills.md`) — the design record's home, not a file this package ships.

Naive `cp -R` of this folder over a living host (for example a repo that already has its own `CLAUDE.md` and `hooks.json`) will clobber that host. Use `install.sh`.

## Honest limits (read this)

- **The hooks are tripwires, not walls.** They tokenize commands and gate protected-branch landings across `git`, `gh`, `az repos`, and `glab` plus declared deploy commands. Force-push / stash / rebase / hard reset are deny. The hook **never returns ask**. **pr-reviewer CLEAN + matching `gates.last_green_hash` is merge and deploy authorization** — the hook allows that land and declared deploys, including headless (ralph / overnight). Without CLEAN those are deny. A host-side branch policy is the other gate (`server_side_gate`). Installer strips host `block-pr-merge.sh`. Full e2e is never a merge precondition.
- **`failClosed: true`** on the two guardrail hooks: crash, timeout, or invalid JSON blocks the action. Payload surprises still fail-open *inside* the script and append `.orchestra/hook-failures.log`. `sessionStart` injects that log into context so a skip of the janitor (trivial / single-ticket path) does not hide a disarmed hook.
- **Prompt-enforced rules degrade under context pressure.** Load-bearing ones are also file contracts (`state.json`) checked by the janitor and the hook.
- **Full e2e never runs by itself.** User-triggered (or scheduled), whole-codebase, detached from PRs.
- **In cloud agents, write CLEAN+fresh before land.** Cloud agents auto-run terminal commands. The hook never returns ask. Headless land/deploy is allow only when this VM wrote `reviews.pr=CLEAN` and a matching gate hash (do that in-session before land). A fresh clone has no `state.json` — seed from `docs/orchestra/state.example.json`. `server_side_gate: true` only with a real branch policy.
- **Cursor 3.5+ may delete unmanaged `git worktree` dirs.** Commits on named ticket branches are the preservation. The nest hook records `git_branch` from `subagentStart`; janitor inspects `git worktree list`, not only `.cursor/worktrees/<ticket>`.
- Cursor facts this package depends on (verified Aug 2026, re-verify after updates): agents in `.cursor/agents/` with clean contexts (the agent file **is** the role's system prompt — no auto-link to a matching skill directory); YAML `model:` overridden by Task unless `force-default-model: true`; one further nesting level allowed since 2.5 (we forbid it, keying `subagent_id`); skills auto-load by description (agent descriptions are dispatch-only; phase skills also set `disable-model-invocation: true`); `.mdc` rules; snake_case hook responses; `subagentStart` / `beforeShellExecution` / `sessionStart`.

## Local, cloud, or both

The chain is the same; only isolation and conversation change.

| | Local session | One cloud agent = orchestrator | One cloud agent per feature |
|---|---|---|---|
| Sub-agents | in-session, shared tree | in-VM, shared clone | each VM runs its own mini-chain |
| Worktrees | 2+ concurrent builders | **same rule** — shared clone | none; the VM is the isolation |
| Handoffs | briefs + disk | briefs + disk | git branches + relayed reports |
| Talks to you | frontier gaps only | async after frontier | via PRs only if you look |

Frontier questions (unanswered decisions only) stay local if they exist. After that the chain runs through merge and deploy without waiting. Split *work* across VMs, never *roles*.

## Working the system

Say what you want; the router classifies into **one** lane (`match: first`) and announces every transition. Pin the orchestrator skill as a Custom Mode. The only user-facing stop after intake is unanswered frontier questions. Trivial changes go straight through with evidence. Small changes (2–5 files) adopt the recommended approach, then one builder + one reviewer + the fast gate + **inclusive PR/branch review** (`pr-reviewer`) then land and deploy. Full-chain work gets recon, frontier only if the request left a gap, an architect-drafted spec the orchestrator commits after red-team, a planner-drafted red-teamed plan, waves of builder+reviewer pairs, integration, the fast gate, inclusive PR review, audit when the change-set spans tickets, and release (merge + deploy) per the delivery declaration. Overnight / unattended is **named invocation only** (`orchestra autonomy`, `run overnight`, `unattended until the ledger is done`, or `ralph` as an alias) and requires an existing ledger — ordinary "keep going" is not it. Re-run `install.sh` after Cursor updates.

## Parked (do not forget)

Folding the original twelve workers (janitor / releaser / researcher / builder-max) is **paused**. `pr-reviewer` was added by request as a thirteenth role for inclusive pre-merge review. Do not fold the parked roles unless that discussion reopens.
