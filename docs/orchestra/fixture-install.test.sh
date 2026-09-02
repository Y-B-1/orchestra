#!/usr/bin/env bash
# Proves install.sh keeps a Cursor-only host working (SPEC §7): every .cursor/**
# file present before install is present after, with the same frontmatter keys,
# and every line that differs traces to a named row in this file's allowed-delta
# list. Runs anywhere with bash, python3, git, diff, tar — no Node, no
# hard-coded home-directory path, no machine-specific input (repair round 2's
# portability contract).
set -uo pipefail
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; FAIL=1; }

UP="$(cd "$(dirname "$0")/../.." && pwd)"                          # package root, resolved from this script's own location — never hard-coded
SCRATCH="${SCRATCH:-$(mktemp -d)}"                                 # honour the caller's scratch dir; default to a fresh temp dir when unset
export PYTHONDONTWRITEBYTECODE=1                                   # every python3 the two installs spawn must never write .cursor/hooks/__pycache__/*.pyc — machine- and version-specific bytes that must never reach cursor.diff
export LC_ALL=C                                                    # pin collation for every sort-sensitive step below — this script's own tree walk and any sort/ls/grep -r it or install.sh runs

FIX="$SCRATCH/fixture"; rm -rf "$FIX"; mkdir -p "$FIX/pkg-old" "$FIX/old" "$FIX/new"
git -C "$UP" archive 5860b59 | tar -x -C "$FIX/pkg-old"           # the pre-port package, read-only extraction

mkhost() {
  git -C "$1" init -q
  git -C "$1" -c user.name=fixture -c user.email=f@x commit -q --allow-empty -m init
  git -C "$1" remote add origin https://github.com/example/host.git
}
mkhost "$FIX/old"
mkhost "$FIX/new"

( cd "$FIX/old" && bash "$FIX/pkg-old/install.sh" )       > "$FIX/install-old.log"    2>&1; old_exit=$?;   echo "old-exit:$old_exit"
( cd "$FIX/new" && bash "$FIX/pkg-old/install.sh" )       > "$FIX/install-new-0.log"  2>&1; seed_exit=$?;  echo "seed-exit:$seed_exit"
( cd "$FIX/new" && bash "$UP/install.sh" )                > "$FIX/install-new.log"    2>&1; new_exit=$?;   echo "new-exit:$new_exit"
[ "$new_exit" -eq 0 ] || bad "the ported install.sh exited $new_exit on the upgraded host"
[ "$seed_exit" -eq 0 ] || bad "the pre-port install.sh (seeding the 0.3.0 host) exited $seed_exit"
if [ "$old_exit" -ne 0 ]; then
  say "note: the 0.3.0 install itself exited $old_exit — recorded, never patched around; see install-old.log"
fi

# `diff -r` itself walks directories in a platform-dependent order (BSD diff on
# macOS vs GNU diff on Linux, plus locale collation) — the SAME hunks come out
# in a different sequence on each, which reads as a mismatch against a
# fixture generated on one platform. So cursor.diff is built canonically
# here instead: our own recursive walk in a fixed (C-locale, codepoint) sort
# order at every directory level, one path list valid on any platform,
# printing the exact `diff -r` line shapes ("Only in X: name",
# "diff -r old/… new/…" + the plain-diff body from a plain two-file `diff`
# call, which is order-independent because it names its two files directly).
( cd "$FIX" && python3 - old/.cursor new/.cursor <<'PY' > "$FIX/cursor.diff"
import filecmp, os, subprocess, sys

old_root, new_root = sys.argv[1], sys.argv[2]
saw_diff = False

def walk(old_dir, new_dir):
    global saw_diff
    old_names = set(os.listdir(old_dir)) if os.path.isdir(old_dir) else set()
    new_names = set(os.listdir(new_dir)) if os.path.isdir(new_dir) else set()
    for name in sorted(old_names | new_names):  # codepoint order == C locale for the ASCII names in this tree
        o, n = os.path.join(old_dir, name), os.path.join(new_dir, name)
        if name in old_names and name not in new_names:
            print(f"Only in {old_dir}: {name}"); saw_diff = True; continue
        if name in new_names and name not in old_names:
            print(f"Only in {new_dir}: {name}"); saw_diff = True; continue
        o_isdir, n_isdir = os.path.isdir(o), os.path.isdir(n)
        if o_isdir and n_isdir:
            walk(o, n)
        elif o_isdir or n_isdir:
            kind = lambda p, isdir: "directory" if isdir else "regular file"
            print(f"File {o} is a {kind(o, o_isdir)} while file {n} is a {kind(n, n_isdir)}")
            saw_diff = True
        elif not filecmp.cmp(o, n, shallow=False):
            print(f"diff -r {o} {n}")
            body = subprocess.run(["diff", o, n], capture_output=True, text=True).stdout
            sys.stdout.write(body)
            saw_diff = True

walk(old_root, new_root)
sys.exit(1 if saw_diff else 0)
PY
); diff_exit=$?; echo "diff-exit:$diff_exit"

