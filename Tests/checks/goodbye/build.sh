#!/bin/bash
# usage: build.sh WT OUT [OVERRIDE]
# Compiles iOSClient/GoodbyePolicy.swift (the device's reading of a goodbye) and
# Sources/SillHost/HostGoodbye.swift (the host's choice of one) with StreamProtocol's sources as one
# module (their `import StreamProtocol` stripped; `-package-name sill` for HostGoodbye's package
# access). OVERRIDE, a mutant: a file named as one of those sources (GoodbyePolicy.swift,
# HostGoodbye.swift or one of StreamProtocol's, Remote.swift say), which takes its place.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
sed '/^import StreamProtocol$/d' "$WT/iOSClient/GoodbyePolicy.swift" > "$T/GoodbyePolicy.swift"
sed '/^import StreamProtocol$/d' "$WT/Sources/SillHost/HostGoodbye.swift" > "$T/HostGoodbye.swift"
if [ -n "${3:-}" ]; then sed '/^import StreamProtocol$/d' "$3" > "$T/$(basename "$3")"; fi
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O -package-name sill "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
