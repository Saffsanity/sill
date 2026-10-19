#!/bin/bash
# Writes clients/core/src/testFixtures/resources/sill/sample-*.hevc: short HEVC streams (Annex B)
# made by ffmpeg's libx265 the way the Mac's VideoToolbox encodes (no B-frames, one keyframe first,
# low latency), for the decoders' tests. HevcSample (testFixtures) splits them into the wire's
# parameter sets and length-prefixed access units.
#   clients/wire-vectors/hevc_sample.sh
set -euo pipefail
out="$(cd "$(dirname "$0")/.." && pwd)/core/src/testFixtures/resources/sill"
mkdir -p "$out"
x265="bframes=0:keyint=1000:min-keyint=1000:scenecut=0:log-level=error"
# A flat colour, so a test can check the picture's pixels.
ffmpeg -loglevel error -y -f lavfi -i "color=c=0x3366CC:s=320x240:r=30" -frames:v 12 -pix_fmt yuv420p \
    -c:v libx265 -preset ultrafast -tune zerolatency -x265-params "$x265" -f hevc "$out/sample-color.hevc"
# A moving test pattern at an odd size (a Mac window's), so every frame differs.
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=s=642x418:r=30" -frames:v 30 -pix_fmt yuv420p \
    -c:v libx265 -preset ultrafast -tune zerolatency -x265-params "$x265" -f hevc "$out/sample-motion.hevc"
ls -l "$out"
