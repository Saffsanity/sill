#!/bin/bash
# usage: build.sh ROOT OUT [WindowRestore.swift override]
# Compiles Sources/SillHost/WindowRestore.swift (Foundation and CoreGraphics only) with this check's
# main.swift. Nothing else of the host: no Accessibility, no window, no permission.
ROOT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$ROOT/Sources/SillHost/WindowRestore.swift}" "$T/WindowRestore.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
