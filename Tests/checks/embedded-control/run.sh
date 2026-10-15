#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
swiftc Sources/SillMenuBar/EmbeddedCommand.swift Sources/SillHost/KeychainItemNames.swift Tests/checks/embedded-control/main.swift -o "$bin/check"
"$bin/check"
