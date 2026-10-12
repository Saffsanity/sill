#!/bin/bash
# build.sh WORKTREE OUT [File.swift=replacement…]: the Mac client's MacKeyMap with the host's
# KeyStrokes and StreamProtocol's sources as one module (`import StreamProtocol` stripped).
WT=$1; OUT=$2; shift 2; T=$(mktemp -d)
FILES=(Sources/MacClient/MacKeyMap.swift Sources/SillHost/KeyStrokes.swift)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
for rel in "${FILES[@]}"; do
    f="$(basename "$rel")"; src="$WT/$rel"
    for o in "$@"; do [ "${o%%=*}" = "$f" ] && src="${o#*=}"; done
    sed '/^import StreamProtocol$/d' "$src" > "$T/$f"
done
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O -package-name sill "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
