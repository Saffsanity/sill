#!/bin/bash
# The clients' design layer from the iOS app's own code (docs/ui-parity.md):
#  - clients/core/src/main/kotlin/me/saffer/sill/core/ui/Tokens.kt, every colour, metric, size and
#    curve the iOS app draws with, read from its Swift (extract_tokens.py);
#  - clients/core/src/test/resources/sill/ui-vectors.json, what iOSClient/PhonePortraitLayout.swift,
#    HostSettingsLedger.swift and DuoPosture.swift compute, compiled as they are with swiftc (the core's tests hold the
#    Kotlin ports to it);
#  - and a check that every word in the core's Copy and PanelCopy is still the iOS app's (check_copy.py).
# Needs python3 and swiftc (Xcode on a Mac, or swift.org's toolchain on Linux).
#   clients/design/generate.sh            regenerate both files (commit the result)
#   clients/design/generate.sh --verify   regenerate into .build and fail if a committed file differs
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/design"
mkdir -p "$out"
cd "$root"
tokens="$root/clients/core/src/main/kotlin/me/saffer/sill/core/ui/Tokens.kt"
vectors="$root/clients/core/src/test/resources/sill/ui-vectors.json"

python3 "$here/extract_tokens.py" iOSClient "$out/Tokens.kt"
python3 "$here/check_copy.py" iOSClient clients/core/src/main/kotlin/me/saffer/sill/core/ui

# The layout and the ledger as the iOS app has them: PhonePortraitLayout.swift imports CoreGraphics,
# whose CGRect Foundation has on Linux too; HostSettingsLedger.swift compiles with HostSettings.swift
# as one module (its own #if says so).
sed 's/^import CoreGraphics$/import Foundation/' iOSClient/PhonePortraitLayout.swift > "$out/PhonePortraitLayout.swift"
grep -v '^import StreamProtocol' Sources/StreamProtocol/HostSettings.swift > "$out/HostSettings.swift"
# DuoPosture.swift (the fold's rules) is Foundation and CoreGraphics only, as Tests/checks/duo compiles it.
sed 's/^import CoreGraphics$/import Foundation/' iOSClient/DuoPosture.swift > "$out/DuoPosture.swift"
swiftc -O "$out/PhonePortraitLayout.swift" "$out/HostSettings.swift" "$out/DuoPosture.swift" iOSClient/HostSettingsLedger.swift "$here/swift/main.swift" \
    -o "$out/vectors" 2>&1 | grep -v "^$" || true
[ -x "$out/vectors" ] || { echo "generate.sh: the generator did not compile" >&2; exit 1; }
"$out/vectors" > "$out/ui-vectors.json"

case "${1:-}" in
    --verify)
        status=0
        if cmp -s "$out/Tokens.kt" "$tokens"; then echo "Tokens.kt matches iOSClient"
        else echo "Tokens.kt is stale: run clients/design/generate.sh and commit it" >&2; diff -u "$tokens" "$out/Tokens.kt" | head -40 >&2 || true; status=1; fi
        if cmp -s "$out/ui-vectors.json" "$vectors"; then echo "ui-vectors.json matches iOSClient"
        else echo "ui-vectors.json is stale: run clients/design/generate.sh and commit it" >&2; status=1; fi
        exit $status ;;
    "")
        cp "$out/Tokens.kt" "$tokens"
        mkdir -p "$(dirname "$vectors")"
        cp "$out/ui-vectors.json" "$vectors"
        echo "wrote $tokens and $vectors" ;;
    *) echo "usage: generate.sh [--verify]" >&2; exit 2 ;;
esac
