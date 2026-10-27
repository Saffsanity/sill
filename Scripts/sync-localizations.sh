#!/bin/bash
# Extract from fresh builds, then sync each app's catalog once with all its targets.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-all}" in
    mac|ios|all) platform="${1:-all}" ;;
    *) echo "usage: $0 [mac|ios|all]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
    echo "usage: $0 [mac|ios|all]" >&2; exit 2
fi
if ! xcrun --find xcstringstool >/dev/null 2>&1 || ! xcrun --find xcodebuild >/dev/null 2>&1; then
    echo "error: select a full Xcode installation with xcode-select (xcstringstool is required)." >&2
    exit 1
fi

mkdir -p .build
tmp="$(mktemp -d "$PWD/.build/localizations.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Both the app and its package dependencies must have contributed data before sync.
require_target() {
    local root="$1" target="$2"
    if [ -z "$(find "$root" -path "*/${target}.build/Objects-normal/*/*.stringsdata" -print -quit)" ]; then
        echo "error: no stringsdata for target $target in $root" >&2
        exit 1
    fi
}

if [ "$platform" != ios ]; then
    test -f Packaging/Localizable.xcstrings || { echo 'error: missing Packaging/Localizable.xcstrings' >&2; exit 1; }
    echo 'Extracting Mac strings...'
    xcodebuild -scheme SillMenuBar -configuration Debug -destination 'platform=macOS' \
        -derivedDataPath "$tmp/mac" SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGNING_ALLOWED=NO build -quiet
    require_target "$tmp/mac/Build/Intermediates.noindex" SillMenuBar-p
    require_target "$tmp/mac/Build/Intermediates.noindex" SillHostCore-t
    require_target "$tmp/mac/Build/Intermediates.noindex" StreamProtocol-t
fi
if [ "$platform" != mac ]; then
    test -f iOSClient/Localizable.xcstrings || { echo 'error: missing iOSClient/Localizable.xcstrings' >&2; exit 1; }
    echo 'Extracting iOS strings...'
    xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -configuration Debug \
        -destination 'generic/platform=iOS' -derivedDataPath "$tmp/ios" \
        SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGNING_ALLOWED=NO build -quiet
    require_target "$tmp/ios/Build/Intermediates.noindex" Sill
    require_target "$tmp/ios/Build/Intermediates.noindex" StreamProtocol-t
fi

sync_catalog() {
    local catalog="$1" root="$2" file
    local data=()
    while IFS= read -r -d '' file; do data+=("$file"); done < <(find "$root" -name '*.stringsdata' -print0)
    if [ "${#data[@]}" -eq 0 ]; then
        echo "error: no stringsdata found in $root" >&2
        exit 1
    fi
    echo "Syncing $catalog (${#data[@]} files)..."
    xcrun xcstringstool sync "$catalog" --stringsdata "${data[@]}"
}

if [ "$platform" != ios ]; then
    sync_catalog Packaging/Localizable.xcstrings "$tmp/mac/Build/Intermediates.noindex"
fi
if [ "$platform" != mac ]; then
    sync_catalog iOSClient/Localizable.xcstrings "$tmp/ios/Build/Intermediates.noindex"
fi
