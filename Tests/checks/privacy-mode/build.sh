#!/bin/bash
# usage: build.sh WT OUT [PrivacyModePolicy.swift override]
# Compiles the pure privacy-mode rule (Sources/SillMenuBar/PrivacyModePolicy.swift, CoreGraphics
# and Foundation only) with this check's main.swift.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$WT/Sources/SillMenuBar/PrivacyModePolicy.swift}" "$T/PrivacyModePolicy.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
