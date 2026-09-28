"""Builds and runs a check that compiles the app's files as one module, their `import StreamProtocol`
lines dropped, with the check's own main.swift: the files its `module.txt` lists (paths from the
repository's root, globs allowed; a line `flags: …` adds swiftc flags). Home pairing's checks
(door-policy, cable-link, ask-limits, home-records, home-device, home-txt, home-model) came with this
from the branch's own scratch folder (docs/home-pairing-plan.md, Results), where it was `lib.py`.

    python3 Tests/checks/module.py CHECK ROOT OUT     build CHECK against ROOT into OUT and run it;
                                                      the exit status is the check's (2: no build)

From a check's mutants.py: `module.mutate(CHECK, MUTANTS, ROOT)`, where each mutant is (name, path
from ROOT, old, new), or with `old` and `new` lists of the same length for several replacements at
once. Each must be found exactly once, compile, and make the check fail; the last line printed counts
them ("N of M mutants caught"), which is what run_mutants in common.sh reads. The repository is never
changed: sources and mutants are copied to a temporary directory."""
import glob, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def module(check):
    """The files and swiftc flags of `check`, from its module.txt."""
    files, flags = [], []
    for line in open(os.path.join(HERE, check, "module.txt")):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("flags:"):
            flags += line[len("flags:"):].split()
        else:
            files.append(line)
    return files, flags


def sources(check, root):
    patterns, _ = module(check)
    out = []
    for pattern in patterns:
        found = sorted(glob.glob(os.path.join(root, pattern)))
        if not found:
            raise SystemExit(f"{check}: module.txt names {pattern}, which is not in {root}")
        out += found
    return out


def build(check, root, exe, overrides=None):
    """Compiles `check` against `root` into `exe`; `overrides` maps a path relative to root to new
    text. Returns (ok, compiler output)."""
    overrides = overrides or {}
    _, flags = module(check)
    with tempfile.TemporaryDirectory() as t:
        for f in sources(check, root):
            rel = os.path.relpath(f, root)
            text = overrides.get(rel, open(f).read())
            lines = [l for l in text.split("\n") if l.strip() != "import StreamProtocol"]
            open(os.path.join(t, os.path.basename(f)), "w").write("\n".join(lines))
        open(os.path.join(t, "main.swift"), "w").write(open(os.path.join(HERE, check, "main.swift")).read())
        r = subprocess.run(["swiftc", "-O", *flags, *sorted(glob.glob(os.path.join(t, "*.swift"))), "-o", exe],
                           capture_output=True, text=True)
        return r.returncode == 0, r.stdout + r.stderr


def run(exe):
    r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout + r.stderr


def mutate(check, mutants, root):
    """Each mutant (name, path, old, new) must be found once, compile and make the check fail."""
    caught = 0
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "m")
        for name, rel, old, new in mutants:
            src = open(os.path.join(root, rel)).read()
            pairs = list(zip(old, new)) if isinstance(old, list) else [(old, new)]
            counts = [src.count(o) for o, _ in pairs]
            if any(n != 1 for n in counts):
                print(f"NOT APPLIED {name}: pattern found {counts} times", flush=True)
                continue
            for o, n in pairs:
                src = src.replace(o, n)
            ok, log = build(check, root, exe, {rel: src})
            if not ok:
                print(f"DOES NOT COMPILE {name}: {log[:400]}", flush=True)
                continue
            code, out = run(exe)
            failed = [l[5:] for l in out.splitlines() if l.startswith("FAIL")]
            hit = code != 0
            caught += hit
            crash = f" (crashed: exit {code})" if code < 0 else ""
            print(f"{'caught' if hit else 'MISSED'} {name}: {len(failed)} failing{crash}"
                  f"{', e.g. ' + failed[0][:110] if failed else ''}", flush=True)
    print(f"{caught} of {len(mutants)} mutants caught")
    return caught == len(mutants)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: module.py CHECK ROOT OUT")
    check, root, exe = sys.argv[1:]
    ok, log = build(check, root, exe)
    if not ok:
        print(log)
        sys.exit(2)
    code, out = run(exe)
    print(out, end="")
    sys.exit(code)
