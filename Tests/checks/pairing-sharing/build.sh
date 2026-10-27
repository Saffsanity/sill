#!/bin/bash
# usage: build.sh WT OUT [PairingWindowSharing.swift override]
# Compiles the pairing window's rule for screen sharing (Sources/SillMenuBar/PairingWindowSharing.swift:
# Foundation, and AppKit for the window's NSWindow.SharingType) with this check's main.swift. No
# window, no screen.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$WT/Sources/SillMenuBar/PairingWindowSharing.swift}" "$T/PairingWindowSharing.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
