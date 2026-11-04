#!/bin/bash
# Brings Packaging/Localizable.xcstrings, the String Catalog Sill for Mac's translations live in, up
# to date with the source: every string the Mac's code shows (SwiftUI literals, String(localized:))
# added as a key, a string no longer in the source marked stale, every translation kept. Run it after
# changing or adding words the Mac shows, then translate the new keys (Xcode opens the catalog, or
# edit its JSON); make-app.sh compiles it into Sill.app.
#
#   Scripts/sync-strings.sh
#
# Each module's strings are exported on their own: StreamProtocol and SillMenuBar both have a
# HostSettings.swift, and the compiler names each .stringsdata after its source file, so one shared
# folder would keep only one of them. The build has a folder of its own, made afresh each run, since
# an incremental build that compiles nothing writes no strings. The iOS app's catalogs
# (iOSClient/Localizable.xcstrings, InfoPlist.xcstrings) are Xcode's: it extracts them as it builds.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$PWD/.build/strings"   # absolute: the compiler runs elsewhere
rm -rf "$out"
for target in StreamProtocol SillHostCore SillMenuBar; do
    mkdir -p "$out/strings-$target"
    swift build -c release --scratch-path "$out/build" --target "$target" \
        -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$out/strings-$target"
done
xcrun xcstringstool sync Packaging/Localizable.xcstrings --stringsdata "$out"/strings-*/*.stringsdata
echo "Packaging/Localizable.xcstrings: $(grep -c '"extractionState" : "stale"' Packaging/Localizable.xcstrings || true) stale"
