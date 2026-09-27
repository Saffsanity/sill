#!/bin/bash
# usage: build.sh WT OUT [MacMenuState.swift override]
# Compiles iOSClient/MacMenuState.swift with StreamProtocol's sources as one module (its
# `import StreamProtocol` stripped), as the goodbye check does.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
sed '/^import StreamProtocol$/d' "${3:-$WT/iOSClient/MacMenuState.swift}" > "$T/MacMenuState.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
