---
name: research
description: How to brief and use the researcher sub-agent for primary-source research into external APIs, dependencies, and standards. Use for any post-cutoff or version-sensitive question; never let a plan cite model memory for those.
---

# Using the researcher

Dispatch `researcher` (background) when the work touches an unknown API, a dependency version newer than model knowledge, or an industry standard the design leans on.

## Brief template

```
Research the following against PRIMARY sources only (official docs, changelogs,
dependency source in node_modules). Installed version first (check lockfile).
Questions:
1. <question>
Write findings to <repo path>/RESEARCH.md with per-claim citations and an
"expires: end of current sprint" header. Record negative results too.
Return a summary + the file path.
```

## Rules for consuming the output

- Plans and tickets cite `RESEARCH.md`, never "the researcher said".
- Conflicting-source findings are decisions: surface them to the user with a recommendation.
- **Expiry is real.** When the sprint ends, the janitor lists the file for deletion; stale research misleads agents. Re-research rather than trust an expired file.
