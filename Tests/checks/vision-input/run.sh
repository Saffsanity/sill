#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p .build/checks/vision-input
swiftc visionOSClient/VisionInputGeometry.swift Tests/checks/vision-input/main.swift -o .build/checks/vision-input/check
.build/checks/vision-input/check
