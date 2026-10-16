#!/bin/bash
# The production installed-app scanner against temporary application bundles, never real apps.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc "$root/Sources/SillHost/InstalledApps.swift" "$here/main.swift" -o "$out/check"
"$out/check"
