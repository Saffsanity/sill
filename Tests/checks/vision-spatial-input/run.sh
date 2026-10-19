#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O iOSClient/PointerPresence.swift Sources/StreamProtocol/*.swift visionOSClient/VisionSpatialInputPolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
