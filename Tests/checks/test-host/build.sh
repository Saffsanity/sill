#!/bin/bash
# usage: build.sh WT OUT [AppIdentity.swift override]
# Compiles which launches are Sill.app itself (Sources/SillMenuBar/AppIdentity.swift: Foundation and
# Security) with the identity store's rule (IdentityStorePlan.swift, Foundation) and this check's
# main.swift. No bundle, no keychain, no network.
WT=$1; OUT=$2; T=$(mktemp -d)
cp "${3:-$WT/Sources/SillMenuBar/AppIdentity.swift}" "$T/AppIdentity.swift"
cp "$WT/Sources/SillMenuBar/IdentityStorePlan.swift" "$T/IdentityStorePlan.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
