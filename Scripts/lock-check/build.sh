#!/bin/bash
# TEST ONLY (docs/locked-mac-plan.md): builds Scripts/lock-check/frames.swift with Sources/StreamProtocol (its
# ParameterSets) as one module into .build/lock-check/frames. It decodes on VideoToolbox's software decoder
# only, never the Mac's media engine.
#   Scripts/lock-check/build.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/lock-check"
mkdir -p "$out"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
for f in "$root"/Sources/StreamProtocol/*.swift; do sed '/^import StreamProtocol$/d' "$f" > "$t/$(basename "$f")"; done
cp "$here/frames.swift" "$t/main.swift"
swiftc -O "$t"/*.swift -o "$out/frames"
echo "built $out/frames"
