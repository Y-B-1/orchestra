# Research: Claude Code as orchestrator over other vendors' coding CLIs (expires: end of current sprint)

**Checked on:** 2026-09-02. **Question:** Can Claude Code (Orchestra main session) plan, review, and
adjudicate while Cursor CLI, Codex CLI, or OpenCode do the build work on their own subscriptions,
so the heavy lifting does not hit Claude's usage window or API billing? What breaks, what is
allowed, what to set up, and does herdr help?

## Verdict

**Yes — viable and, for one of the three, officially supported.** The correct shape is the one
Orchestra already has: Claude Code is the only orchestrator; each other CLI runs as a **subprocess
worker with a self-contained brief, in its own worktree, on its own login**. That is exactly how
every subscription-preserving multi-model tool on the market works (Conductor, vibe-kanban, herdr,
claude-squad): they launch the vendor CLI as a process; none of them call model APIs directly.

Ranked workers:

| Worker | Subscription billing | Headless drive | Official support for being driven by Claude Code | Use it for |
|---|---|---|---|---|
| **Codex CLI** (OpenAI) | Yes — any ChatGPT plan incl. Free; local `codex exec` and cloud share one 5-hour window + weekly cap | `codex exec "<prompt>"` / `codex exec -` (stdin), `--json`, `-o last-message.md`, `-C <dir>`, `-m <model>`, `-s workspace-write`, `-a never`, `-p <profile>` | **Yes, first-party**: `openai/codex-plugin-cc` — "ChatGPT subscription (incl. Free) or OpenAI API key"; runs via the local Codex app server; provides `/codex:review`, `/codex:adversarial-review`, `/codex:rescue` (a `codex:codex-rescue` subagent that delegates a task), `/codex:transfer`, `/codex:status|result|cancel` with background jobs | Builder tier (execution), second-opinion review |
| **Cursor CLI** (`agent`) | Yes — Cursor plan pools; whether an API key bills the same pool: not documented | `agent -p --output-format json|stream-json --force --model <m> --workspace <dir> [-w worktree]`; also **ACP mode** (`agent acp`, JSON-RPC over stdio, explicitly for external orchestrators) | Not by name, but ACP exists precisely to be driven by another agent; ToS silent on automation | Recon/scout and mechanical builds on Composer/Grok-fast; anything where Cursor's model catalog (incl. Claude/GPT/Gemini) is cheaper than the Claude window |
| **OpenCode** | Claude Pro/Max: **dead** (Anthropic ToS Feb-2026, enforced Apr-4-2026; OpenCode stripped the OAuth plugin, PR #18186). ChatGPT plan: yes (OAuth `/connect`). GitHub Copilot plan: yes | `opencode run --format json --model provider/model --agent <a> --auto`; `opencode serve` + SDK/HTTP | No | Only if you own a Copilot or ChatGPT plan and want a second harness; otherwise skip — Codex covers the ChatGPT case natively |

## What is allowed (terms)

- **Anthropic**: no rule against Claude Code invoking other vendors' tools. The 2026 crackdown is
  the *reverse* direction only — other harnesses reusing a Claude subscription's OAuth
  (ToS Feb 20 2026; Pro/Max blocked for third-party harnesses Apr 4 2026; paid "Agent SDK credit"
  as the sanctioned path from Jun 15 2026). Ruflo/claude-flow-style swarms *inside* one Claude
  login are what got hit; CLI-wrapping is unaffected.
- **OpenAI**: the plugin README states usage "will contribute to your Codex usage limits" and
  works on ChatGPT sign-in — explicit permission. `codex mcp-server` is deprecated in favor of
  the app server and this plugin.
- **Cursor**: ToS has no clause on scripted/automated/parallel use; changelog lists parallel
  local agents as a feature; ACP is a supported external-driver interface.

## Limitations — why it is not a free lunch

1. **No shared context.** Each child is a fresh session that sees only its prompt, the repo, and
   its own rules files. Every ticket brief must be fully self-contained. Orchestra's `briefs.md`
   already assumes this; the Claude rails/skills preload does **not** travel — the child reads
   `AGENTS.md`/`CLAUDE.md` (Cursor CLI reads both; Codex reads `AGENTS.md`), not `.claude/agents`,
   `.claude/rules`, or `.claude/skills`.
2. **Two permission systems, and Claude's hooks are blind.** Claude Code's PreToolUse hooks fire
   on the *Bash call*, not on what the child does inside. Your git guards, nested-agent block,
   and port guard do not apply inside a Codex or Cursor run. Safety must come from the child's
   own sandbox (Codex Seatbelt `workspace-write`, network off; Cursor `--sandbox` + `.cursor/cli.json`
   allow/deny) and from worktree isolation. Never give a child `danger-full-access` or a
   push-capable credential.
3. **Bash timeout ceiling is 10 minutes.** A build that runs longer must go through
   `run_in_background`, the Codex plugin's background jobs, or a persistent runtime (herdr).
   Output is returned as one block after exit — write logs to a scratch path and return the
   path + exit code (Orchestra's "evidence paths, never transcripts" rule already says this).
4. **Worktree discipline is mandatory.** Children write to the tree. One child per worktree;
   Cursor CLI has `-w` to create its own; Codex uses `-C`. The orchestrator still owns
   create → merge → remove.
5. **Three separate usage meters with no cross-visibility.** Claude (5-hour + weekly), Codex
   (5-hour + weekly, local and cloud shared), Cursor (plan pools + on-demand). A review-gate
   loop across two of them "may drain usage limits quickly" (plugin README). Cap rounds.
6. **The model matrix does not reach the child.** Orchestra's "YAML owns model" holds only for
   Claude agents. For a CLI worker the model is a flag (`-m`, `--model`) or a profile
   (`.codex/config.toml`, `~/.codex/<profile>.config.toml`), so the role→CLI→model map has to
   be written down and carried in the brief.
7. **Cursor CLI headless gaps.** Rules load; `.cursor/skills` and `.cursor/agents` are not
   documented as loading headless. Exit codes and stdin semantics are not documented. Shell
   mode has a hard 30-second timeout (irrelevant for `-p`, relevant for `/shell`).
8. **Evidence honesty gets weaker.** A child's "done" is a report, not evidence. Keep the
   Claude gatekeeper as the only source of gate evidence — it re-runs the command list at the
   named hash regardless of who built.
9. **Quality floor.** Cheaper worker models return more findings. The repair valve (Opus 5
   builder-max) stays a Claude role; expect more round-1 findings from Codex-mini/Composer builds.

## Is Cursor-native or another harness better?

- **Cursor as the orchestrator** (subagents with per-agent `model:`, 8 parallel worktrees, cloud
  agents, one plan) is the strongest single-app alternative — but you lose Claude Code's
  Workflow tool, hooks, the Claude-native Orchestra you just built, and Fable 5.1 as the
  judgement model unless Cursor's catalog has it at acceptable cost. Not recommended given the
  investment already made; keep Cursor as a *worker*.
- **herdr** (github.com/herdrdev/herdr, Rust, Apache-2.0, ~34k stars): a terminal multiplexer /
  runtime for ~20 agent CLIs. Each agent gets a persistent pane in a background server; state
  detection (working/blocked/idle/done) via hooks or screen patterns; sessions survive terminal
  close; **local socket API + CLI that an agent can call to spawn, prompt, and read other agents**.
  It bills nothing — each pane is the vendor CLI on its own login. What it adds to a Claude Code
  orchestrator: (a) workers that outlive the 10-minute Bash ceiling, (b) reattachable sessions,
  (c) blocked/idle detection you can poll instead of parsing stdout, (d) one screen to watch a
  20-wide wave. What it does not add: any orchestration logic, briefs, worktrees, or evidence.
  **Verdict: optional, phase 2.** Start with Bash + the Codex plugin; adopt herdr if long builds or
  visibility become the pain.
- **Conductor / vibe-kanban / claude-squad**: same mechanism (launch CLIs, ride subscriptions) with
  a UI; they replace the orchestrator role rather than serve it. vibe-kanban's original team is
  sunsetting. Not recommended alongside Orchestra.
- **Ruflo/claude-flow, OpenCode-on-Claude-OAuth**: blocked by Anthropic's 2026 terms. Do not use.

## Setup — strict steps for a seamless version

1. **Codex worker (do first — official path).**
   - `npm i -g @openai/codex`; `codex login` with the ChatGPT account (the plan pays).
   - In Claude Code: `/plugin marketplace add openai/codex-plugin-cc`,
     `/plugin install codex@openai-codex`, `/reload-plugins`, `/codex:setup`.
   - Repo `.codex/config.toml`: `model = "<gpt-5.x variant>"`, `model_reasoning_effort = "medium"`,
     `sandbox_mode = "workspace-write"`, approval `never`; a `~/.codex/builder.config.toml` profile
     for the execution tier. Codex reads `AGENTS.md` (already a symlink to `CLAUDE.md` here).
   - Thin slice: one ticket, dispatched as `/codex:rescue` or `codex exec -C <worktree> -p builder
     -o <scratch>/last.md "<brief>"`, gated by the Claude gatekeeper. Prove exit codes, worktree
     hygiene, and the usage meter before widening.
2. **Cursor worker.**
   - Install the CLI; `agent login`; project `.cursor/cli.json` with `permissions.allow/deny` and
     `approvalMode`; keep the generated `.cursor/rules/*.mdc` (the CLI loads them headless).
   - Dispatch form: `agent -p --output-format stream-json --force --model <m> --workspace <worktree>
     "<brief>" > <scratch>/cursor-<ticket>.ndjson; echo exit:$?`.
   - Reserve for scout-tier and mechanical builds; pick models from `agent --list-models`.
3. **Orchestra changes (no new roles).**
   - Add `RUNTIME: claude | codex | cursor` to the builder and scout brief templates; the Claude
     `builder`/`scout` sub-agent (Sonnet, cheap) becomes the wrapper that runs the CLI in its
     worktree, captures exit code + log path, and returns the standard trailer. Sub-agents may
     run Bash; the hook only blocks the Agent tool, so this respects "no nesting."
   - Write the role→runtime→model map into `docs/orchestra/claude-models.md` (a fourth column).
     Judgement (Fable 5.1), repair (Opus 5), gatekeeper, janitor, releaser stay Claude.
   - Rails for CLI workers live in `AGENTS.md`/`CLAUDE.md` (the files they read), not in
     `.claude/`; keep them to the three that matter (exit codes without pipes, own paths only,
     no scratch in the repo).
   - Cap cross-harness findings loops at the existing round-3 → builder-max rule.
4. **Guards.** Child sandbox on, network off unless the ticket needs it, no `gh`/`az` auth in the
   child environment, one worktree per child, Claude gatekeeper re-proves every gate.
5. **Optional, later:** herdr as the runtime for long-running or many-wide waves; the orchestrator
   spawns/prompts panes over its socket API instead of raw Bash.

## Addendum: "Grok Build" vs Grok-in-Cursor (owner question, 2026-09-02)

Two different things share the name:

- **Grok models inside Cursor** — Grok 4.5 / 4.6 (+Fast) sit in Cursor's cheaper "Cursor Models"
  pool and are selectable from the Cursor CLI with `--model grok-4.6`. This IS covered by your
  Cursor plan. Grok 4.6 is the only Cursor model with a documented effort ladder
  (`xhigh/high/medium/low`). Best fit: scout/recon and mechanical builds — cheap pool, fast.
- **Grok Build** — xAI's own terminal coding agent (open source, Apache-2.0, v1.0 on
  2026-08-07; defaults to Grok 4.6; spawns up to 8 subagents in isolated worktrees; 2M context;
  plan-then-approve loop). It requires a **SuperGrok or X Premium+ subscription — not a Cursor
  plan**. "Cursor supports it" in vendor blogs means the model is available in Cursor, not that
  a Cursor login runs Grok Build. Headless/non-interactive mode and being driven by another
  agent: **not verified** in this pass (secondary sources only; no xAI doc fetched).

Practical rule: unless you already pay for SuperGrok / X Premium+, use Grok through the Cursor
CLI, not through Grok Build. If you do have that subscription, Grok Build is a fourth worker
candidate with the same limitations list as the others — verify its headless flags and sandbox
before adding it to the runtime map.

## Sources
- Codex: learn.chatgpt.com/docs/developer-commands, /docs/pricing, /codex/mcp-server (deprecation),
  /codex/sandboxing; github.com/openai/codex-plugin-cc (README); help.openai.com "Using Codex with
  your ChatGPT plan".
- Cursor: cursor.com/docs/cli/reference/parameters, /cli/headless, /cli/using,
  /cli/reference/authentication, /cli/reference/permissions, /cli/reference/configuration,
  /cli/acp, /docs/models-and-pricing, /terms-of-service.
- OpenCode: opencode.ai/docs/{cli,server,providers,agents,rules,skills,permissions,mcp-servers,zen};
  github.com/anomalyco/opencode/pull/18186.
- Claude Code: code.claude.com/docs/en/{settings,sub-agents,sandboxing,mcp,costs,llm-gateway-connect};
  theregister.com 2026-02-20 (ToS), venturebeat (Apr-4-2026 enforcement).
- herdr: github.com/herdrdev/herdr; herdr.dev/docs. Harness comparison: Conductor docs,
  BloopAI/vibe-kanban, smtg-ai/claude-squad, openai/symphony, yegge.ai/gastown, ruvnet/ruflo.
