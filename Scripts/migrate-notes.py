#!/usr/bin/env python3
"""Moves a branch's notes out of the spots every branch used to edit at once (2026-11-12, branch
`tooling-speedup`): CLAUDE.md's "Current step" became one file per piece of work in docs/steps/, the
table of Tests/checks/README.md one README.md per check folder, and CI's list of checks with mutants
is read from the folders. A branch opened before that keeps its notes in the old places; this moves
them, so its owner does it in one command.

In such a branch, right after `git merge origin/main` stops on conflicts:

    python3 Scripts/migrate-notes.py      resolves and stages CLAUDE.md, Tests/checks/README.md,
                                          docs/DEVELOPMENT.md and .github/workflows/ci.yml
    git status                            any other conflict is the branch's own, as before
    git commit

It reads the three versions git keeps during the merge (the merge base, this branch's, main's), so it
works whatever the conflicted files look like now, and writes only in the working tree:
- CLAUDE.md: each "Current step" entry this branch added becomes docs/steps/<date>-<branch>.md; an
  entry it changed is merged three ways into the file main gave that entry. Its other changes to
  CLAUDE.md (Layout, Build and run, ...) are merged into main's CLAUDE.md.
- Tests/checks/README.md: each table row this branch added or changed becomes, or is merged into,
  Tests/checks/<name>/README.md (counts left out: a check prints its own). The file itself is main's;
  any other change the branch made to it is printed, to carry by hand if still wanted.
- docs/DEVELOPMENT.md: "The pure checks" paragraph is main's, the branch's other changes are kept.
- .github/workflows/ci.yml: the mutants matrix is main's (read from the folders), the rest is merged.
A file whose three-way merge conflicts keeps its markers and is named; nothing is committed, nothing
leaves this machine.

    python3 Scripts/migrate-notes.py --ours REV --theirs REV    the same after a merge already
                                          committed (HEAD^1 and HEAD^2), or between any two commits
    python3 Scripts/migrate-notes.py --move-entries             an entry written into CLAUDE.md after
                                          the move (its "Steps" section), out to its own step file
    python3 Scripts/migrate-notes.py --absorb                   the other way round: in a branch that
                                          has the new layout (tooling-speedup until it merges), right
                                          after merging a main that does not yet, main's new entries,
                                          rows and lists go where the layout puts them
    python3 Scripts/migrate-notes.py --convert                  the conversion itself, once, on the
                                          working tree (tooling-speedup used it on main at 936d627)
    python3 Scripts/migrate-notes.py --verify REV               checks that docs/steps and the check
                                          folders' README.md hold REV's entries and rows word for word
"""
import collections
import difflib
import os
import re
import subprocess
import sys
import tempfile

DATE = re.compile(r"20\d\d-\d\d-\d\d")
CLAUDE, CHECKS_README, DEVELOPMENT, CI = (
    "CLAUDE.md", "Tests/checks/README.md", "docs/DEVELOPMENT.md", ".github/workflows/ci.yml")
STEPS = "docs/steps"
OLD_SECTION = "## Current step"
NEW_SECTION = "## Steps"
# Two blocks of the old Current step that do not open with a bold, dated title, and their names.
SPECIAL = {
    "Milestone 3, scaling and the virtual display.": "milestone-3",
    "Still open: the unexplained one-off stall": "still-open",
}
CHECKS_BULLET_START = "- `Tests/checks/` — the pure checks, a folder each"
DEV_HEADING = "### The pure checks"
MATRIX_OLD = re.compile(r"^\s*check: \[.*\]\s*$")
MATRIX_NEW = re.compile(r"^\s*check: \$\{\{ fromJSON\(")

# What --convert writes in place of the old Current step and the milestones (the pointer), and in
# place of the Layout's list of checks. The migration reads both back from main's CLAUDE.md instead,
# so a later edit of them on main is never undone by a branch's merge.
POINTER = """\
## Steps

What each piece of work did (a branch, a release, a finding) is in `docs/steps/`, one file each,
named `<date>-<branch>.md` with the date the work began, so the newest are last by name:
`Scripts/steps.sh list` prints the newest first (or `ls docs/steps | sort -r | head`);
`Scripts/steps.sh find 349` finds a pull request's (or `grep -l '#349' docs/steps/*`), and
`ls docs/steps/*keep-vpn*` a branch's. Before starting, read the step file of the work you continue
and the newest few.

A branch writes its notes in its own step file (`Scripts/steps.sh new` makes it), never in this
file, so no two branches edit the same lines for their notes. Until 2026-11-12 the notes were this
file's "Current step", newest first; they moved word for word, and `docs/steps/README.md` lists them
in that order. A code comment that cites `CLAUDE.md, "<title>"` (or "Current step") means the step
file with that title: `grep -l '<title>' docs/steps/*`. A branch opened before the move runs
`python3 Scripts/migrate-notes.py` once, right after merging main (the script's header says how).

Rules found in the steps that hold for all work (each where it is written):
- While Noah streams, nothing that shares the Mac's one video encoder: no `simctl io recordVideo`,
  SillHost stream, ReelRenderer or encoder benchmark, and no Simulator panel in the Claude app
  (docs/steps/2026-09-24-encoder-recovery.md, "Operational rule").
- Host code: `SillHostCore`'s `package` access, never `MainActor.assumeIsolated` in core code, the
  modal-loop rule, the CLI's byte-identical stdout, App Nap; TCC and the signing identity
  (docs/steps/2026-09-23-menu-bar-app.md, "Rules." and "TCC:").
- ScreenCaptureKit sends frames only when a window repaints, so a covered window freezes on the
  device (docs/steps/2026-09-22-milestone-1.md, "Learned"), and AWDL takes the Mac's radio off its
  Wi-Fi channel (docs/steps/2026-09-22-trackpad-stutter.md).

"""

