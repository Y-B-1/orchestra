# Orchestra Roster for Cursor

A multi-agent operating system for Cursor: thirteen sub-agent roles, a machine-validated routing graph with three work lanes, deterministic guardrail hooks, bounded working memory, and a verified **merge-mode** installer — the charge chain (design → plan → execute → audit → gates → pr-review → release → cleanup) translated into Cursor's native mechanisms.

The original Claude snapshot is frozen at the sibling folder `orchestra-roster`. **All improvements live in this package** (GitHub: `Y-B-1/orchestra`).

## What's in the box

```
AGENTS.md                          Host charter (fill-in framework — not "you are the orchestrator")
install.sh                         Merge-mode install: copies orchestra files, keeps host charter/hooks/skills
docs/orchestra/                    Frameworks for AGENTS.md + AGENT-MEMORY.md, state.example.json, flow.html generator
docs/AGENT-MEMORY.md               Long-term index shell (how-to-fill + Current)
.cursor/
  agents/                          Thirteen worker roles (dispatch-only descriptions)
  skills/orchestrator/             SKILL.md (constitution + mechanics) + flow.json + briefs.md
  skills/{design,plan,execute,...} Orchestrator playbooks (who to hire — they do not do the work; disable-model-invocation)
  skills/pr-review                 Playbook for the inclusive pre-merge review (hires pr-reviewer)
  rules/orchestra-router.mdc       alwaysApply: SUB-AGENT STOP + short non-negotiables (main session only)
  hooks.json + hooks/              block-dangerous · block-nested-subagents · heal-orchestra-docs · session-start
docs/flow.html                     Generated human view of flow.json (includes autonomy)
.orchestra/delivery.json           Per-repo delivery declaration (committed)
.orchestra/package-version         Install stamp (VERSION + git describe; committed via gitignore exception)
VERSION                            Package version (source of the stamp)
```

The **orchestrator is the main session**, taught by the orchestrator skill (pin it as a Custom Mode). Phase skills are playbooks for who the main session hires; they set `disable-model-invocation: true` so workers cannot auto-load them. Each worker's empty-context job **is** `.cursor/agents/<role>.md` — Cursor does not auto-bind `skills/<role>/SKILL.md` by name; do not add a duplicate skill per role. Briefs in `briefs.md` are extra payload per dispatch. Workers in `.cursor/agents/` do the work.

## The design in five sentences

The **orchestrator is the main session** — the only entity that talks to the user or dispatches agents; sub-agents get clean contexts and self-contained briefs, and may not spawn agents (hook-enforced policy). **flow.json is the only statement of routing**: typed states with exclusive intake classification (`match: first`), `if/then` routes, three lanes, an autonomy loop that **requires an existing ledger**, and announced transitions. **Load-bearing process is enforced, not trusted**: red-team verdicts, review verdicts, and gate hashes are recorded in `.orchestra/state.json` (schema: `docs/orchestra/state.example.json`); destructive git is deny; protected landings `ask` in a local IDE and deny when headless — **ask is not the merge approval of record**; a host branch policy is, when `server_side_gate` is true. **Charter and memory are frameworks**: `AGENTS.md` and `docs/AGENT-MEMORY.md` are shells with how-to-fill rules; `sessionStart` heals missing headings without clobbering product text; the **janitor** stewards them at batch close. **Delivery is a per-repo declaration**: the provider decides which CLI ships; `server_side_gate` is true only when a branch policy actually runs the fast set — never because the remote happens to be Azure.

## Install into a project (merge, do not replace)

From the **host** repo root:

```bash
bash /path/to/orchestra/install.sh
```

That copies orchestra agents, orchestra skills, the router rule, and orchestra hook scripts; **upserts** orchestra entries in `.cursor/hooks.json` without removing host hooks; creates `AGENTS.md` / `docs/AGENT-MEMORY.md` from frameworks only when missing; appends a `## Orchestra` block when that heading is absent. It will **not** overwrite a filled host `AGENTS.md`, extra skills (for example react-doctor), or non-orchestra hook entries.

`install.sh` fails loudly until pinned roles have a non-`inherit` `model:` **and** `force-default-model: true` (so a parent Task `inherit` cannot override YAML). Judgement roles (including `pr-reviewer`) stay `inherit`. Phase skills must set `disable-model-invocation: true`. It self-tests both guardrail hooks with the **documented** `subagentStart` payload (`subagent_id`, `parent_conversation_id`, `subagent_type`), checks that recording `conversation_id` cannot poison orchestrator fan-out, validates every flow.json edge, writes `.orchestra/package-version`, and checks `docs/flow.html` names every state.

Then fill the **Delivery** slot in `AGENTS.md` from `.orchestra/delivery.json`. A leftover `<declare…>` placeholder is a note, not an install failure, once `delivery.json` exists.

