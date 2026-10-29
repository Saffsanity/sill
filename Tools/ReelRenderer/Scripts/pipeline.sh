#!/bin/bash
# The reel's delivery steps, as v3.1 ran them (design/reel/v3/SHOTLIST-v3.md §8.2 and §11): the score, the silent
# film, the film with its score, the poster frame, the finished MP4s (cover art, `moov` first, no video edit
# list), the checks and the contact sheet, into $REEL_DIR/v31/out (REEL_DIR defaults to work/ here).
#
# Everything runs at utility priority with the renderer's software H.264 encoder: Sill.app may be streaming, and
# it shares the Mac's one hardware video encoder. The script refuses the hardware encoder and the test switches.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
export REEL_DIR=${REEL_DIR:-$HERE/work}
OUT=$REEL_DIR/v31/out
RR=$HERE/.build/release/ReelRenderer
[ -z "${SILL_HW_ENCODER:-}" ] || { echo "SILL_HW_ENCODER is set: refusing (the software encoder only)"; exit 1; }
[ -z "${REEL_V31_NO_ARROW:-}${REEL_V31_FLAT:-}${REEL_V31_NO_GRAIN:-}" ] || { echo "a REEL_V31_ test switch is set: refusing"; exit 1; }
(cd "$HERE" && taskpolicy -c utility swift build -c release)
mkdir -p "$OUT"
cd "$OUT"
[ -f score.wav ] || taskpolicy -c utility "$RR" score score.m4a --wav score.wav
taskpolicy -c utility "$RR" render --out silent.mp4 > render.log 2>&1
taskpolicy -c utility "$RR" mux silent.mp4 score.wav scored.mp4
taskpolicy -c utility "$RR" stills poster 75.2
taskpolicy -c utility "$RR" finalize --cover poster/still-S32-75.200.png --poster-out poster.jpg scored.mp4 silent.mp4
taskpolicy -c utility "$RR" verify scored.mp4 silent.mp4 > verify.log
taskpolicy -c utility "$RR" sheet scored.mp4 contact-sheet.png
ls -la scored.mp4 silent.mp4 poster.jpg contact-sheet.png
echo "pipeline done: $OUT"
