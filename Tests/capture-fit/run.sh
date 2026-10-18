#!/bin/bash
# Opt-in macOS integration test: captures only a blank window it creates itself.
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="$PWD/.build/capture-fit"
mkdir -p "$out"
source_file="$PWD/Sources/SillHost/WindowCapture.swift"
if [ "${1:-}" = "--rev" ]; then
    git show "$2:Sources/SillHost/WindowCapture.swift" > "$out/WindowCapture.swift"
    source_file="$out/WindowCapture.swift"
fi
xcrun swiftc -swift-version 5 -module-cache-path "$out/modules" \
    "$source_file" Tests/capture-fit/main.swift -o "$out/CaptureFit"
exec "$out/CaptureFit"