CHECKS_BULLET = """\
- `Tests/checks/` — the pure checks, a folder each, which says what it checks and what it compiles in
  its own `README.md`: `main.swift`, `run.sh` (compiles the app's files it names with swiftc into
  `.build/checks/<name>/` and runs; `--mutants` runs `mutants.py`, passing only when every mutant is
  caught), and `build.sh` where a check compiles a module (StreamProtocol's sources with `import
  StreamProtocol` stripped), or a `module.txt` naming the files `module.py` compiles as one module.
  `list.sh` prints every check with what it checks (no table is kept by hand); `run-all.sh
  [--mutants] [-v] [name…]` runs them and exits with the number that failed (a folder whose `run.sh`
  is not executable fails); `common.sh` is sourced by each `run.sh`; `mutant-checks.py` gives CI the
  checks with mutants, read from the folders; `repo-rules` fails a check folder without its
  README.md, a static mutants list in ci.yml, and a step entry written back into CLAUDE.md;
  `HISTORY.md` is the old README with its table, frozen. A change to a checked file updates its
  check (and a mutant's pattern) in the same commit.
"""


# ---------------------------------------------------------------------------------------------- git

def git(*args, check=True, cwd=None):
    r = subprocess.run(["git", *args], capture_output=True, text=True, cwd=cwd)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def root_dir():
    return git("rev-parse", "--show-toplevel").strip()


def show(rev, path):
    """A file's text at a commit, or None where it is not."""
    r = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8")


def merge3(ours, base, theirs):
    """Three-way merge of texts with git merge-file; returns (text, number of conflicts)."""
    with tempfile.TemporaryDirectory() as t:
        paths = []
        for name, text in (("ours", ours), ("base", base), ("theirs", theirs)):
            p = os.path.join(t, name)
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            paths.append(p)
        r = subprocess.run(["git", "merge-file", "-p", "-L", "this branch", "-L", "merge base",
                            "-L", "main", *paths], capture_output=True)
        if r.returncode < 0:
            raise SystemExit(f"git merge-file failed: {r.stderr.decode()}")
        return r.stdout.decode("utf-8"), r.returncode


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


# ------------------------------------------------------------------------------ CLAUDE.md's entries

def sections(lines):
    """[(start, end, heading)] for each '## ' section; the lines before the first are not listed."""
    starts = [i for i, l in enumerate(lines) if l.startswith("## ")]
    return [(s, e, lines[s]) for s, e in zip(starts, starts[1:] + [len(lines)])]


def bold_span(lines, i):
    joined = "\n".join(lines[i:i + 16])
    m = re.match(r"\*\*(.+?)\*\*", joined, re.S)
    return m.group(1) if m else lines[i]


def is_entry_start(lines, i):
    line = lines[i]
    if line.startswith("**"):
        return bool(DATE.search(bold_span(lines, i)))
    return line.startswith(tuple(SPECIAL))


def split_entries(body):
    """The old Current step's lines (after its heading) as (preamble, [entry lines])."""
    starts = [i for i in range(len(body)) if is_entry_start(body, i)]
    if not starts:
        return body, []
    return body[:starts[0]], [body[a:b] for a, b in zip(starts, starts[1:] + [len(body)])]


def entry_text(lines):
    """An entry as its step file holds it: its lines, trailing empty lines left out, one newline."""
    lines = list(lines)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


def title_of(text_or_lines):
    lines = text_or_lines.split("\n") if isinstance(text_or_lines, str) else text_or_lines
    first = lines[0]
    if first.startswith("**"):
        span = bold_span(lines, 0)
    elif first.startswith("## "):
        span = first[3:]
    else:
        span = first
    return " ".join(span.split())


def short_title(span):
    return re.split(r" \(|, 20\d\d-|\. ", span, 1)[0].strip(" .:,*")


