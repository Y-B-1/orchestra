# Cross-runtime model matrix — Orca dispatch

(SCOPE: this matrix governs Orca `worker-start --agent/--model/--effort` dispatch across
Claude/Codex/Cursor/OpenCode. For pure-Claude sub-agent work inside one Claude Code session,
docs/orchestra/claude-models.md remains the matrix. Fallback fires on the limit signatures in
orca-runtimes.json — check `orca account list --json` usage windows before dispatching a wave.
Reworked 2026-09-02, user ruling: chains are set by HOW MUCH INTELLIGENCE the role needs,
nothing else. The matrix IS the law — dispatch follows it verbatim, no rank re-derivation,
no tier rules, no checker script.)

**Luna effort peg (user, 2026-09-03, verbatim): "peg the luna model at max effort? Only use it at
max effort."** Implemented as xhigh — Codex's maximum tier; every Luna step in every chain carries it.

**Standing bans (user, 2026-09-02):** Luna and Composer never build — any builder lane, any
step. Terra is retired everywhere (Sol covers its review slot, Luna its research slot).
Orca cannot read Cursor usage (no telemetry; limits surface only as mid-run signatures), so
every Cursor-primary lane keeps a non-Cursor fallback.

## The matrix — ordered by intelligence the role needs

### Highest — verdicts and briefs

| Role | Primary | → | Floor |
|---|---|---|---|
| Orchestrator (entry door) | Fable 5 · low · Claude | — | Opus 5 · low |
| Architect | Fable 5 · low · Claude | Sol · xhigh · Codex | Opus 5 · medium |
| Founder-mind (U21: implementation-space dossier / audit lens) | Fable 5 · low · Claude | — | Opus 5 · medium |
| Planner | Fable 5 · low · Claude | Sol · xhigh · Codex | Opus 5 · medium |
| PR-reviewer (exit door) | Fable 5 · low · Claude | Sol · xhigh · Codex | Opus 5 · medium |

### High — adversarial analysis and repair

| Role | Primary | → | Floor |
|---|---|---|---|
| Red-teamer | Sol · xhigh · Codex | Grok 4.6 xhigh · Cursor | Opus 5 · medium |
| Builder-max (repair valve) | Opus 5 · medium · Claude | Sol · xhigh · Codex | Sonnet 5 · medium |
| Builder (rule-sensitive) | Opus 5 · medium · Claude | — | Sonnet 5 · medium |
| Auditor | Sol · high · Codex | Grok 4.6 high · Cursor | Sonnet 5 · medium |

### Mid — planned building and per-ticket review

| Role | Primary | → | → | Floor |
|---|---|---|---|---|
| Builder (default) | Grok 4.6 high · Cursor | Sol · high · Codex | GLM-5.3 · OpenCode Go | Sonnet 5 · medium |
| Builder (frontend) | Kimi K3 · OpenCode Go | Grok 4.6 high · Cursor | Sol · high · Codex | Sonnet 5 · medium |
| Builder (speed lane) | Grok 4.6 high-fast · Cursor | Kimi K3 · OpenCode Go | GLM-5.3 · OpenCode Go | Sonnet 5 · low |
| Reviewer (per ticket) | Grok 4.6 high · Cursor | Sol · medium · Codex | — | Sonnet 5 · low |

### Lower — retrieval, summarizing, mechanical

| Role | Primary | → | → | Floor |
|---|---|---|---|---|
| Researcher | Luna · xhigh · Codex | GLM-5.3 · OpenCode Go | — | Sonnet 5 · medium |
| Scout | Grok 4.6 high-fast · Cursor | Composer 2.5 · Cursor | GLM-5.3-Flash · OpenCode Go | Sonnet 5 · low |
| Gatekeeper | Sonnet 5 · low · Claude | — | — | (itself) |
| Janitor | Sonnet 5 · low · Claude | — | — | (itself) |
| Releaser | Sonnet 5 · low · Claude | — | — | (itself) |

## Notes on placement

- **Fable 5 runs at `low` everywhere.** Four roles only: the two doors plus architect and planner.
- **Builder-max keeps Opus 5 first** — the user's call (2026-09-02): Opus 5 beats Sol xhigh
  on repair work. Sol xhigh stays as its second-best fallback.
- **Builder fallbacks escalate to Sol, never sideways to C-tier.** A build that Cursor
  drops mid-limit is exactly the build worth a stronger second attempt; the old Luna/Composer
  steps were weaker than the Sonnet floor beneath them, which is why they are banned.
- **Kimi K3 owns the frontend builder lane** — strongest OpenCode Go model on single-shot
  coding. Keep its tickets short and well-specified; frontend refactors spanning many files
  go to the default builder instead.
- **GLM-5.3 / GLM-5.3-Flash absorb overflow** on OpenCode Go when the Cursor and ChatGPT
  windows are spent.
- **Researcher runs on Luna** because research here is retrieval-and-summarize from primary
  docs; its citations are verified downstream by Fable-written plans. If a research task is
  plan-shaping, dispatch it as Grok 4.6 high · Cursor with a note in the brief.
- **Rule-sensitive builds run on Opus 5 in Claude** — those paths must stay inside Claude
  Code's hooks and are the ones worth the strongest builder.
- Gatekeeper, janitor, and releaser are single-step: they hold credentials and produce gate
  evidence, so they never leave Claude, and Sonnet 5 is both primary and floor.
- **Unrouted:** Terra (retired 2026-09-02), Grok 4.6 low-fast, Grok Build via xAI.
