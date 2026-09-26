#!/bin/bash
# usage: build.sh WT OUT [GoodbyePolicy.swift override]
# Compiles GoodbyePolicy.swift with StreamProtocol's sources as one module (its `import StreamProtocol`
# stripped).
WT=$1; OUT=$2; T=$(mktemp -d)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
sed '/^import StreamProtocol$/d' "${3:-$WT/iOSClient/GoodbyePolicy.swift}" > "$T/GoodbyePolicy.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
