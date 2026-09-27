#!/bin/bash
# usage: build.sh WT OUT [PointerControl.swift override] [StreamProtocol folder override]
# Compiles PointerControl.swift with StreamProtocol's sources as one module (its `import
# StreamProtocol` stripped).
WT=$1; OUT=$2; T=$(mktemp -d)
cp "${4:-$WT/Sources/StreamProtocol}"/*.swift "$T"/
sed '/^import StreamProtocol$/d' "${3:-$WT/Sources/SillHost/PointerControl.swift}" > "$T/PointerControl.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
