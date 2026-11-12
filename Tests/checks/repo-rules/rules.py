"""The rules that keep branches out of each other's way (2026-11-12, branch `tooling-speedup`): every
check folder describes itself, no table or list of the checks is kept by hand, CI reads the checks
with mutants from the folders, and the notes of a piece of work go in its own docs/steps file, not
back into CLAUDE.md. Prints `ok` or `FAIL` per rule, exits 1 on any FAIL. usage: rules.py ROOT"""
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True      # importing mutant-checks.py leaves no __pycache__ behind
root = sys.argv[1]
checks = os.path.join(root, "Tests/checks")
failed = passed = 0


def rule(ok, what, detail=""):
    global failed, passed
    if ok:
        passed += 1
        print(f"ok   {what}")
    else:
        failed += 1
        print(f"FAIL {what}" + (f": {detail}" if detail else ""))


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


# 1. Each check describes itself: README.md, its name as the heading, **Checks:** and **Compiles:**.
folders = sorted(d for d in os.listdir(checks) if os.path.isfile(os.path.join(checks, d, "run.sh")))
bad = []
for name in folders:
    path = os.path.join(checks, name, "README.md")
    if not os.path.isfile(path):
        bad.append(f"{name} (no README.md)")
        continue
    text = read(path)
    if not text.startswith(f"# `{name}`\n"):
        bad.append(f"{name} (README.md does not start with \"# `{name}`\")")
    if "\n**Checks:** " not in text:
        bad.append(f"{name} (no **Checks:** paragraph)")
    if "\n**Compiles:** " not in text:
        bad.append(f"{name} (no **Compiles:** paragraph)")
rule(not bad, f"each of the {len(folders)} check folders says what it checks in its own README.md",
     "; ".join(bad) + " (Tests/checks/README.md, \"Adding a check\")")

# 2. No table of the checks kept by hand in Tests/checks/README.md (it is printed by list.sh).
rows = [l for l in read(os.path.join(checks, "README.md")).split("\n") if re.match(r"^\| `[^`]+` \|", l)]
rule(not rows, "Tests/checks/README.md keeps no table of the checks (list.sh prints one)",
     f"{len(rows)} table rows, first: {rows[0][:80] if rows else ''}")

# 3. CI's mutants matrix is read from the folders, never listed by hand, and checked before it runs.
ci = read(os.path.join(root, ".github/workflows/ci.yml"))
static = [l.strip() for l in ci.split("\n") if re.match(r"^\s*check: \[", l)]
rule(not static, "ci.yml lists no checks by hand", static[0][:80] if static else "")
rule("check: ${{ fromJSON(needs.mutant-checks.outputs.checks) }}" in ci
     and "Tests/checks/mutant-checks.py --github-output" in ci,
     "ci.yml's mutants matrix comes from Tests/checks/mutant-checks.py, which checks it first",
     "the mutants job must take `check: ${{ fromJSON(needs.mutant-checks.outputs.checks) }}` from the "
     "mutant-checks job, whose step runs `python3 Tests/checks/mutant-checks.py --github-output`")

# 4. The listing CI uses: every folder with a run.sh and a mutants.py, as JSON that reads back, and
#    the guard passing on it (an untracked mutants.py is only a warning here: CI never sees one).
spec = importlib.util.spec_from_file_location("mutant_checks", os.path.join(checks, "mutant-checks.py"))
mc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mc)
listed = mc.listing()
walked = sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(checks, "*", "mutants.py"))
                if os.path.isfile(os.path.join(os.path.dirname(p), "run.sh")))
text = json.dumps(listed, separators=(",", ":"))
rule(listed == walked and json.loads(text) == walked and listed,
     f"mutant-checks.py lists the {len(walked)} folders with a mutants.py, as JSON that reads back",
     f"listed {len(listed)}, found {len(walked)}")
problems, _ = mc.verify(text)
untracked = subprocess.run(["git", "-C", root, "ls-files", "--others", "--exclude-standard", "--",
                            "Tests/checks/*/mutants.py"], capture_output=True, text=True).stdout.split()
untracked_names = {p.split("/")[2] for p in untracked if p.count("/") == 3}
real = [p for p in problems if not (p.startswith("not a folder with a mutants.py in git")
                                    and set(p.split(": ", 1)[1].split(", ")) <= untracked_names)]
for name in sorted(untracked_names):
    print(f"note Tests/checks/{name}/mutants.py is not in git yet: CI runs its mutants once it is committed")
rule(not real, "mutant-checks.py's guard passes on that list", "; ".join(real))

# 5. The notes: CLAUDE.md keeps the pointer and no step entries; docs/steps holds them, well named.
claude = read(os.path.join(root, "CLAUDE.md"))
lines = claude.split("\n")
rule("## Steps" in lines, "CLAUDE.md has its \"Steps\" section (where the notes are, and how to add one)")
entry = re.compile(r"^\*\*[^*]*20\d\d-\d\d-\d\d")
entries = [l for l in lines if entry.match(l) or l == "## Current step" or l.startswith("## Milestone ")]
rule(not entries, "CLAUDE.md holds no step entry (each is docs/steps/<date>-<branch>.md)",
     f"{len(entries)} entry lines, first: {entries[0][:90] if entries else ''} "
     "(move it to its own file: python3 Scripts/migrate-notes.py --move-entries; a branch opened "
     "before 2026-11-12 runs python3 Scripts/migrate-notes.py once, right after merging main)")
steps = os.path.join(root, "docs/steps")
names = sorted(f for f in os.listdir(steps) if f.endswith(".md") and f != "README.md")
badnames = [f for f in names if not re.match(r"^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9.-]*\.md$", f)]
rule(names and not badnames, f"docs/steps' {len(names)} files are named <date>-<branch>.md",
     ", ".join(badnames))
empty = [f for f in names if not read(os.path.join(steps, f)).strip()]
rule(not empty, "no step file is empty", ", ".join(empty))

print(f"repo-rules: {passed} of {passed + failed} rules hold")
sys.exit(1 if failed else 0)
