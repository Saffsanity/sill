#!/bin/bash
# usage: build.sh reader|mirror OUT [BUDGET]
# Compiles Scripts/menu-check/<harness>.swift with Sources/StreamProtocol and the host's menu files
# as one module (-package-name sill): MenuReader, MenuFormat and MenuPolicy, and for the mirror
# MenuMirror, each without its `import StreamProtocol` and `import Network` (the mirror's
# NWConnection is the harness's FakeConnection). BUDGET replaces MenuReader.readBudget.
set -e
HARNESS=$1; OUT=$2; BUDGET=${3:-}
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cp "$ROOT"/Sources/StreamProtocol/*.swift "$T"/
files=(MenuReader MenuFormat MenuPolicy)
[ "$HARNESS" = mirror ] && files+=(MenuMirror)
for f in "${files[@]}"; do
  sed -e '/^import StreamProtocol$/d' -e '/^import Network$/d' -e 's/NWConnection/FakeConnection/g' \
      "$ROOT/Sources/SillHost/$f.swift" > "$T/$f.swift"
done
if [ -n "$BUDGET" ]; then
  sed -i '' "s/static let readBudget = 1.5$/static let readBudget = $BUDGET/" "$T/MenuReader.swift"
  grep -q "static let readBudget = $BUDGET$" "$T/MenuReader.swift" || { echo "build.sh: readBudget not found" >&2; exit 1; }
fi
cp "$HERE/$HARNESS.swift" "$T/main.swift"
rm -f "$OUT"
swiftc -O -package-name sill "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" || true
test -x "$OUT"
