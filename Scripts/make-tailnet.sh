#!/bin/bash
# Builds SillTailnet.xcframework (Helpers/tailnet-mobile: Reach from Anywhere's tailnet inside
# Sill for iPhone and iPad, docs/relay-plan.md) into .build/tailnet/. The Xcode project's
# "SillTailnet" target runs this before the app compiles, and links the framework statically.
#
#   Scripts/make-tailnet.sh                  device and simulator slices (arm64)
#   Scripts/make-tailnet.sh --device-only    the device slice alone (an archive)
#
# A c-archive per slice with a hand-written C API (Helpers/tailnet-mobile/sill_tailnet.go), not
# gomobile. GOOS=ios for both slices: the SDK and its version-min flag are what stamp each Mach-O's
# platform, which is how xcodebuild -create-xcframework tells them apart. Skipped when the
# framework is newer than every input. Needs Go (Scripts/make-helpers.sh says how to get it).
set -euo pipefail
cd "$(dirname "$0")/.."

min_ios=17.0
out=.build/tailnet
framework="$out/SillTailnet.xcframework"
device_only=0
if [ "${1:-}" = "--device-only" ]; then device_only=1; fi
# Xcode's build phases run with a minimal PATH; Go's usual homes.
export PATH="$PATH:/usr/local/go/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/go/bin:$HOME/.local/bin"
if ! command -v go >/dev/null 2>&1; then
    echo "error: Go is not installed; SillTailnet.xcframework needs it (https://go.dev/dl, or brew install go)." >&2
    exit 1
fi

stamp="$out/.inputs"
inputs="$( { echo "$device_only $min_ios"; go version; xcrun --sdk iphoneos --show-sdk-version; cat "$0" Helpers/tailnet-mobile/go.mod Helpers/tailnet-mobile/go.sum;
             find Helpers/tailnet-mobile -name '*.go' -type f ! -name '*_test.go' ! -path '*/cmd/*' | LC_ALL=C sort | xargs cat; } | shasum -a 256 | awk '{ print $1 }')"
if [ -d "$framework" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$inputs" ]; then
    echo "SillTailnet.xcframework up to date in $out"
    exit 0
fi
rm -rf "$out"
mkdir -p "$out"

slice() {
    local name="$1" sdk="$2" flag="$3" dir sysroot clang
    dir="$PWD/$out/$name"
    mkdir -p "$dir/include"
    sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    clang="$(xcrun --sdk "$sdk" -f clang)"
    echo "==> SillTailnet $name"
    (cd Helpers/tailnet-mobile && CGO_ENABLED=1 GOOS=ios GOARCH=arm64 GOFLAGS=-mod=readonly \
        CC="$clang -isysroot $sysroot $flag -arch arm64" \
        CGO_CFLAGS="-isysroot $sysroot $flag -arch arm64" CGO_LDFLAGS="-isysroot $sysroot $flag -arch arm64" \
        go build -trimpath -buildmode=c-archive -tags ios -o "$dir/libsilltailnet.a" .)
    mv "$dir/libsilltailnet.h" "$dir/include/SillTailnet.h"
    printf 'module SillTailnet {\n    header "SillTailnet.h"\n    export *\n}\n' > "$dir/include/module.modulemap"
}
slice ios-arm64 iphoneos "-miphoneos-version-min=$min_ios"
args=(-library "$PWD/$out/ios-arm64/libsilltailnet.a" -headers "$PWD/$out/ios-arm64/include")
if [ "$device_only" = 0 ]; then
    slice ios-arm64-simulator iphonesimulator "-mios-simulator-version-min=$min_ios"
    args+=(-library "$PWD/$out/ios-arm64-simulator/libsilltailnet.a" -headers "$PWD/$out/ios-arm64-simulator/include")
fi
xcodebuild -create-xcframework "${args[@]}" -output "$framework" >/dev/null
echo "$inputs" > "$stamp"
echo "Built $framework ($(du -sh "$framework" | awk '{ print $1 }'))"
