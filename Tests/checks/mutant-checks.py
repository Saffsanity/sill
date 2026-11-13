#!/usr/bin/env python3
"""The checks that have mutants, for CI's mutants matrix (.github/workflows/ci.yml): every folder
here with a run.sh and a mutants.py, sorted, as one JSON array. The matrix is read from the folders
at run time, so adding a check, or mutants to one, edits no shared line.

    python3 Tests/checks/mutant-checks.py                       print the list
    python3 Tests/checks/mutant-checks.py --verify JSON         exit 1 unless JSON is that list
    python3 Tests/checks/mutant-checks.py --github-output FILE  list, verify, then append
                                                                `checks=<list>` to FILE (CI's step)

The verification is the guard that keeps a check's mutants from dropping out of CI unseen. It reads
the JSON as the workflow's fromJSON does and compares it with the folders that have a mutants.py as
git's index lists them (`git ls-files`, not the walk of the folder that made the list; the walk
when there is no git): it fails on a list that does not parse, is empty, names a check twice, names
one without a mutants.py or an executable run.sh, or leaves one out, and says which.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def listing():
    """The list: a walk of this folder."""
    names = []
    for name in sorted(os.listdir(HERE)):
        folder = os.path.join(HERE, name)
        if os.path.isfile(os.path.join(folder, "run.sh")) and os.path.isfile(os.path.join(folder, "mutants.py")):
            names.append(name)
    return names


def expected():
    """What the list must be, found another way: git's index (the walk if git can't answer)."""
    r = subprocess.run(["git", "-C", ROOT, "ls-files", "-z", "--", "Tests/checks/*/mutants.py"],
                       capture_output=True)
    if r.returncode == 0 and r.stdout:
        paths = [p.decode() for p in r.stdout.split(b"\0") if p]
        return sorted({p.split("/")[2] for p in paths if p.count("/") == 3}), "git ls-files"
    import glob
    return sorted(os.path.basename(os.path.dirname(p))
                  for p in glob.glob(os.path.join(HERE, "*", "mutants.py"))), "the folders (no git)"


def verify(text):
    """Problems with a list as the matrix would read it; empty when it is exactly the checks with mutants."""
    try:
        got = json.loads(text)
    except ValueError as e:
        return [f"the list is not JSON ({e}): {text[:80]!r}"], 0
    if not isinstance(got, list) or not all(isinstance(x, str) for x in got):
        return [f"the list is not an array of names: {text[:80]!r}"], 0
    want, source = expected()
    problems = []
    if not got:
        problems.append("the list is empty")
    if not want:
        problems.append(f"no Tests/checks/*/mutants.py in {source}")
    dupes = sorted({x for x in got if got.count(x) > 1})
    if dupes:
        problems.append("named twice: " + ", ".join(dupes))
    missing = [x for x in want if x not in got]
    if missing:
        problems.append(f"left out ({len(missing)} of the {len(want)} folders with a mutants.py in "
                        f"{source}): " + ", ".join(missing))
    unknown = [x for x in got if x not in want]
    if unknown:
        problems.append("not a folder with a mutants.py in " + source + ": " + ", ".join(unknown))
    for x in got:
        run = os.path.join(HERE, x, "run.sh")
        if x in want and not os.access(run, os.X_OK):
            problems.append(f"Tests/checks/{x}/run.sh is missing or not executable")
    if len(got) < len(want) and not missing:
        problems.append(f"{len(got)} names for {len(want)} folders")
    return problems, len(want)


def main(argv):
    args = argv[1:]
    if not args:
        print(json.dumps(listing(), separators=(",", ":")))
        return 0
    if args[0] == "--verify" and len(args) == 2:
        problems, n = verify(args[1])
        for p in problems:
            print(f"mutant-checks: {p}", file=sys.stderr)
        if problems:
            print("mutant-checks: FAILED: a check's mutants would drop out of CI", file=sys.stderr)
            return 1
        print(f"mutant-checks: the list names all {n} checks with mutants, each once")
        return 0
    if args[0] == "--github-output" and len(args) == 2:
        text = json.dumps(listing(), separators=(",", ":"))
        problems, n = verify(text)
        for p in problems:
            print(f"::error::mutant-checks: {p}")
        if problems:
            return 1
        with open(args[1], "a", encoding="utf-8") as f:
            f.write(f"checks={text}\n")
        print(f"mutant-checks: {n} checks with mutants, one job each: {', '.join(json.loads(text))}")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
