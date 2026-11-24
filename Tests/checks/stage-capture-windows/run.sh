#!/bin/bash
# The production StageCaptureWindows policy: duplicate instances are selected by PID, including
# their auxiliary windows, with set comparison for catalog-driven capture restarts.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O Sources/SillHost/StageCaptureWindows.swift "$here/main.swift" -o "$out/check"
"$out/check"
