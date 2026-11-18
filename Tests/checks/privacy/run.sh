#!/bin/bash
# PrivacyPolicy (Sources/SillHost/PrivacyPolicy.swift; docs/privacy-mode-plan.md, part 1): Lock this Mac when the last
# device leaves (#283, #275). Who acts (Sill.app itself alone), the gate's reading, which departures count, the wait and
# what ends it, its end (the lock, or why not: locked already, another user on the screen, no reading yet, no display
# to type the password at), the lock's confirmation and the display sleep, Turn off its display too and Only after a
# device away from home, a quit and a crash, the TEST ONLY hooks, every word, and the rule driven as the coordinator's
# glue drives it through 20,000 random sessions against its invariants. Compiled with StreamProtocol's sources and
# LockPolicy.swift as one module (module.txt; ../module.py drops their `import StreamProtocol`), for
# DesktopDisplays.role and LockPolicy.Reading.
#   Tests/checks/privacy/run.sh             compile and run the check
#   Tests/checks/privacy/run.sh --mutants   one-line mutants of PrivacyPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
