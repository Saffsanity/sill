#!/bin/bash
# The rules that keep branches out of each other's way: each check folder says what it checks in its
# own README.md, no table of the checks is kept by hand, CI's mutants matrix is read from the folders
# (Tests/checks/mutant-checks.py) and checked before it runs, and a branch's notes go in its own
# docs/steps file, never back into CLAUDE.md. Python only; reads files, writes nothing.
#   Tests/checks/repo-rules/run.sh             check the rules
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
python3 "$here/rules.py" "$root"
