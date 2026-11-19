#!/bin/bash
# TEST ONLY: the device's camera stream end to end on the Mac (docs/camera-plan.md §8, §13.2): the app's own
# CameraEncoder, CameraPattern, CameraStream and CameraPolicy compiled for macOS with encoder-main.swift, on
# VideoToolbox's SOFTWARE HEVC encoder (CameraEncoder refuses a hardware session) and software decoder. No camera, no
# network, never the Mac's hardware encoder. Not one of Tests/checks (CI's runners may lack VideoToolbox's software
# HEVC encoder); run it beside the loopback gates, under the heavy lock. Its header says what it judges.
#   Scripts/camera-check/encoder.sh [OUT.bin]   OUT.bin: epoch 0's frames as a SILLCAM1 fixture for sillclient.py
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/.build/camera-check"
mkdir -p "$out/src"
rm -f "$out/src/"*.swift
for f in "$root"/Sources/StreamProtocol/*.swift "$root/iOSClient/CameraPolicy.swift" "$root/iOSClient/CameraStream.swift" \
         "$root/iOSClient/CameraEncoder.swift" "$root/iOSClient/CameraPattern.swift"; do
    grep -v '^import StreamProtocol$' "$f" > "$out/src/$(basename "$f")"
done
cp "$root/Scripts/camera-check/encoder-main.swift" "$out/src/main.swift"
swiftc -O "$out/src/"*.swift -o "$out/encoder"
"$out/encoder" "$@"