diff "$FIX/cursor.diff" "$UP/docs/orchestra/fixtures/cursor-diff.expected" > "$FIX/expect.log" 2>&1; expect_exit=$?; echo "expect-exit:$expect_exit"
[ "$expect_exit" -eq 0 ] || { bad "cursor.diff does not match the committed expectation:"; cat "$FIX/expect.log"; }

( cd "$FIX/new" && python3 docs/orchestra/sync-agent-config.py --check ) > "$FIX/check.log" 2>&1; check_exit=$?; echo "check-exit:$check_exit"
[ "$check_exit" -eq 0 ] || { bad "sync-agent-config.py --check failed on the upgraded host:"; cat "$FIX/check.log"; }

grep -nE '__pycache__|\.pyc\b' "$FIX/cursor.diff" >/dev/null 2>&1; pyc_in_diff=$?; echo "pyc-in-diff:$pyc_in_diff"
[ "$pyc_in_diff" -eq 1 ] || bad "cursor.diff carries a __pycache__/.pyc hunk — PYTHONDONTWRITEBYTECODE did not reach every python3"

find "$FIX/old" "$FIX/new" -name '__pycache__' -o -name '*.pyc' 2>/dev/null | grep . >/dev/null 2>&1; pyc_on_disk=$?; echo "pyc-on-disk:$pyc_on_disk"
[ "$pyc_on_disk" -eq 1 ] || bad "a __pycache__/.pyc file survives on a fixture host"

# --- row-2: the three stale top-level orchestrator files are pruned (r3-2) ---
row2=$(grep -c '^Only in old/.cursor/skills/orchestrator: ' "$FIX/cursor.diff")
[ "$row2" = "3" ] || bad "expected 3 'Only in old/.cursor/skills/orchestrator:' lines (flow.json, briefs.md, STATE.template.md), got $row2"

# --- row 9: files that must NEVER appear as an actual diff hunk (CURSOR_ONLY / hand-maintained) ---
# Scoped to real diff-header/Only-in lines for the exact path — a prose mention
# of the same path inside an unrelated agent-body hunk is not a hit.
# models.md is deliberately NOT in this list (A24): it now carries the pinned
# claude-fable-5-1 id, so its content legitimately differs from the 5860b59
# baseline this fixture upgrades from — a real, once-off source edit, not
# something install.sh generates or overwrites.
row9=$(python3 - "$FIX/cursor.diff" <<'PY'
import re, sys
paths = ["hooks.json", "hooks/session-start.py", "hooks/block-nested-subagents.py"]
text = open(sys.argv[1]).read()
hits = []
for p in paths:
    base = p.rsplit("/", 1)[-1]
    if re.search(rf"^diff -r .*{re.escape(p)} ", text, re.M):
        hits.append(p)
    if re.search(rf"^Only in (old|new)/\.cursor[^:]*: {re.escape(base)}$", text, re.M):
        hits.append(p)
print("\n".join(hits))
PY
)
[ -z "$row9" ] || bad "cursor.diff carries a real hunk for a CURSOR_ONLY path: $row9"

