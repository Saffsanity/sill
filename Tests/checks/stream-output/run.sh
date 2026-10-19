#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc "$ROOT/Sources/SillHost/StreamOutputGate.swift" "$ROOT/Tests/checks/stream-output/main.swift" -o "$OUT/check"
"$OUT/check"
