# Orchestra Roster for Cursor

A multi-agent operating system for Cursor: twelve sub-agent roles, a machine-validated routing graph with three work lanes, deterministic guardrail hooks, bounded working memory, and a verified installer — the charge chain (design → plan → execute → audit → gates → release → cleanup) translated into Cursor's native mechanisms, then red-teamed twice: once for correctness, once against its own premises.

## What's in the box

```
AGENTS.md                          Orchestrator constitution (main session; copy to project root)
install.sh                         Verified install: hook self-tests, model-pinning check, graph validation
.cursor/
  agents/                          Twelve sub-agent personas (clean-context system prompts, level contracts)
    scout researcher architect planner red-teamer builder builder-max
    reviewer auditor gatekeeper janitor releaser
  skills/
    orchestrator/                  SKILL.md (mechanics) + flow.json (THE routing graph)
                                   + briefs.md (every dispatch template) + STATE.template.md
    design/ plan/ execute/ diagnose/ audit/ gates/ release/ cleanup/
  rules/orchestra-router.mdc       alwaysApply: router mandate + sub-agent stop + resume-reconcile
  hooks.json + hooks/              block-dangerous.py · block-nested-subagents.py
docs/flow.html                     Human view of flow.json
.orchestra/delivery.json           Per-repo delivery declaration (committed; rest of .orchestra/ is gitignored)
```

## The design in five sentences

The **orchestrator is the main session** — the only entity that talks to the user or dispatches agents; sub-agents get clean contexts and self-contained briefs, and may not spawn agents (hook-enforced policy). **flow.json is the only statement of routing**: typed states with `if/then` routes, parallel `then` arrays, standing `always` duties, first-class backward edges (`back_to` + `carry`), three lanes (trivial / small / full chain), and announced transitions. **Load-bearing process is enforced, not trusted**: red-team verdicts, review verdicts, and gate hashes are recorded in `.orchestra/state.json`; the hook asks the real user on protected-branch pushes and denies them while the green-gate hash ≠ HEAD; the janitor's checklist detects skipped process from the file trail. **Memory is bounded and pointer-based**: `docs/orchestra/STATE.md` (stamped working memory, reconciled against the tree on resume — any session is killable without loss), per-plan ledgers, and pruned long-term memory in `docs/AGENT-MEMORY.md`. **Delivery is a per-repo declaration and host-agnostic**: the provider (GitHub, Azure DevOps, GitLab, or plain git) decides which CLI ships the work; merge on fast-gate green with the gated hash as the shipped hash — or, where the host gates server-side, let its branch policy do it against the preview merge commit; draft PRs from the first wave (never blockers), deploy per environment policy, migrations never auto-deploy, revert-first rollback.

## Install into a project

```bash
cp -R <this-repo>/.cursor <this-repo>/AGENTS.md <this-repo>/install.sh <project>/ && cd <project> && bash install.sh
```

`install.sh` fails loudly until you: **pin the model tiers** (edit `model:` frontmatter — judgement roles architect/planner/red-teamer/auditor/builder-max stay `inherit`; pin builder/reviewer/gatekeeper/releaser to your plan's mid tier and scout/researcher/janitor to its fast tier). It also self-tests both hooks (a synthetic nested spawn must come back `deny`), validates every flow.json edge and dispatch role, writes the default `.orchestra/delivery.json` for you to edit, and prints the manual steps (verify the sub-agent state path; re-run after every Cursor update — hook payload schemas can change silently, and fail-opens land in `.orchestra/hook-failures.log`).

Then edit the **Delivery** line in AGENTS.md and `.orchestra/delivery.json`: `install.sh` detects the **provider** from your remote (`github` · `azure-devops` · `gitlab` · `plain-git`); confirm it, plus protected branches, landing rule, and deploy policy per environment (`auto` only for low-blast environments — production defaults to approval).

**On Azure DevOps** the recommended shape: a **branch policy on `main` with build validation** running the same fast set, `server_side_gate: true` in the declaration, PRs opened as drafts and marked ready with **auto-complete** so the platform merges when the policy passes, and the full suite as its own scheduled pipeline on main — never in the PR's required checks. Azure builds the *preview merge commit*, so the hash it gates is provably the hash that ships; the local hash-freshness check stands down there. Production deploys belong behind a Pipelines **environment approval check**.

## Honest limits (read this)

- **The hooks are tripwires, not walls.** They tokenize commands (handling `git -C`, reordered flags, env prefixes, `&&` chains, and interpreter `-c` strings) and gate protected-branch landings across `git`, `gh`, `az repos`, and `glab` plus declared deploy commands — catching accidents and first-order drift, not adversarial evasion. The user-facing `ask` is the actual floor for irreversibles; a host-side branch policy is stronger still, which is why `server_side_gate` exists.
- **Prompt-enforced rules degrade under context pressure.** That is why the load-bearing ones are also file contracts (`state.json`) checked by the janitor and the hook — a silent skip becomes a visible gap.
- **Full e2e never runs by itself.** It is user-triggered (or user-scheduled), whole-codebase, detached from PRs. A suite that only runs on demand rots — schedule a quiet run on main if you rely on it.
- Cursor facts this package depends on (verified Aug 2026, re-verify after updates): agents in `.cursor/agents/` with clean contexts; one further nesting level allowed since 2.5 (we forbid it); skills auto-load by description; `.mdc` rules; snake_case hook responses; `subagentStart` / `beforeShellExecution` events.

## Working the system

Say what you want; the router classifies into a lane and announces every transition. Trivial changes go straight through with evidence. Small changes (2–5 files) get design-in-chat + one builder + one reviewer + the fast gate. Full-chain work gets the interview, an architect-drafted spec you approve, a planner-drafted red-teamed plan, waves of builder+reviewer pairs, integration, audit when the change-set spans tickets, and release per your delivery declaration. Backward edges are first-class: findings loop to their author, a changed ruling re-enters the design gate and invalidates affected tickets, a failed deploy reverts first and enters the bug lane. Pin the orchestrator skill as a Custom Mode to keep the router active every turn.
