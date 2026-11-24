#!/bin/bash
# usage: build.sh ROOT OUT [FramePacing.swift override]
# Compiles Sources/SillHost/FramePacing.swift (Foundation only) with the check's main.swift.
ROOT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$ROOT/Sources/SillHost/FramePacing.swift}" "$T/FramePacing.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