# --- row 11: upgrade-path prune arms (round 3) — .claude/ and docs/ prunes, checked on new/ directly since diff -r only covers .cursor/ ---
n=$(grep -c 'orchestra-block-dangerous' "$FIX/new/.claude/settings.json" 2>/dev/null); [ -z "$n" ] && n=0
[ "$n" = "0" ] || bad ".claude/settings.json on the upgraded host still names orchestra-block-dangerous.py"
grep -q 'removed stale .claude/hooks/orchestra-block-dangerous.py' "$FIX/install-new.log" || bad "install-new.log missing the orchestra-block-dangerous.py prune note"

ls "$FIX/new/.claude/hooks/orchestra-block-dangerous.py" >/dev/null 2>&1 && bad "stale .claude/hooks/orchestra-block-dangerous.py survives on the upgraded host"
ls "$FIX/new/.claude/orchestra-router.md" >/dev/null 2>&1 && bad "stale .claude/orchestra-router.md survives on the upgraded host"
ls "$FIX/new/docs/orchestra/generate-claude-agents.py" >/dev/null 2>&1 && bad "stale docs/orchestra/generate-claude-agents.py survives on the upgraded host"

for stale in flow.json briefs.md STATE.template.md; do
  ls "$FIX/new/.cursor/skills/orchestrator/$stale" >/dev/null 2>&1 && bad "stale .cursor/skills/orchestrator/$stale survives on the upgraded host"
done

# --- the CLAUDE.md routing note (A23 #2): printed only on the upgrade, never on the fresh 0.3.0 install ---
grep -q 'host charter ## Orchestra block names a path removed in 0.4.0' "$FIX/install-new.log" || bad "install-new.log missing the stale-routing-pointer note"
grep -q 'host charter ## Orchestra block names a path removed in 0.4.0' "$FIX/install-old.log" && bad "install-old.log (fresh 0.3.0 install) unexpectedly prints the stale-routing-pointer note"

# --- §2.2 fixture arm: a host skills: preload survives the agent merge in
# either YAML style — flow (`skills: [a, b]`) used to be dropped silently.
# Isolated from the old/new upgrade comparison above so its fixture rule
# skills never pollute cursor.diff. ---
SK="$SCRATCH/skillhost"; rm -rf "$SK"; mkdir -p "$SK/.claude/rules"
mkhost "$SK"
printf '# x\nRule x body.\n' > "$SK/.claude/rules/x.md"
printf '# y\nRule y body.\n' > "$SK/.claude/rules/y.md"
( cd "$SK" && bash "$UP/install.sh" ) > "$FIX/install-sk-0.log" 2>&1; sk0_exit=$?
[ "$sk0_exit" -eq 0 ] || bad "install.sh exited $sk0_exit seeding the skillhost fixture"

# Replace the package's own block-style `skills:` (already merged in by the
# seed install above) with a host preload in each YAML style, so the second
# install below proves the merge reads both styles rather than just adding
# alongside an untouched block.
python3 - "$SK/.claude/agents/builder.md" "skills: [rule-x]" <<'PY'
import re, sys
p, repl = sys.argv[1], sys.argv[2]
text = open(p).read()
end = text.find("\n---\n", 4)
front, rest = text[4:end], text[end:]
front = re.sub(r"^skills:[ \t]*\n(?:[ \t]*-.*\n?)*", repl + "\n", front, count=1, flags=re.M)
open(p, "w").write("---\n" + front + rest)
PY
python3 - "$SK/.claude/agents/gatekeeper.md" "skills:\n  - rule-y" <<'PY'
import re, sys
p, repl = sys.argv[1], sys.argv[2].replace("\\n", "\n")
text = open(p).read()
end = text.find("\n---\n", 4)
front, rest = text[4:end], text[end:]
front = re.sub(r"^skills:[ \t]*\n(?:[ \t]*-.*\n?)*", repl + "\n", front, count=1, flags=re.M)
open(p, "w").write("---\n" + front + rest)
PY

