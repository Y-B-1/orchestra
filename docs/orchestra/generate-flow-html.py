#!/usr/bin/env python3
"""Generate docs/flow.html from .cursor/skills/orchestrator/flow.json.

The JSON is the only statement of routing. This file is the human view.
Run after editing flow.json. `install.sh` --check-mode fails if a state is missing.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import sys

ROOT_CANDIDATES = ("docs/orchestra/generate-flow-html.py",)
FLOW = os.path.join(".cursor", "skills", "orchestrator", "flow.json")
OUT = os.path.join("docs", "flow.html")

PHASES = [
    ("Intake", ("intake",)),
    ("Lanes", ("trivial.inline", "small.design", "small.build", "small.close")),
    ("Design", ("design.recon", "design.frontier", "design.approaches", "design.spec", "design.gate")),
    ("Plan", ("plan.recon", "plan.draft", "plan.redteam")),
    ("Execute", ("execute.setup", "execute.ticket-loop", "execute.review", "execute.integrate", "execute.wave-close")),
    ("Gates & audit", ("gates.fast", "review.pr", "audit.decide", "audit.run")),
    ("Release", ("release.merge", "release.deploy", "release.rollback")),
    ("Full suite & bug", ("fullsuite.run", "bug.feedback-loop")),
    ("Cleanup & terminal", ("cleanup.final", "terminal.done")),
    ("Autonomy", ("autonomy.loop",)),
]

CSS = """
  :root{
    --bg:#f6f7f9; --card:#ffffff; --ink:#1a1d21; --muted:#5b6470; --line:#e3e6ea;
    --accent:#4f46e5; --scout:#0e7490; --research:#7c3aed; --red:#b91c1c; --build:#b45309;
    --review:#0f766e; --audit:#9d174d; --gate:#334155; --janitor:#4d7c0f; --release:#1d4ed8;
    --author:#0369a1; --gatebg:#fff7ed; --invbg:#eef2ff; --alwaysbg:#f0fdf4; --backc:#b91c1c;
  }
  @media (prefers-color-scheme: dark){
    :root{ --bg:#111417; --card:#1a1f24; --ink:#e8eaed; --muted:#9aa4b0; --line:#2a3138;
      --accent:#818cf8; --scout:#22d3ee; --research:#c4b5fd; --red:#f87171; --build:#fbbf24;
      --review:#5eead4; --audit:#f472b6; --gate:#cbd5e1; --janitor:#a3e635; --release:#93c5fd;
      --author:#7dd3fc; --gatebg:#2a2118; --invbg:#1e2140; --alwaysbg:#132a1a; --backc:#f87171; }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:2rem 1rem 4rem}
  .wrap{max-width:1080px;margin:0 auto}
  h1{font-size:1.6rem;margin:0 0 .25rem}
  .sub{color:var(--muted);margin:0 0 1.5rem;max-width:75ch}
  h2{font-size:1.05rem;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin:2.2rem 0 .8rem;border-bottom:1px solid var(--line);padding-bottom:.4rem}
  .phase{display:flex;flex-direction:column;gap:.9rem}
  .state{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:.9rem 1.1rem;box-shadow:0 1px 2px rgba(0,0,0,.05)}
  .state h3{margin:0 0 .15rem;font-size:1rem;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
  .q{color:var(--muted);font-style:italic;margin:0 0 .6rem}
  .always{background:var(--alwaysbg);border:1px solid var(--line);border-radius:7px;padding:.4rem .7rem;font-size:.85rem;margin:.4rem 0 .6rem}
  .always::before{content:"ALWAYS ";font-weight:700;font-size:.72rem;color:var(--janitor)}
  table{border-collapse:collapse;width:100%}
  td{vertical-align:top;padding:.32rem .5rem;border-top:1px solid var(--line);font-size:.92rem}
  td.if{width:34%;font-weight:600}
  td.if::before{content:"IF ";color:var(--accent);font-weight:700;font-size:.75rem}
  td.then::before{content:"THEN ";color:var(--muted);font-weight:700;font-size:.75rem}
  td.then.back::before{content:"BACK TO ";color:var(--backc);font-weight:700;font-size:.75rem}
  .role{display:inline-block;font:600 .72rem/1 ui-monospace,Menlo,monospace;padding:.2rem .45rem;border-radius:999px;border:1.5px solid currentColor;margin-left:.4rem;white-space:nowrap}
  .r-scout{color:var(--scout)} .r-researcher{color:var(--research)} .r-red{color:var(--red)}
  .r-builder{color:var(--build)} .r-reviewer{color:var(--review)} .r-auditor{color:var(--audit)}
  .r-gatekeeper{color:var(--gate)} .r-janitor{color:var(--janitor)} .r-releaser{color:var(--release)}
  .r-author{color:var(--author)}
  .gate{background:var(--gatebg)}
  .inv{background:var(--invbg);border:1px solid var(--line);border-radius:10px;padding:1rem 1.3rem}
  .inv li{margin:.35rem 0}
  .roster{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:.7rem}
  .roster .state{padding:.7rem .9rem}
  .roster p{margin:.2rem 0 0;font-size:.88rem;color:var(--muted)}
  .match{font-size:.8rem;color:var(--muted);margin:0 0 .4rem}
  @media(max-width:640px){ td.if{width:40%} body{padding:1rem .6rem 3rem} }
"""

ROLE_CLASS = {
    "scout": "r-scout",
    "researcher": "r-researcher",
    "red-teamer": "r-red",
    "builder": "r-builder",
    "builder-max": "r-builder",
    "reviewer": "r-reviewer",
    "pr-reviewer": "r-reviewer",
    "auditor": "r-auditor",
    "gatekeeper": "r-gatekeeper",
    "janitor": "r-janitor",
    "releaser": "r-releaser",
    "architect": "r-author",
    "planner": "r-author",
}


def esc(s):
    return html.escape(s, quote=True)


def pills(dispatch):
    if not dispatch:
        return ""
    out = []
    for tok in dispatch.replace("+", "|").split("|"):
        tok = tok.strip()
        if not tok:
            continue
        base = tok.split(":")[0].split("@")[0].strip()
        cls = ROLE_CLASS.get(base, "r-author")
        out.append(f'<span class="role {cls}">{esc(tok)}</span>')
    return " " + "".join(out)


def then_cell(route):
    if route.get("back_to"):
        carry = route.get("carry") or ""
        text = route["back_to"]
        if carry:
            text += " — " + carry
        extra = ""
        if route.get("then"):
            t = route["then"]
            extra = " " + (" ".join(t) if isinstance(t, list) else str(t))
        return f'<td class="then back">{esc(text + extra)}{pills(route.get("dispatch", ""))}</td>'
    parts = []
    then = route.get("then")
    if isinstance(then, list):
        parts.append(" · ".join(then))
    elif then:
        parts.append(str(then))
    if route.get("next"):
        parts.append("→ " + route["next"])
    if route.get("loop"):
        loop = route["loop"]
        if not any(loop in p for p in parts):
            parts.append("↻ " + loop)
    body = " ".join(parts) if parts else "(stay)"
    return f'<td class="then">{esc(body)}{pills(route.get("dispatch", ""))}</td>'


def render_state(name, st):
    gate = " gate" if "gate" in name or name.startswith("release.") else ""
    q = st.get("question")
    match = st.get("match")
    bits = [f'<div class="state{gate}"><h3>{esc(name)}</h3>']
    if match:
        bits.append(f'<p class="match">match: {esc(match)}</p>')
    if q:
        bits.append(f'<p class="q">{esc(q)}</p>')
    for a in st.get("always") or []:
        bits.append(f'<div class="always">{esc(a)}</div>')
    routes = st.get("routes") or []
    if routes:
        bits.append("<table>")
        for r in routes:
            bits.append("<tr>")
            bits.append(f'<td class="if">{esc(r.get("if", ""))}</td>')
            bits.append(then_cell(r))
            bits.append("</tr>")
        bits.append("</table>")
    bits.append("</div>")
    return "\n".join(bits)


def generate(data):
    states = data["states"]
    roles = data.get("roles") or {}
    chunks = [
        "<!doctype html>",
        '<html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{esc(data.get('title', 'Orchestra routing'))}</title>",
        f"<style>{CSS}</style></head><body><div class=\"wrap\">",
        f"<h1>{esc(data.get('title', 'Orchestra routing'))}</h1>",
        '<p class="sub">Generated from <code>.cursor/skills/orchestrator/flow.json</code> '
        "(the only statement of routing). Do not edit this HTML by hand — run "
        "<code>docs/orchestra/generate-flow-html.py</code>. Intake is exclusive "
        "(<code>match: first</code>). Green blocks are standing duties; red BACK TO "
        "rows carry a payload. Autonomy is a first-class state.</p>",
        "<h2>Roster</h2><div class=\"roster\">",
    ]
    for role, desc in roles.items():
        chunks.append(f'<div class="state"><h3>{esc(role)}</h3><p>{esc(desc)}</p></div>')
    chunks.append("</div>")

    placed = set()
    for title, names in PHASES:
        chunks.append(f"<h2>{esc(title)}</h2><div class=\"phase\">")
        for name in names:
            if name in states:
                chunks.append(render_state(name, states[name]))
                placed.add(name)
        chunks.append("</div>")

    leftover = [n for n in states if n not in placed]
    if leftover:
        chunks.append("<h2>Other states</h2><div class=\"phase\">")
        for name in leftover:
            chunks.append(render_state(name, states[name]))
        chunks.append("</div>")

    interrupts = data.get("interrupts") or {}
    if interrupts:
        chunks.append("<h2>Interrupts</h2><div class=\"phase\"><div class=\"state\"><table>")
        for k, v in interrupts.items():
            then = v.get("then", "")
            if v.get("back_to"):
                then = f"back to {v['back_to']}: {then}"
            chunks.append(f'<tr><td class="if">{esc(k)}</td><td class="then">{esc(then)}</td></tr>')
        chunks.append("</table></div></div>")

    cloud = data.get("cloud") or {}
    if cloud:
        chunks.append("<h2>Running in the cloud</h2><div class=\"phase\"><div class=\"state\"><table>")
        for k, v in cloud.items():
            chunks.append(f'<tr><td class="if">{esc(k)}</td><td class="then">{esc(v)}</td></tr>')
        chunks.append("</table></div></div>")

    inv = data.get("invariants") or []
    if inv:
        chunks.append("<h2>Invariants</h2><div class=\"inv\"><ul>")
        for i in inv:
            chunks.append(f"<li>{esc(i)}</li>")
        chunks.append("</ul></div>")

    chunks.append("</div></body></html>\n")
    return "\n".join(chunks)


def missing_states(data, html_text):
    return [name for name in data["states"] if name not in html_text]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="exit 1 if flow.html omits a state")
    args = parser.parse_args()
    if not os.path.isfile(FLOW):
        print(f"FAIL: {FLOW} missing", file=sys.stderr)
        return 1
    data = json.load(open(FLOW))
    if args.check:
        if not os.path.isfile(OUT):
            print(f"FAIL: {OUT} missing", file=sys.stderr)
            return 1
        text = open(OUT).read()
        miss = missing_states(data, text)
        if miss:
            print("FAIL: flow.html missing states: " + ", ".join(miss), file=sys.stderr)
            return 1
        if "autonomy.loop" not in text:
            print("FAIL: flow.html missing autonomy.loop", file=sys.stderr)
            return 1
        print("flow.html covers every flow.json state")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    html_text = generate(data)
    with open(OUT, "w") as f:
        f.write(html_text)
    miss = missing_states(data, html_text)
    if miss:
        print("FAIL: generator omitted " + ", ".join(miss), file=sys.stderr)
        return 1
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
