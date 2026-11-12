#!/bin/bash
# usage: build.sh WT OUT [SRC]
# Compiles UpdatePolicy, UpdateInstallPolicy, UpdateManifest and UpdateArchive (from SRC, by default
# WT/Sources/SillMenuBar; mutants.py passes a copy with one change) with StreamProtocol's sources as one
# module (each `import StreamProtocol` stripped), and this check's main.swift.
WT=$1; OUT=$2; SRC=${3:-$WT/Sources/SillMenuBar}; T=$(mktemp -d)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
for f in UpdatePolicy UpdateInstallPolicy UpdateManifest UpdateArchive; do
    sed '/^import StreamProtocol$/d' "$SRC/$f.swift" > "$T/$f.swift"
done
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
