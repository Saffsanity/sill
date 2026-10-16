#!/bin/bash
# InstalledApps (Sources/SillHost/InstalledApps.swift), where the Apps list finds the Mac's apps: a
# fake applications folder in a temporary directory, with an app in a suite's folder (#76), one too
# deep, a helper inside a bundle, a hidden folder, a symbolic link and two bundles with one ID.
#   Tests/checks/installed-apps/run.sh   compile and run
# It has no mutants script.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then echo "installed-apps: no mutants script"; exit 0; fi
swiftc -O Sources/SillHost/InstalledApps.swift "$here/main.swift" -o "$out/check"
"$out/check"