( cd "$SK" && bash "$UP/install.sh" ) > "$FIX/install-sk-1.log" 2>&1; sk1_exit=$?
[ "$sk1_exit" -eq 0 ] || { bad "install.sh exited $sk1_exit re-installing over the flow-style/block-style skills: preload"; cat "$FIX/install-sk-1.log"; }

for pair in "builder.md:rule-x" "gatekeeper.md:rule-y"; do
  af="${pair%%:*}"; host_skill="${pair##*:}"
  merged="$SK/.claude/agents/$af"
  n=$(grep -c "^\s*-\s*orchestra-rails\s*\$" "$merged" 2>/dev/null); [ -z "$n" ] && n=0
  [ "$n" = "1" ] || bad "$af: orchestra-rails should appear exactly once after merge, found $n"
  grep -qE "^\s*-\s*${host_skill}\s*\$" "$merged" || bad "$af: host preload $host_skill did not survive the merge"
done

# --- symlink-mirror arm: a host that mirrors a skill as a directory symlink
# (.cursor/skills/<x> -> .claude/skills/<x>, the DEVOPS TS generator's
# SYMLINK_MIRRORS convention) must be SATISFIED as-is: --check exits 0 without
# the generated-copy banner, and a write pass must never replace the symlink.
SYML="$SCRATCH/symlinkhost"; rm -rf "$SYML"
mkdir -p "$SYML/.claude/skills/react-doctor" "$SYML/.cursor/skills"
mkhost "$SYML"
printf -- '---\nname: react-doctor\ndescription: test skill for the symlink-mirror arm.\n---\n\nBody.\n' > "$SYML/.claude/skills/react-doctor/SKILL.md"
ln -s ../../.claude/skills/react-doctor "$SYML/.cursor/skills/react-doctor"
sym_src_before="$(shasum "$SYML/.claude/skills/react-doctor/SKILL.md" | cut -d" " -f1)"

( cd "$SYML" && python3 "$UP/docs/orchestra/sync-agent-config.py" --root "$SYML" --check ) > "$FIX/symlink-check-before.log" 2>&1; sym_check_before=$?
[ "$sym_check_before" -eq 0 ] || { bad "sync-agent-config.py --check failed on a host whose react-doctor mirror is a symlink:"; cat "$FIX/symlink-check-before.log"; }

( cd "$SYML" && python3 "$UP/docs/orchestra/sync-agent-config.py" --root "$SYML" ) > "$FIX/symlink-write.log" 2>&1; sym_write_exit=$?
[ "$sym_write_exit" -eq 0 ] || bad "sync-agent-config.py write pass exited $sym_write_exit on the symlink-mirror host"

[ -L "$SYML/.cursor/skills/react-doctor" ] || bad "write pass replaced the symlink mirror at .cursor/skills/react-doctor with a copy"
[ "$(readlink "$SYML/.cursor/skills/react-doctor")" = "../../.claude/skills/react-doctor" ] || bad "symlink mirror target changed after the write pass"
# The real damage a write-through does is to the SOURCE: a directory symlink hands the writer the .claude file.
[ "$(shasum "$SYML/.claude/skills/react-doctor/SKILL.md" | cut -d" " -f1)" = "$sym_src_before" ] || bad "write pass wrote THROUGH the symlink and changed .claude/skills/react-doctor/SKILL.md"

( cd "$SYML" && python3 "$UP/docs/orchestra/sync-agent-config.py" --root "$SYML" --check ) > "$FIX/symlink-check-after.log" 2>&1; sym_check_after=$?
[ "$sym_check_after" -eq 0 ] || { bad "sync-agent-config.py --check failed after the write pass on the symlink-mirror host:"; cat "$FIX/symlink-check-after.log"; }

[ "$FAIL" -eq 0 ] && say "FIXTURE OK" || say "FIXTURE FAILED — fix the FAIL lines above"
exit "$FAIL"
