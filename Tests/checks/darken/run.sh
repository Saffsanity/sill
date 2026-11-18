#!/bin/bash
# DarkenPolicy (Sources/SillHost/DarkenPolicy.swift; docs/privacy-mode-plan.md, part 2): this Mac's screens dark while a
# device uses it (#133, #323). Which sessions darken, the dark and its raise before the wake, the wait and the hold for
# the lock, under the lock screen and its fallback, a key or a click on the dark Mac, taken back, the switches, a quit,
# the watchdog's decisions, the screens, the TEST ONLY hooks, every word, and a model of the glue running it beside the
# lock's rule (PrivacyPolicy) through 20,000 random sessions against its invariants. Compiled with StreamProtocol's
# sources, HostConfig.swift, PrivacyPolicy.swift and LockPolicy.swift as one module (module.txt; ../module.py drops
# their `import StreamProtocol`).
#   Tests/checks/darken/run.sh             compile and run the check
#   Tests/checks/darken/run.sh --mutants   one-line mutants of DarkenPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
