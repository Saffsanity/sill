#!/bin/bash
# InstalledApps (Sources/SillHost/InstalledApps.swift), where the Apps list finds the Mac's apps: a
# fake applications folder in a temporary directory, with apps in a suite's folder (#76) and two
# folders down (#135), a helper inside a bundle, a package of another kind, a framework, dot names,
# symbolic links (a folder's, not followed; a folder given that is a link, followed) and bundles
# that share an ID (at different depths, and twice at one depth).
#   Tests/checks/installed-apps/run.sh             compile and run
#   Tests/checks/installed-apps/run.sh --mutants   one-line mutants of InstalledApps.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/SillHost/InstalledApps.swift "$here/main.swift" -o "$out/check"
"$out/check"
