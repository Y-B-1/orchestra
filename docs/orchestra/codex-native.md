# Codex-native Orchestra

Codex has two deliberately separate places in Orchestra: a bounded worker is
the default, while a primary Codex session may coordinate only when the user
explicitly selects `$codex-orchestrator` or makes the equivalent choice in
plain language. Claude remains the usual coordinator.

## Operating modes

| Situation | Codex role | Context and authority |
| --- | --- | --- |
| Claude, Orca, or another IDE dispatches a brief | Worker | Execute one named role and return evidence. No routing, state ownership, nested agents, merge, or deploy unless the releaser brief carries valid authorization. |
| Codex native parent dispatches a project custom agent | Worker | Role body, model, effort, sandbox, rule reads, and nesting denial come from the generated `.codex/agents/<role>.toml`. |
| User explicitly selects Codex as the Orchestra main | Coordinator | Activate `.agents/skills/codex-orchestrator/SKILL.md`, pass its identity gate, then follow the shared flow and constitution. |
| Ordinary Codex task | Ordinary session | Follow `AGENTS.md`; do not open or resume Orchestra merely because the work is large or an old state file exists. |

A context-light Codex process can still be useful as a subagent when its
external coordinator injects a complete role-and-ticket brief. Native project
assets add deterministic role policy, model pins, rule reads, and safety hooks;
they are valuable but do not turn every worker into an orchestrator.

## Sources and generated artifacts

| Contract | Source of truth | Consumer |
| --- | --- | --- |
| Project charter | `CLAUDE.md`; tracked `AGENTS.md` is a symlink to it | Every project session |
| Worker behavior | `.claude/agents/*.md` | Claude directly; runtime generator for other hosts |
| File-scoped rules | `.claude/rules/*.md` | Claude directly; generated neutral skills for workers |
| Native Codex model policy | `docs/orchestra/codex-models.json` | Runtime generator and drift tests |
| Native Codex workers | `.codex/agents/*.toml` | Codex native subagent dispatch |
| Shared coordinator process | `.claude/skills/orchestrator/` | Claude directly; Codex adapter by path |
| Codex coordinator activation | `.agents/skills/codex-orchestrator/SKILL.md` | Explicitly selected primary Codex sessions only |
| Codex hooks | `.codex/hooks.json` and `.codex/hooks/` | Trusted local or cloud Codex surface |

Never hand-edit generated agent TOMLs. Change the Claude role source or
`codex-models.json`, then run:

```sh
python3 scripts/generate-runtimes.py
python3 scripts/generate-runtimes.py --check
```

The project charter contract is mechanically checked as `AGENTS.md ->
CLAUDE.md`; it never links to a user's global Claude file. Personal global
Codex instructions are host configuration and are not copied into this repo.

## Worker mode — the normal mixed-IDE path

An external coordinator should send a self-contained brief containing the
role, exact owned paths, sibling ownership, test-first seam, `done_when`, scoped
checks, path rules, worktree, branch, and direct-exit evidence format. Orca may
also choose Codex through `docs/orchestra/orca-runtimes.json`; its explicit
model and effort flags remain the cross-runtime routing contract.

An Orca-launched Codex worker is recognized by `ORCA_WORKTREE_ID` without the
coordinator-only `ORCA_WORKSPACE_ID`. Other external Codex launchers must set
`ORCHESTRA_CODEX_WORKER=<role>` in the worker process environment; a brief
alone does not set hook identity. If a non-Orca harness cannot inject that
environment, keep the ticket within the ordinary three-file routing floor or
use a native generated agent; do not disable the floor globally.

The standalone worker does not need the Codex coordinator skill. It must not
read or write Orchestra run state, fan out, adjudicate, or infer permission to
land. If the host supports native project custom agents, select the matching
generated name rather than overriding its model or effort.

## Native coordinator mode — explicit option

Use one of these explicit forms in a primary Codex session:

- `$codex-orchestrator`
- “Use Codex as the Orchestra coordinator for this request.”
- “Run Orchestra with Codex as the main coordinator.”

The skill rejects a dispatched role brief, an Orca worker environment, or a
request that did not explicitly choose Codex coordination before it reads flow
or state. After activation, it reads the existing Claude-source constitution
and one state at a time through `flow-state.py`; it does not maintain a second
flow copy.

