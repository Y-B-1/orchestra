# Native Codex model matrix — Orchestra workers

This is the human-readable contract for Codex-native custom agents. The
machine-readable source is `docs/orchestra/codex-models.json`; generated files
under `.codex/agents/` consume it directly.

This matrix is separate from `orca-runtimes.json`. Orca fallback chains choose
between external runtimes, while this file pins the model and reasoning effort
for a named subagent created by a native Codex coordinator. Changing a row is a
model-policy change, not a generator refactor.

| Role | Model | Effort |
| --- | --- | --- |
| architect | `gpt-5.6-sol` | `xhigh` |
| auditor | `gpt-5.6-sol` | `high` |
| builder | `gpt-5.6-sol` | `high` |
| builder-frontend | `gpt-5.6-sol` | `high` |
| builder-max | `gpt-5.6-sol` | `xhigh` |
| builder-sensitive | `gpt-5.6-sol` | `xhigh` |
| builder-speed | `gpt-5.6-sol` | `low` |
| founder-mind | `gpt-5.6-sol` | `xhigh` |
| gatekeeper | `gpt-5.6-sol` | `low` |
| janitor | `gpt-5.6-sol` | `low` |
| planner | `gpt-5.6-sol` | `xhigh` |
| pr-reviewer | `gpt-5.6-sol` | `xhigh` |
| red-teamer | `gpt-5.6-sol` | `xhigh` |
| releaser | `gpt-5.6-sol` | `high` |
| researcher | `gpt-5.6-luna` | `xhigh` |
| reviewer | `gpt-5.6-sol` | `medium` |
| scout | `gpt-5.6-sol` | `low` |

The mapping preserves the settled constraints: Luna is restricted to the
researcher tier and runs only at `xhigh`; Luna never builds; Terra remains
retired. `builder-max` is the high-reasoning repair lane and is never a first
attempt.

Every generated worker disables native subagents. Auditor, pr-reviewer,
red-teamer, reviewer, and scout additionally use the read-only sandbox because
their source contracts do not produce repository changes. Architect, planner,
janitor, and researcher remain writable because their contracts can produce
documents; gatekeeper remains writable because verification commands can
produce build and test artifacts.

There is no orchestrator row or `.codex/agents/orchestrator.toml`. Native Codex
coordination belongs to the explicit main-session adapter, never a child agent.
