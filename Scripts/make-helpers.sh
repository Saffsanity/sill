#!/bin/bash
# Builds the helper Sill.app carries for Reach from Anywhere (docs/relay-plan.md) into
# .build/helpers/sill-net: Helpers/sill-net, this repository's Go, with Headscale built in (the
# version Helpers/sill-net/go.mod pins, its checksums in go.sum; it runs as `sill-net headscale
# serve`, so the Go runtime, tsnet and gvisor ship once). Scripts/make-app.sh runs this and copies
# it into Sill.app/Contents/Helpers.
#
#   Scripts/make-helpers.sh                    this Mac's architecture
#   SILL_UNIVERSAL=1 Scripts/make-helpers.sh   arm64 and x86_64, joined with lipo (as make-app.sh)
#
# Needs Go (the version in Helpers/sill-net/go.mod, or newer): https://go.dev/dl or
# `brew install go`. Pure Go (CGO_ENABLED=0), built -trimpath, so the same source gives the same
# binary on any Mac with the same Go. Skipped when nothing it reads changed (go.mod, go.sum,
# Helpers/sill-net's sources and this script).
set -euo pipefail
cd "$(dirname "$0")/.."

out=.build/helpers
mkdir -p "$out"
if ! command -v go >/dev/null 2>&1; then
    echo "error: Go is not installed; Reach from Anywhere's helper needs it (https://go.dev/dl, or brew install go)." >&2
    exit 1
fi

if [ "${SILL_UNIVERSAL:-}" = 1 ]; then archs=(arm64 amd64); else
    case "$(uname -m)" in arm64) archs=(arm64) ;; *) archs=(amd64) ;; esac
fi
stamp="$out/.inputs"
inputs="$( { echo "${archs[*]}"; go version; cat "$0" Helpers/sill-net/go.mod Helpers/sill-net/go.sum;
             find Helpers/sill-net -name '*.go' -type f ! -name '*_test.go' | LC_ALL=C sort | xargs cat; } | shasum -a 256 | awk '{ print $1 }')"
if [ -x "$out/sill-net" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$inputs" ]; then
    echo "Helper up to date in $out"
    exit 0
fi
rm -f "$out/headscale"      # a separate Headscale, from before it was built into sill-net

export CGO_ENABLED=0 GOOS=darwin GOFLAGS=-mod=readonly
headscale="$(awk '{ for (i = 1; i < NF; i++) if ($i == "github.com/juanfont/headscale") print $(i + 1) }' Helpers/sill-net/go.mod)"
for arch in "${archs[@]}"; do
    echo "==> sill-net with Headscale $headscale ($arch)"
    (cd Helpers/sill-net && GOARCH="$arch" go build -trimpath -ldflags "-s -w" -o "$PWD/../../$out/sill-net-$arch" .)
done
if [ "${#archs[@]}" -gt 1 ]; then
    lipo -create "$out/sill-net-arm64" "$out/sill-net-amd64" -output "$out/sill-net"
else
    cp "$out/sill-net-${archs[0]}" "$out/sill-net"
fi
rm -f "$out"/sill-net-arm64 "$out"/sill-net-amd64
echo "$inputs" > "$stamp"
ls -lh "$out/sill-net" | awk '{ print "  " $5 "  " $9 }'