Codex native dispatch uses only the generated named roles. The agent TOMLs own
model and effort, workers have native subagents disabled, and the coordinator
uses the actual capacity of its current harness. The plan's collision map—not
the configured thread ceiling—decides safe parallelism.

For every writer, the coordinator creates the worktree first and includes its
absolute path, branch, and expected HEAD in the brief. The writer must begin by
returning `pwd -P`, `git rev-parse --show-toplevel`, and
`git status --short --branch` as a premise receipt. If a Codex client cannot
honor the assigned working directory, the coordinator serializes writers; a
nominal worktree mentioned only in prose is not isolation evidence.

## Project settings and hooks

`.codex/config.toml` contains only portable project settings: native agents are
enabled, their session concurrency has an upper bound, and hooks are enabled.
It intentionally contains no profile, provider, authentication, notification,
telemetry, absolute home path, or secret.

Codex does not execute changed project hooks merely because they are committed.
Review and trust the hook definitions on the surface where they will run, then
prove at least one deny case and one allow case. Repository self-tests prove
payload behavior; they do not prove a local app or hosted task trusted the
hook. `SubagentStart` is context and mismatch reporting, not a blocking seam;
worker nesting is removed in the generated worker configuration.

There is deliberately no project-wide Codex `Stop` autonomy hook. A standalone
Orca-launched Codex worker is itself a root Codex session, and the current Stop
payload provides no tested coordinator identity. Wiring the Claude loop there
could turn a worker into the coordinator whenever shared autonomy state is
armed. Native Codex autonomy therefore stays inside the explicitly activated
coordinator turn until a session-scoped identity adapter is proven.

## State and landing

There is exactly one active coordinator for a run. That coordinator alone owns
`docs/orchestra/STATE.md`, `.orchestra/state.json`, and the batch ledger. A
Codex coordinator must reconcile recorded state with HEAD, the working tree,
and live worktrees before resuming it.

An explicitly selected Codex coordinator also acquires the session-scoped
lease with `.codex/hooks/coordinator-lease.py` before reading or changing run
state and releases it only at terminal close or explicit handoff. The lease
atomically detects a second recorded Codex coordinator in the same Git common
directory. It is a collision signal, not an authentication capability or proof
of explicit user intent. An OPEN shared state or any live Claude/Orca
coordinator still blocks acquisition and requires a deliberate handoff.

Project guards are defense in depth around the sandbox. Native worker
definitions disable nesting and mark role/read-only identity, but hooks cannot
intercept later `write_stdin` bytes sent to an already-open process and cannot
prove the effects of arbitrary interpreter bodies. Workers may not open an
interactive shell or REPL. Worker Bash is deliberately literal-only: shell
variables, globs, braces, tilde and other dynamic expansion syntax fail closed,
even when quoted and harmless. Grouping and file-descriptor duplication fail
closed because they can reopen unchecked stdin; use literal arguments or
`apply_patch`. Installed shells, interpreters, and database REPLs require a
modeled noninteractive payload; unknown options fail closed. Inherited MCP/local
tools are not considered safe until the live custom-agent receipt enumerates
and constrains that surface.
Until the project hook hash is trusted by a client, the files are configured
and self-tested—not live enforcement.

The adapter does not weaken release law. The current delivery declaration,
green gate hash, and fresh `pr-reviewer` CLEAN authorize the named releaser.
Where another Claude session owns active work, Codex may prepare an isolated
branch and draft PR but must not move remote `main` until the active session
hands off, the branch incorporates the published state, gates rerun, and review
is CLEAN again.

## Verification receipts

Do not call the integration complete from static files alone. Capture three
fresh receipts when the relevant surface is available:

1. an ordinary Codex session does not open a run or mutate the checkout;
2. a named Codex worker loads its generated role and required rule reads, cannot
   spawn a child, and returns its evidence trailer;
3. an explicitly activated `$codex-orchestrator` acquires its lease, reads one
   shared flow state, dispatches only a named role into its assigned worktree,
   waits for it, and remains the sole state writer.

Run the generator and focused hook/runtime tests before those receipts. Hook
trust and cloud behavior require their own observed receipts.