def slug(text, words=None):
    s = text.lower().replace("’", "").replace("'", "")
    s = re.sub(r"[^a-z0-9.]+", "-", s)
    s = re.sub(r"(?<!\d)\.|\.(?!\d)", "-", s)        # dots only inside numbers (0.6.1)
    s = re.sub(r"-+", "-", s).strip("-")
    if words:
        s = "-".join(s.split("-")[:words])
    return s


def base_name(text):
    """<date>-<branch> for an entry: its title's first date and branch, else its short title."""
    lines = text.split("\n")
    for start, name in SPECIAL.items():
        if lines[0].startswith(start):
            m = DATE.search(text)
            return f"{m.group(0) if m else 'undated'}-{name}"
    span = title_of(lines)
    m = DATE.search(span) or DATE.search(text)
    b = re.search(r"branch\s+`([^`]+)`", span)
    return f"{m.group(0) if m else 'undated'}-{slug(b.group(1)) if b else slug(short_title(span), 8)}"


def names_for(texts, taken=()):
    """File names (without .md) for entries in order: <date>-<branch>, and where two would share one,
    each of them with its short title after a double dash; -2, -3 if still taken."""
    bases = [base_name(t) for t in texts]
    count = collections.Counter(bases)
    used, names = set(taken), []
    for text, b in zip(texts, bases):
        n = b if count[b] == 1 and b not in used else f"{b}--{slug(short_title(title_of(text)), 6)}"
        candidate, k = n, 2
        while candidate in used:
            candidate, k = f"{n}-{k}", k + 1
        used.add(candidate)
        names.append(candidate)
    return names


def checks_bullet_range(lines):
    """The Layout's bullet on Tests/checks/: [start, end) or None."""
    for i, line in enumerate(lines):
        if line.startswith(CHECKS_BULLET_START):
            j = i + 1
            while j < len(lines) and not lines[j].startswith(("- ", "## ")) and lines[j] != "":
                j += 1
            return i, j
    return None


def split_claude(text, pointer=POINTER, bullet=CHECKS_BULLET):
    """CLAUDE.md as it was -> (lean CLAUDE.md, [entry texts in order], old Layout bullet or None).
    The old Current step and the Milestone sections go; the pointer takes the Current step's place."""
    lines = text.split("\n")
    out, entries = [], []
    secs = sections(lines)
    out.extend(lines[:secs[0][0]] if secs else lines)
    placed = False
    for s, e, heading in secs:
        if heading == OLD_SECTION:
            pre, ents = split_entries(lines[s + 1:e])
            if any(l.strip() for l in pre):
                raise SystemExit("CLAUDE.md: text before the first Current step entry; not moved")
            entries += [entry_text(x) for x in ents]
            out.extend(pointer.rstrip("\n").split("\n") + [""])
            placed = True
        elif heading.startswith("## Milestone "):
            entries.append(entry_text(lines[s:e]))
        else:
            out.extend(lines[s:e])
    if not placed:
        return text, [], None
    old_bullet = None
    r = checks_bullet_range(out)
    if r:
        old_bullet = "\n".join(out[r[0]:r[1]]) + "\n"
        out[r[0]:r[1]] = bullet.rstrip("\n").split("\n")
    return "\n".join(out), entries, old_bullet


def section_text(text, heading):
    """A '## ' section's exact text, its heading included, from main's CLAUDE.md."""
    lines = text.split("\n")
    for s, e, h in sections(lines):
        if h == heading:
            return "\n".join(lines[s:e]) + "\n"
    return None


def bullet_text(text):
    lines = text.split("\n")
    r = checks_bullet_range(lines)
    return "\n".join(lines[r[0]:r[1]]) + "\n" if r else None


# ------------------------------------------------------------------------------ the checks' table

ROW = re.compile(r"^\| `([^`]+)` \|")


def table_rows(text):
    """{check: [(compiles, what it checks), ...]} from the old README's table, in table order."""
    rows = collections.OrderedDict()
    for line in (text or "").split("\n"):
        m = ROW.match(line)
        if not m:
            continue
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if len(cells) < 3:
            continue
        rows.setdefault(m.group(1), []).append((cells[1], cells[2]))
    return rows


def unique(items):
    seen, out = set(), []
    for x in items:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def check_readme(name, rows):
    """A check folder's README.md from its row(s), the counts left out."""
    what = unique(w for _, w in rows)
    compiles = unique(c for c, _ in rows)
    out = [f"# `{name}`", ""]
    if len(what) > 1 or len(compiles) > 1:
        out += [f"The old table in `Tests/checks/README.md` listed this check {len(rows)} times, merges "
                "having kept each branch's copy of its row; the different texts are here as they were, "
                "to be made one when the check next changes.", ""]
    for w in what:
        out += [f"**Checks:** {w}", ""]
    for c in compiles:
        out += [f"**Compiles:** {c}", ""]
    return "\n".join(out).rstrip("\n") + "\n"


