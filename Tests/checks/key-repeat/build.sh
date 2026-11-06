#!/bin/bash
# usage: build.sh WT OUT [FILE=OVERRIDE ...]
# Compiles the check with StreamProtocol's sources as one module, -package-name sill for the host
# files' `package` access: Sources/SillHost/KeyRepeat.swift and Sources/SillHost/KeyStrokes.swift (the
# keys whose repeat it is), each with its `import StreamProtocol` stripped. FILE=OVERRIDE (a basename,
# then a path) compiles OVERRIDE in FILE's place (the mutants').
WT=$1; OUT=$2; shift 2; T=$(mktemp -d)
FILES=(Sources/SillHost/KeyRepeat.swift Sources/SillHost/KeyStrokes.swift)
cp "$WT"/Sources/StreamProtocol/*.swift "$T"/
for rel in "${FILES[@]}"; do
    f="$(basename "$rel")"; src="$WT/$rel"
    for o in "$@"; do [ "${o%%=*}" = "$f" ] && src="${o#*=}"; done
    sed '/^import StreamProtocol$/d' "$src" > "$T/$f"
done
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O -package-name sill "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