**On GitHub** the same shape: required checks matching the fast set, then `server_side_gate: true`. Draft PRs, mark ready, merge with the host policy as the gate of record.

**On Azure DevOps** the recommended shape: a **branch policy on `main` with build validation** running the same fast set, then `server_side_gate: true`. Install defaults `server_side_gate` to **false** even for Azure remotes — set it true only after that policy exists. PRs as drafts, mark ready with **auto-complete**, full suite as its own scheduled pipeline on main. Production deploys belong behind a Pipelines **environment approval check**.

A host with **both** remotes (GitHub `origin` plus Azure `devops`) is the Equiti Hub pattern. Install then prefers `azure-devops` as `provider` because Azure is the land path; edit `delivery.json` if GitHub should be the gate of record instead. The hook already tokenizes `git`, `gh`, and `az repos`.

This package is **Cursor-only**. A Claude Code port would be a second agent runtime (`.claude/agents`, different hooks) and is out of scope.

Naive `cp -R` of this folder over a living host (for example a repo that already has its own `AGENTS.md` and `hooks.json`) will clobber that host. Use `install.sh`.

## Honest limits (read this)

- **The hooks are tripwires, not walls.** They tokenize commands and gate protected-branch landings across `git`, `gh`, `az repos`, and `glab` plus declared deploy commands. Force-push / stash / rebase / hard reset are deny. The user-facing `ask` is a **local-IDE** pause; cloud/headless degrades it to deny. A host-side branch policy is the real merge gate, which is why `server_side_gate` exists. Do not advertise hook ask as *the* merge approval.
- **`failClosed: true`** on the two guardrail hooks: crash, timeout, or invalid JSON blocks the action. Payload surprises still fail-open *inside* the script and append `.orchestra/hook-failures.log`. `sessionStart` injects that log into context so a skip of the janitor (trivial / single-ticket path) does not hide a disarmed hook.
- **Prompt-enforced rules degrade under context pressure.** Load-bearing ones are also file contracts (`state.json`) checked by the janitor and the hook.
- **Full e2e never runs by itself.** User-triggered (or scheduled), whole-codebase, detached from PRs.
- **In cloud agents, approvals change shape.** Cloud agents auto-run terminal commands, so ask→deny when headless, and a protected landing with no readable gate record is denied (`.orchestra/state.json` is gitignored). Seed from `docs/orchestra/state.example.json`. Set `server_side_gate: true` only with a real branch policy.
- **Cursor 3.5+ may delete unmanaged `git worktree` dirs.** Commits on named ticket branches are the preservation. The nest hook records `git_branch` from `subagentStart`; janitor inspects `git worktree list`, not only `.cursor/worktrees/<ticket>`.
- Cursor facts this package depends on (verified Aug 2026, re-verify after updates): agents in `.cursor/agents/` with clean contexts (the agent file **is** the role's system prompt — no auto-link to a matching skill directory); YAML `model:` overridden by Task unless `force-default-model: true`; one further nesting level allowed since 2.5 (we forbid it, keying `subagent_id`); skills auto-load by description (agent descriptions are dispatch-only; phase skills also set `disable-model-invocation: true`); `.mdc` rules; snake_case hook responses; `subagentStart` / `beforeShellExecution` / `sessionStart`.

## Local, cloud, or both

The chain is the same; only isolation and conversation change.

| | Local session | One cloud agent = orchestrator | One cloud agent per feature |
|---|---|---|---|
| Sub-agents | in-session, shared tree | in-VM, shared clone | each VM runs its own mini-chain |
| Worktrees | 2+ concurrent builders | **same rule** — shared clone | none; the VM is the isolation |
| Handoffs | briefs + disk | briefs + disk | git branches + relayed reports |
| Talks to you | yes | async (Slack, web, PR) | via PRs |

Design and plan are conversations — keep them local. Execute waves are the natural cloud workload. Split *work* across VMs, never *roles*.

## Working the system

Say what you want; the router classifies into **one** lane (`match: first`) and announces every transition. Pin the orchestrator skill as a Custom Mode. Trivial changes go straight through with evidence. Small changes (2–5 files) get design-in-chat + one builder + one reviewer + the fast gate + **inclusive PR/branch review** (`pr-reviewer`) before merge. Full-chain work gets the interview, an architect-drafted spec you approve, a planner-drafted red-teamed plan, waves of builder+reviewer pairs, integration, the fast gate, inclusive PR review, audit when the change-set spans tickets, and release per your delivery declaration. Unattended "keep going until done" requires an existing ledger. Re-run `install.sh` after Cursor updates.

## Parked (do not forget)

Folding the original twelve workers (janitor / releaser / researcher / builder-max) is **paused**. `pr-reviewer` was added by request as a thirteenth role for inclusive pre-merge review. Do not fold the parked roles unless that discussion reopens.