def without_rows(text):
    return "\n".join(l for l in (text or "").split("\n") if not ROW.match(l))


# ---------------------------------------------------------------------- DEVELOPMENT.md and ci.yml

def dev_section(lines):
    for i, line in enumerate(lines):
        if line.strip() == DEV_HEADING:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("#"):
                j += 1
            return i, j
    return None


def dev_normalized(text, theirs):
    """The branch's DEVELOPMENT.md with main's "The pure checks" paragraph."""
    lines, t = text.split("\n"), theirs.split("\n")
    a, b = dev_section(lines), dev_section(t)
    if not a or not b:
        return text
    lines[a[0]:a[1]] = t[b[0]:b[1]]
    return "\n".join(lines)


def ci_normalized(text, theirs):
    """The branch's ci.yml with main's mutants matrix line in place of the static list."""
    new = next((l for l in theirs.split("\n") if MATRIX_NEW.match(l)), None)
    if new is None:
        return text
    return "\n".join(new if MATRIX_OLD.match(l) else l for l in text.split("\n"))


# ----------------------------------------------------------------------------------- the modes

def convert(root):
    """The conversion, once, on the working tree (tooling-speedup on main at 936d627)."""
    claude = read(os.path.join(root, CLAUDE))
    lean, entries, old_bullet = split_claude(claude)
    if not entries:
        raise SystemExit("CLAUDE.md has no Current step: already converted?")
    names = names_for(entries)
    steps = os.path.join(root, STEPS)
    os.makedirs(steps, exist_ok=True)
    for name, text in zip(names, entries):
        write(os.path.join(steps, name + ".md"), text)
    write(os.path.join(root, CLAUDE), lean)
    index = ["# Steps", "",
             "One file per piece of work (a branch, a release, a finding), written by the branch that does it:",
             "`<date>-<branch>.md`, the date its work began. CLAUDE.md, \"Steps\", says how to add, list and find",
             "them; `Scripts/steps.sh list` prints the newest first.", "",
             "The files below were CLAUDE.md's \"Current step\" (and its two milestones) until 2026-11-12, moved",
             "word for word by `Scripts/migrate-notes.py --convert` from main at 936d627. This list keeps their",
             "order there, newest first, so an entry's \"the entry below\", \"the next entry\" or \"the entry",
             "above\" means its neighbour here. It is frozen: a new step file is not added to it.", ""]
    for k, (name, text) in enumerate(zip(names, entries), 1):
        index.append(f"{k}. [{name}.md]({name}.md): {short_title(title_of(text))}")
    write(os.path.join(steps, "README.md"), "\n".join(index) + "\n")
    readme = read(os.path.join(root, CHECKS_README))
    rows = table_rows(readme)
    for name, rs in rows.items():
        folder = os.path.join(root, "Tests/checks", name)
        if os.path.isdir(folder):
            write(os.path.join(folder, "README.md"), check_readme(name, rs))
    history = ("# The checks' README as it was (frozen)\n\n"
               "Tests/checks/README.md until 2026-11-12 (main at 936d627), word for word below the line: its\n"
               "table, with the case and mutant counts that merges and hand edits kept, and the history of those\n"
               "counts. Nothing here is updated. Each check now says what it checks in its own README.md\n"
               "(`Tests/checks/list.sh` prints them all) and prints its own counts when it runs.\n\n"
               "CLAUDE.md's Layout listed the checks too, in the bullet that follows the old README.\n\n---\n\n"
               + readme + "\n---\n\nCLAUDE.md's Layout bullet on `Tests/checks/` until 2026-11-12:\n\n"
               + (old_bullet or ""))
    write(os.path.join(root, "Tests/checks/HISTORY.md"), history)
    print(f"{len(entries)} entries -> {STEPS}/ ({len(set(names))} files); {len(rows)} checks' README.md; "
          f"CLAUDE.md {len(claude.encode())} -> {len(lean.encode())} bytes")


def steps_entries(section, canonical):
    """A "Steps" section's lines as (kept, [entry lines]): an entry runs from a bold, dated title to the
    next one or to the first line of the section's own text (the pointer as main has it), which stays."""
    sm = difflib.SequenceMatcher(None, section, canonical, autojunk=False)
    own = set()
    for block in sm.get_matching_blocks():
        own.update(range(block.a, block.a + block.size))
    kept, entries, current = [], [], None
    for i, line in enumerate(section):
        if i not in own and is_entry_start(section, i):
            current = [line]
            entries.append(current)
        elif current is not None and i not in own:
            current.append(line)
        else:
            current = None
            if line == "" and kept and kept[-1] == "":
                continue                # the empty line an entry leaves behind
            kept.append(line)
    return kept, entries


