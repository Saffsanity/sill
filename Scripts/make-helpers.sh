#!/bin/bash
# Builds the two helpers Sill.app carries for Reach from Anywhere (docs/relay-plan.md) into
# .build/helpers/: sill-net (Helpers/sill-net, this repository's Go) and headscale (the pinned
# release in Helpers/tools/go.mod, its checksums in Helpers/tools/go.sum). Scripts/make-app.sh
# runs this and copies both into Sill.app/Contents/Helpers.
#
#   Scripts/make-helpers.sh                    this Mac's architecture
#   SILL_UNIVERSAL=1 Scripts/make-helpers.sh   arm64 and x86_64, joined with lipo (as make-app.sh)
#
# Needs Go (the version in Helpers/sill-net/go.mod, or newer): https://go.dev/dl or
# `brew install go`. Both are pure Go (CGO_ENABLED=0), built -trimpath, so the same source gives
# the same binary on any Mac with the same Go. Skipped when the binaries are newer than every
# input (the go.mod/go.sum files, Helpers/sill-net's sources and this script).
set -euo pipefail
cd "$(dirname "$0")/.."

out=.build/helpers
mkdir -p "$out"
if ! command -v go >/dev/null 2>&1; then
    echo "error: Go is not installed; Reach from Anywhere's helpers need it (https://go.dev/dl, or brew install go)." >&2
    exit 1
fi

if [ "${SILL_UNIVERSAL:-}" = 1 ]; then archs=(arm64 amd64); else
    case "$(uname -m)" in arm64) archs=(arm64) ;; *) archs=(amd64) ;; esac
fi
stamp="$out/.inputs"
inputs="$( { echo "${archs[*]}"; go version; cat "$0" Helpers/tools/go.mod Helpers/tools/go.sum Helpers/sill-net/go.mod Helpers/sill-net/go.sum;
             find Helpers/sill-net -name '*.go' -type f | LC_ALL=C sort | xargs cat; } | shasum -a 256 | awk '{ print $1 }')"
if [ -x "$out/sill-net" ] && [ -x "$out/headscale" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$inputs" ]; then
    echo "Helpers up to date in $out"
    exit 0
fi

export CGO_ENABLED=0 GOOS=darwin GOFLAGS=-mod=readonly
for arch in "${archs[@]}"; do
    echo "==> sill-net ($arch)"
    (cd Helpers/sill-net && GOARCH="$arch" go build -trimpath -ldflags "-s -w" -o "$PWD/../../$out/sill-net-$arch" .)
    echo "==> headscale $(awk '{ for (i = 1; i < NF; i++) if ($i == "github.com/juanfont/headscale") print $(i + 1) }' Helpers/tools/go.mod) ($arch)"
    (cd Helpers/tools && GOARCH="$arch" go build -trimpath -ldflags "-s -w" -o "$PWD/../../$out/headscale-$arch" github.com/juanfont/headscale/cmd/headscale)
done
for name in sill-net headscale; do
    if [ "${#archs[@]}" -gt 1 ]; then
        lipo -create "$out/$name-arm64" "$out/$name-amd64" -output "$out/$name"
    else
        cp "$out/$name-${archs[0]}" "$out/$name"
    fi
    rm -f "$out/$name"-arm64 "$out/$name"-amd64
done
echo "$inputs" > "$stamp"
ls -lh "$out/sill-net" "$out/headscale" | awk '{ print "  " $5 "  " $9 }'
