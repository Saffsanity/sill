#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
out=.build/checks/vision-window-size
mkdir -p "$out"
swiftc visionOSClient/VisionWindowSizePolicy.swift Tests/checks/vision-window-size/main.swift -o "$out/check"
"$out/check"