def move_entries(root):
    """Moves entries written into CLAUDE.md after the move (in its "Steps" section, or a "Current step"
    or "Milestone" section put back) to step files of their own, word for word."""
    path = os.path.join(root, CLAUDE)
    lines = read(path).split("\n")
    canonical = (section_text(show("origin/main", CLAUDE) or "", NEW_SECTION) or POINTER).split("\n")
    secs = sections(lines)
    out = list(lines[:secs[0][0]] if secs else lines)
    entries = []
    for s, e, heading in secs:
        if heading == NEW_SECTION:
            kept, ents = steps_entries(lines[s:e], canonical)
            out.extend(kept)
            entries += [entry_text(x) for x in ents]
        elif heading == OLD_SECTION:
            pre, ents = split_entries(lines[s + 1:e])
            if any(l.strip() for l in pre):
                raise SystemExit("CLAUDE.md: a \"Current step\" section with text before its first entry; move it by hand")
            entries += [entry_text(x) for x in ents]
        elif heading.startswith("## Milestone "):
            entries.append(entry_text(lines[s:e]))
        else:
            out.extend(lines[s:e])
    if not entries:
        print("CLAUDE.md holds no step entry: nothing to move")
        return
    taken = {f[:-3] for f in os.listdir(os.path.join(root, STEPS))}
    for name, text in zip(names_for(entries, taken), entries):
        write(os.path.join(root, STEPS, name + ".md"), text)
        print(f"{STEPS}/{name}.md: moved out of CLAUDE.md word for word")
    write(path, "\n".join(out))
    print("CLAUDE.md: the entries taken out; check `git diff` and commit both")


def verify(root, rev):
    """docs/steps, the check folders' README.md and HISTORY.md against REV's files, word for word."""
    claude = show(rev, CLAUDE)
    if claude is None or OLD_SECTION not in claude.split("\n"):
        raise SystemExit(f"{rev}: no CLAUDE.md with a Current step")
    lines = claude.split("\n")
    s = lines.index(OLD_SECTION)
    e = next(k for k in range(s + 1, len(lines)) if lines[k].startswith("## "))
    _, ents = split_entries(lines[s + 1:e])
    exact = "".join("\n".join(x) + "\n" for x in ents)
    body = "\n".join(lines[s + 1:e]) + "\n"
    problems = []
    if "\n" + exact != body:
        problems.append("the entries do not add up to the Current step's text")
    lean, entries, _ = split_claude(claude)
    names = names_for(entries)
    for name, text in zip(names, entries):
        path = os.path.join(root, STEPS, name + ".md")
        if not os.path.exists(path):
            problems.append(f"missing {path}")
        elif read(path) != text:
            problems.append(f"{path} differs from its entry")
    moved = sum(len(t) for t in entries)
    if lean != read(os.path.join(root, CLAUDE)):
        print("note: CLAUDE.md differs from the lean form of REV's (later edits, or not converted)")
    files = sorted(f for f in os.listdir(os.path.join(root, STEPS)) if f.endswith(".md") and f != "README.md")
    print(f"{len(entries)} entries at {rev[:12]} ({len(ents)} of Current step, "
          f"{len(entries) - len(ents)} milestones), {moved} characters; {len(files)} step files now")
    readme = show(rev, CHECKS_README)
    rows = table_rows(readme)
    for name, rs in rows.items():
        path = os.path.join(root, "Tests/checks", name, "README.md")
        if not os.path.exists(path):
            problems.append(f"missing {path}")
            continue
        text = read(path)
        for compiles, what in rs:
            if f"**Checks:** {what}\n" not in text or f"**Compiles:** {compiles}\n" not in text:
                problems.append(f"{path} lacks a row's text")
    hist = os.path.join(root, "Tests/checks/HISTORY.md")
    if not os.path.exists(hist):
        problems.append("no Tests/checks/HISTORY.md")
    elif readme not in read(hist):
        print(f"note: Tests/checks/HISTORY.md is the README of the conversion's main, frozen, not {rev[:12]}'s")
    print(f"{len(rows)} checks' rows, {sum(len(r) for r in rows.values())} rows in all")
    for p in problems:
        print("PROBLEM:", p)
    print("verified: every entry and row is where it went, word for word" if not problems else "NOT VERIFIED")
    return not problems


