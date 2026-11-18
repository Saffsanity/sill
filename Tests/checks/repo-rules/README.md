# `repo-rules`

**Checks:** the rules that keep branches out of each other's way (2026-11-12, branch `tooling-speedup`): every check folder has a `README.md` with its name as the heading and a **Checks:** and a **Compiles:** paragraph; `Tests/checks/README.md` keeps no table of the checks; `.github/workflows/ci.yml` lists no checks by hand and takes its mutants matrix from `Tests/checks/mutant-checks.py`, whose listing is every folder with a `mutants.py` and whose guard passes on it (a `mutants.py` not yet in git only noted); CLAUDE.md has its "Steps" section and no step entry (no bold, dated title, no "Current step" or "Milestone" section); every file in `docs/steps` is named `<date>-<branch>.md` and none is empty

**Compiles:** nothing: `rules.py` (Python), which imports `Tests/checks/mutant-checks.py` and reads the files it names
