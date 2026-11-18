#!/bin/bash
# PrivacyPolicy (Sources/SillHost/PrivacyPolicy.swift; docs/privacy-mode-plan.md, part 1): Lock this Mac when the last
# device leaves (#283, #275). Which departures count, the wait and what ends it, its end (the lock, or why not: locked
# already, another user on the screen, no reading yet, no display to type the password at), the lock's confirmation and
# the display sleep, a quit and a crash, the TEST ONLY hooks, every word, and a model of the server and the glue run
# through 20,000 random sessions against the rule's invariants. Compiled with StreamProtocol's sources as one module
# (module.txt; ../module.py drops their `import StreamProtocol`), for DesktopDisplays.role.
#   Tests/checks/privacy/run.sh             compile and run the check
#   Tests/checks/privacy/run.sh --mutants   one-line mutants of PrivacyPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