def migrate(root, ours, theirs):
    base = git("merge-base", ours, theirs).strip()
    t_claude = show(theirs, CLAUDE)
    if t_claude is None or OLD_SECTION in t_claude.split("\n") or show(theirs, STEPS + "/README.md") is None:
        raise SystemExit(f"{theirs} has no docs/steps: merge a main that has them first")
    o_claude, b_claude = show(ours, CLAUDE), show(base, CLAUDE)
    resolved, conflicted, notes = [], [], []

    # CLAUDE.md -------------------------------------------------------------------------------
    pointer, bullet = section_text(t_claude, NEW_SECTION) or POINTER, bullet_text(t_claude) or CHECKS_BULLET
    o_lean, o_entries, _ = split_claude(o_claude, pointer, bullet)
    b_lean, b_entries, _ = split_claude(b_claude, pointer, bullet)
    if not o_entries:
        notes.append("CLAUDE.md: this branch's CLAUDE.md has no Current step; nothing to move")
    else:
        lean, n = merge3(o_lean, b_lean, t_claude)
        write(os.path.join(root, CLAUDE), lean)
        (conflicted if n else resolved).append(CLAUDE)
        # main's step files by their first line, the key an entry keeps when its words change
        t_files = [f for f in git("ls-tree", "--name-only", f"{theirs}:{STEPS}").split() if f.endswith(".md")]
        by_first = {}
        for f in t_files:
            text = show(theirs, f"{STEPS}/{f}") or ""
            by_first.setdefault(text.split("\n", 1)[0], f)
        # the working tree's step files: a second run finds what the first one moved
        wt_dir = os.path.join(root, STEPS)
        wt_steps = {f: read(os.path.join(wt_dir, f)) for f in os.listdir(wt_dir)
                    if f.endswith(".md") and f != "README.md"}
        wt_by_first = {}
        for f, x in sorted(wt_steps.items()):
            wt_by_first.setdefault(x.split("\n", 1)[0], f)
        b_set, b_by_first = set(b_entries), {x.split("\n", 1)[0]: x for x in b_entries}
        b_by_name = {}
        for x in b_entries:
            b_by_name.setdefault(base_name(x), x)
        new_texts = []
        for text in o_entries:
            if text in b_set:
                continue
            first = text.split("\n", 1)[0]
            old = match_old(text, b_entries, b_by_first, b_by_name)
            target = by_first.get(old.split("\n", 1)[0]) if old else None
            if old is not None and target is not None:
                path = f"{STEPS}/{target}"
                merged, n = merge3(text, old, show(theirs, path))
                write(os.path.join(root, path), merged)
                (conflicted if n else resolved).append(path)
                notes.append(f"{path}: this branch's changes to that entry, merged into it")
            elif first in wt_by_first:
                path = f"{STEPS}/{wt_by_first[first]}"
                if wt_steps[wt_by_first[first]] != text:
                    write(os.path.join(root, path), text)
                    notes.append(f"{path}: this branch's entry, written again as it is in the branch")
                else:
                    notes.append(f"{path}: this branch's entry, moved already")
                resolved.append(path)
            else:
                new_texts.append(text)
        taken = {f[:-3] for f in t_files} | {f[:-3] for f in os.listdir(os.path.join(root, STEPS))}
        for name, text in zip(names_for(new_texts, taken), new_texts):
            path = f"{STEPS}/{name}.md"
            write(os.path.join(root, path), text)
            resolved.append(path)
            notes.append(f"{path}: this branch's entry, moved out of CLAUDE.md word for word")
        gone = [x for x in b_entries if x not in set(o_entries)
                and x.split("\n", 1)[0] not in {y.split("\n", 1)[0] for y in o_entries}]
        for x in gone:
            notes.append(f"CLAUDE.md: this branch removed the entry \"{short_title(title_of(x))}\"; "
                         "its step file stays as main has it")

    # Tests/checks/README.md ------------------------------------------------------------------
    o_readme, b_readme, t_readme = show(ours, CHECKS_README), show(base, CHECKS_README), show(theirs, CHECKS_README)
    o_rows, b_rows = table_rows(o_readme), table_rows(b_readme)
    if o_rows and o_readme != b_readme:
        for name, rows in o_rows.items():
            if b_rows.get(name) == rows:
                continue
            ours_t = check_readme(name, rows)
            base_t = check_readme(name, b_rows[name]) if name in b_rows else ""
            if ours_t == base_t:
                continue                    # only its counts changed: a check prints its own now
            path = f"Tests/checks/{name}/README.md"
            if not os.path.isdir(os.path.join(root, "Tests/checks", name)):
                notes.append(f"{CHECKS_README}: a row for `{name}`, which has no folder here; not moved")
                continue
            t_text = show(theirs, path)
            if t_text is None:
                text, n = (ours_t, 0) if not base_t else merge3(ours_t, base_t, "")
            else:
                text, n = merge3(ours_t, base_t, t_text)
            write(os.path.join(root, path), text)
            (conflicted if n else resolved).append(path)
            notes.append(f"{path}: this branch's row for `{name}`, as the check's own README.md")
        extra = [l for l in difflib.unified_diff(without_rows(b_readme).split("\n"),
                                                 without_rows(o_readme).split("\n"), lineterm="", n=0)
                 if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
        write(os.path.join(root, CHECKS_README), t_readme)
        resolved.append(CHECKS_README)
        if extra:
            notes.append(f"{CHECKS_README} is main's; this branch's other changes to it were not carried "
                         "(add what still holds to the check's README.md):\n      "
                         + "\n      ".join(x[:150] for x in extra[:30]))

    # docs/DEVELOPMENT.md and ci.yml -----------------------------------------------------------
    for path, normalize in ((DEVELOPMENT, dev_normalized), (CI, ci_normalized)):
        o_text, b_text, t_text = show(ours, path), show(base, path), show(theirs, path)
        if None in (o_text, b_text, t_text) or o_text == b_text:
            continue
        text, n = merge3(normalize(o_text, t_text), normalize(b_text, t_text), t_text)
        write(os.path.join(root, path), text)
        (conflicted if n else resolved).append(path)

    # a check folder that came with this branch and has nothing to make its README.md from
    for name in sorted(os.listdir(os.path.join(root, "Tests/checks"))):
        folder = os.path.join(root, "Tests/checks", name)
        if os.path.isfile(os.path.join(folder, "run.sh")) and not os.path.exists(os.path.join(folder, "README.md")):
            notes.append(f"Tests/checks/{name} has no README.md and no row to make one from: write one "
                         "(Tests/checks/README.md, \"Adding a check\")")

    staged = [p for p in resolved if p not in conflicted]
    if staged:
        git("add", "--", *staged, cwd=root)
    print(f"Merge base {base[:12]}, this branch {git('rev-parse', '--short=12', ours).strip()}, "
          f"main {git('rev-parse', '--short=12', theirs).strip()}.")
    for note in notes:
        print("  " + note)
    if staged:
        print("Resolved and staged: " + ", ".join(staged))
    if conflicted:
        print("Left with conflict markers (resolve, then git add): " + ", ".join(conflicted))
    others = [p for p in git("diff", "--name-only", "--diff-filter=U", cwd=root).split()
              if p not in staged and p not in conflicted]
    if others:
        print("Still conflicted, not notes (as any merge): " + ", ".join(others))
    return not conflicted


def match_old(text, b_entries, b_by_first, b_by_name):
    """The base entry an entry is a later version of: the same first line, else the same date and
    branch reading alike (not a second entry of one branch on one day), else one that reads much alike;
    None for a new entry."""
    first = text.split("\n", 1)[0]
    old = b_by_first.get(first)
    if old is None and base_name(text) in b_by_name:
        x = b_by_name[base_name(text)]
        old = x if difflib.SequenceMatcher(None, text[:600], x[:600]).ratio() >= 0.5 else None
    if old is None:
        ratios = [(difflib.SequenceMatcher(None, text[:600], x[:600]).ratio(), x) for x in b_entries]
        best = max(ratios, default=(0, None), key=lambda r: r[0])
        old = best[1] if best[0] >= 0.75 else None
    return old


def absorb(root, theirs):
    """This branch has the new layout, the main it merges does not yet: main's entries and rows that
    are new since the merge base go to their own files, its other changes are merged three ways."""
    ours = "HEAD"
    base = git("merge-base", ours, theirs).strip()
    o_claude, b_claude, t_claude = show(ours, CLAUDE), show(base, CLAUDE), show(theirs, CLAUDE)
    if OLD_SECTION in o_claude.split("\n") or OLD_SECTION not in t_claude.split("\n"):
        raise SystemExit("--absorb is for a branch with docs/steps merging a main with a Current step")
    resolved, conflicted, notes = [], [], []
    pointer, bullet = section_text(o_claude, NEW_SECTION) or POINTER, bullet_text(o_claude) or CHECKS_BULLET
    b_lean, b_entries, _ = split_claude(b_claude, pointer, bullet)
    t_lean, t_entries, _ = split_claude(t_claude, pointer, bullet)
    lean, n = merge3(o_claude, b_lean, t_lean)
    write(os.path.join(root, CLAUDE), lean)
    (conflicted if n else resolved).append(CLAUDE)
    o_files = [f for f in git("ls-tree", "--name-only", f"{ours}:{STEPS}").split() if f.endswith(".md") and f != "README.md"]
    by_first = {}
    for f in o_files:
        by_first.setdefault((show(ours, f"{STEPS}/{f}") or "").split("\n", 1)[0], f)
    b_set, b_by_first, b_by_name = set(b_entries), {x.split("\n", 1)[0]: x for x in b_entries}, {}
    for x in b_entries:
        b_by_name.setdefault(base_name(x), x)
    new_texts = []
    for text in t_entries:
        if text in b_set:
            continue
        old = match_old(text, b_entries, b_by_first, b_by_name)
        target = by_first.get(old.split("\n", 1)[0]) if old else by_first.get(text.split("\n", 1)[0])
        if target is not None:
            path = f"{STEPS}/{target}"
            merged, n = merge3(show(ours, path), old or show(ours, path), text)
            write(os.path.join(root, path), merged)
            (conflicted if n else resolved).append(path)
            notes.append(f"{path}: main's changes to that entry, merged into it")
        else:
            new_texts.append(text)
    for name, text in zip(names_for(new_texts, {f[:-3] for f in o_files}), new_texts):
        path = f"{STEPS}/{name}.md"
        write(os.path.join(root, path), text)
        resolved.append(path)
        notes.append(f"{path}: main's new entry, out of its CLAUDE.md word for word")
    b_rows, t_rows = table_rows(show(base, CHECKS_README)), table_rows(show(theirs, CHECKS_README))
    for name, rows in t_rows.items():
        if b_rows.get(name) == rows:
            continue
        theirs_t = check_readme(name, rows)
        base_t = check_readme(name, b_rows[name]) if name in b_rows else ""
        if theirs_t == base_t:
            continue
        path = f"Tests/checks/{name}/README.md"
        mine = show(ours, path)
        text, n = (theirs_t, 0) if mine is None else merge3(mine, base_t, theirs_t)
        write(os.path.join(root, path), text)
        (conflicted if n else resolved).append(path)
        notes.append(f"{path}: main's row for `{name}`, as the check's own README.md")
    write(os.path.join(root, CHECKS_README), show(ours, CHECKS_README))
    resolved.append(CHECKS_README)
    for path, normalize in ((DEVELOPMENT, dev_normalized), (CI, ci_normalized)):
        o_text, b_text, t_text = show(ours, path), show(base, path), show(theirs, path)
        if None in (o_text, b_text, t_text) or b_text == t_text:
            continue
        text, n = merge3(o_text, normalize(b_text, o_text), normalize(t_text, o_text))
        write(os.path.join(root, path), text)
        (conflicted if n else resolved).append(path)
    staged = [p for p in resolved if p not in conflicted]
    if staged:
        git("add", "--", *staged, cwd=root)
    print(f"Merge base {base[:12]}, this branch {git('rev-parse', '--short=12', ours).strip()}, "
          f"main {git('rev-parse', '--short=12', theirs).strip()}.")
    for note in notes:
        print("  " + note)
    print("Resolved and staged: " + ", ".join(staged))
    if conflicted:
        print("Left with conflict markers (resolve, then git add): " + ", ".join(conflicted))
    others = [p for p in git("diff", "--name-only", "--diff-filter=U", cwd=root).split()
              if p not in staged and p not in conflicted]
    if others:
        print("Still conflicted, not notes (as any merge): " + ", ".join(others))
    return not conflicted


def main(argv):
    args = argv[1:]
    root = root_dir()
    if args[:1] == ["--convert"]:
        convert(root)
        return 0
    if args[:1] == ["--absorb"]:
        r = subprocess.run(["git", "rev-parse", "-q", "--verify", "MERGE_HEAD"], capture_output=True,
                           text=True, cwd=root)
        if r.returncode != 0:
            raise SystemExit("No merge in progress: run it right after `git merge origin/main` stops")
        return 0 if absorb(root, r.stdout.strip()) else 1
    if args[:1] == ["--move-entries"]:
        move_entries(root)
        return 0
    if args[:1] == ["--verify"]:
        return 0 if verify(root, args[1] if len(args) > 1 else "HEAD") else 1
    if args[:1] in (["-h"], ["--help"]):
        print(__doc__)
        return 0
    ours = theirs = None
    while args:
        if args[0] == "--ours" and len(args) > 1:
            ours, args = args[1], args[2:]
        elif args[0] == "--theirs" and len(args) > 1:
            theirs, args = args[1], args[2:]
        else:
            print(__doc__, file=sys.stderr)
            return 2
    if theirs is None:
        r = subprocess.run(["git", "rev-parse", "-q", "--verify", "MERGE_HEAD"], capture_output=True,
                           text=True, cwd=root)
        if r.returncode != 0:
            raise SystemExit("No merge in progress: run it right after `git merge origin/main` stops on "
                             "conflicts, or pass --ours HEAD^1 --theirs HEAD^2 after a merge you committed.")
        theirs = r.stdout.strip()
        ours = ours or "HEAD"
    else:
        dirty = git("status", "--porcelain", "--", CLAUDE, CHECKS_README, DEVELOPMENT, CI, STEPS,
                    "Tests/checks", cwd=root)
        if dirty.strip():
            raise SystemExit("Uncommitted changes to the files this writes; commit or stash them first:\n" + dirty)
    ours = ours or "HEAD"
    return 0 if migrate(root, ours, theirs) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
