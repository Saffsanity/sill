#!/bin/bash
# usage: build.sh ROOT OUT [DisplayWakePolicy.swift override]
# Compiles Sources/SillHost/DisplayWakePolicy.swift (Foundation only) with this check's main.swift.
ROOT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$ROOT/Sources/SillHost/DisplayWakePolicy.swift}" "$T/DisplayWakePolicy.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
