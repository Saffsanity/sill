#!/bin/bash
# TEST ONLY: builds the microphone's gate tools into OUT (default .build/mic-check): `tone` (the tone's packets
# for sillclient.py --mic, written to OUT/tone.packets, 120 s of it) and `analyze` (where each click was heard
# in a test host's file sink). AudioToolbox and Foundation only; nothing of an audio device. The gates
# (live.py) also need a release SillHost (swift build -c release).
#   Scripts/mic-check/build.sh [OUT]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../.." && pwd)"
out="${1:-$root/.build/mic-check}"; mkdir -p "$out"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/tone" "$t/analyze"
cp "$here/tone.swift" "$t/tone/main.swift"; cp "$here/analyze.swift" "$t/analyze/main.swift"
swiftc -O "$root/Sources/SillAudio/AudioEncoder.swift" "$root/Sources/SillAudio/AudioPacketizer.swift" \
    "$root/Sources/SillHost/TestTone.swift" "$t/tone/main.swift" -o "$out/tone"
swiftc -O "$root/Sources/SillHost/TestTone.swift" "$t/analyze/main.swift" -o "$out/analyze"
"$out/tone" "$out/tone.packets" 120
