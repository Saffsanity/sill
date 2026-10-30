#!/bin/bash
# ConsoleSession (Sources/SillHost/ConsoleSession.swift, issue #211): whether this Mac's user session
# has the console under fast user switching, as the host reads it and tells the devices (kind 16's
# `sessionOnConsole`), its log lines, and the TEST ONLY SILL_TEST_CONSOLE_FILE.
#   Tests/checks/console-session/run.sh             compile and run the check
#   Tests/checks/console-session/run.sh --mutants   one-line mutants of ConsoleSession.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/ConsoleSession.swift "$here/main.swift" -o "$out/check"
"$out/check"
