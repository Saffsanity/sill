#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
sed '/^import StreamProtocol$/d' visionOSClient/VisionToolbarPreferences.swift > "$out/VisionToolbarPreferences.swift"
swiftc Sources/StreamProtocol/Input.swift "$out/VisionToolbarPreferences.swift" "$here/main.swift" -o "$out/check"
"$out/check"
python3 "$here/structure.py"
