#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
out=.build/checks/vision-controls
mkdir -p "$out"
sed '/^import StreamProtocol$/d' iOSClient/KeyChords.swift > "$out/KeyChords.swift"
sed '/^import StreamProtocol$/d' visionOSClient/VisionTextInput.swift > "$out/VisionTextInput.swift"
swiftc Sources/StreamProtocol/Input.swift "$out/KeyChords.swift" "$out/VisionTextInput.swift" visionOSClient/VisionHIDKey.swift visionOSClient/VisionSessionPolicy.swift iOSClient/PointerPresence.swift Tests/checks/vision-controls/main.swift -o "$out/check"
"$out/check"
