#!/bin/bash
# usage: build.sh WT OUT [SillDisplayRole.swift override]
# Compiles Sources/SillHost/SillDisplayRole.swift (the roles' identities; `import StreamProtocol` stripped) with
# StreamProtocol's DesktopDisplays.swift and Sources/SillHost/DisplayMakeGuard.swift as one module, and this check's
# main.swift, which reads the wiring as text in the repository it is given.
WT=$1; OUT=$2; T=$(mktemp -d)
sed '/^import StreamProtocol$/d' "${3:-$WT/Sources/SillHost/SillDisplayRole.swift}" > "$T/SillDisplayRole.swift"
cp "$WT/Sources/StreamProtocol/DesktopDisplays.swift" "$T/DesktopDisplays.swift"
cp "$WT/Sources/SillHost/DisplayMakeGuard.swift" "$T/DisplayMakeGuard.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error|warning"
rm -rf "$T"
