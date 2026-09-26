#!/bin/bash
# usage: build.sh WT OUT [DeviceGate.swift override]
# Compiles DeviceGate.swift with StreamProtocol's sources as one module (its `import StreamProtocol`
# stripped), with -package-name sill for its `package` access.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
sed '/^import StreamProtocol$/d' "${3:-$WT/Sources/SillHost/DeviceGate.swift}" > "$T/DeviceGate.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O -package-name sill "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
