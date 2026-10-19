#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O Sources/StreamProtocol/*.swift visionOSClient/VisionWorkspace.swift visionOSClient/VisionSceneSet.swift "$here/main.swift" -o "$out/check"
"$out/check"
