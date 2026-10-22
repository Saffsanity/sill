#!/bin/bash
# usage: build.sh WT OUT [DiscoveryPolicy override] [RemoteDialPolicy override] [SavedMacs override]
# Compiles the device's pure parts with StreamProtocol's sources as one module.
SELF="$(cd "$(dirname "$0")" && pwd)"
WT="$1"; OUT="$2"; T=$(mktemp -d)
cp "$WT/Sources/StreamProtocol/"*.swift "$T/"
for f in "${3:-$WT/iOSClient/DiscoveryPolicy.swift}" "${4:-$WT/iOSClient/RemoteDialPolicy.swift}" "${5:-$WT/iOSClient/SavedMacs.swift}"; do
  sed '/^import StreamProtocol$/d' "$f" > "$T/$(basename "$f")"
done
cp "$SELF/main.swift" "$T/main.swift"
cp "$SELF/home.swift" "$T/home.swift"
swiftc -O "$T/"*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
