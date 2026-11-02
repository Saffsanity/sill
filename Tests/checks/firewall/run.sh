#!/bin/bash
# FirewallRule (Sources/SillHost/FirewallRule.swift) on its own: what the macOS firewall's read-only
# answers (`socketfilterfw`, macOS 27's and the older form) mean for Sill, the report's Mac above all
# (the bundle allowed, its executable blocked), and every word Sill says about it: Settings › General's
# line and its Terminal command, the menu's subtitle, the log's lines, the shell quoting. Its
# `package` access needs -package-name.
#   Tests/checks/firewall/run.sh             compile and run the check
#   Tests/checks/firewall/run.sh --mutants   one-line mutants of FirewallRule.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -package-name sill Sources/SillHost/FirewallRule.swift "$here/main.swift" -o "$out/check"
"$out/check"
