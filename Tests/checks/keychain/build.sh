#!/bin/bash
# usage: build.sh WT OUT [IdentityStorePlan.swift override]
# Compiles the pure store-selection rule (Sources/SillMenuBar/IdentityStorePlan.swift, Foundation
# only) with this check's main.swift. No StreamProtocol, no bundle, no keychain.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$WT/Sources/SillMenuBar/IdentityStorePlan.swift}" "$T/IdentityStorePlan.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
