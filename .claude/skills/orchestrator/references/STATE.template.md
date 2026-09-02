# STATE — <project> (written-at: <ISO timestamp> @ <git HEAD short hash>)

## Run
- status: <OPEN | idle>
- lane: <full-chain | small | bug | none>
- flow state: <e.g. execute.wave-close>
- spec: <path or —>
- plan: <path or —>
- ledger: <docs/plans/<feature>-ledger.md or —>

## Open items (pointers, not content)
- rulings: <spec path>#rulings
- findings in flight: <ledger path>#<ticket>
- staged: <exact command or —>
- deferred: <blocked rail such as host MCP apply_migration, or —>

## Next action
<one line: the single next step on resume>

## Long-term pointers
- memory: docs/AGENT-MEMORY.md — load sections on demand, never wholesale
- research: <RESEARCH.md path + expiry, or —>
- last full-suite run: <date + result pointer, or —>
