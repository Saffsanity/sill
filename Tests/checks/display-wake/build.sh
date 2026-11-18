#!/bin/bash
# usage: build.sh WT OUT [DisplayWake.swift override]
# Compiles DisplayWake.swift (its `import StreamProtocol` stripped) with the three StreamProtocol files
# its rule names, as they are: StreamMessage.swift (the message kinds), Input.swift (InputEvent) and
# Pen.swift (an Apple Pencil's PenInput, kind 45).
SELF="$(cd "$(dirname "$0")" && pwd)"
WT="$1"; OUT="$2"; T=$(mktemp -d)
cp "$WT/Sources/StreamProtocol/StreamMessage.swift" "$WT/Sources/StreamProtocol/Input.swift" "$WT/Sources/StreamProtocol/Pen.swift" "$T/"
sed '/^import StreamProtocol$/d' "${3:-$WT/Sources/SillHost/DisplayWake.swift}" > "$T/DisplayWake.swift"
cp "$SELF/main.swift" "$T/main.swift"
swiftc -O "$T/"*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
