---
name: red-team
description: How to brief and use red-teamer sub-agents — the three plan lenses (requirements, feasibility, scope), design judging, and pre-commit skepticism. A first-round clean pass on non-trivial work means the skeptic failed.
---

# Using the red-teamer

Always fresh context. Always one lens per agent. All lenses of one round dispatch in parallel, in one message.

## Brief templates

**Requirements lens** (paste spec + verbatim rulings + artifact):
```
Lens: REQUIREMENTS. Attack the plan below against the spec and rulings below.
Find requirements missing, weakened, paraphrased into something different, or
contradicted. Quote spec line vs plan line. Verdict READY/NOT-READY, findings
ranked. Under 400 words.
--- SPEC --- ... --- RULINGS (verbatim) --- ... --- PLAN --- ...
```

**Feasibility lens** (paste artifact; agent may read the codebase):
```
Lens: FEASIBILITY. Attack the plan below against the actual codebase. Every
challenge must name a real file or symbol that breaks a step — vague doubt is
not a finding. Verdict READY/NOT-READY. --- PLAN --- ...
```

**Scope lens** (paste artifact + ownership table):
```
Lens: SCOPE. Hunt: two tickets owning one file without a blocking edge; missing
blocking edges; hidden migrations; irreversible steps with no approval boundary;
work no requirement asked for. Verdict READY/NOT-READY. --- PLAN --- ...
```

**Judge** (paste 2+ alternatives + criteria):
```
Lens: JUDGE. Compare the alternatives on: <criteria — default depth, locality,
seam placement, simplicity>. Pick one winner, say what to graft from the losers.
```

## Rules

- NOT-READY findings go back to the **author** (you, for plans) — the red-teamer never repairs.
- After repair, re-dispatch only the failed lens, fresh context again.
- If all lenses pass round 1 on a non-trivial plan, tighten the briefs (add the rulings, name the diff surface) and rerun once before trusting it.
