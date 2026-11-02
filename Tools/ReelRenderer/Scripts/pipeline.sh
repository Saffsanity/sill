#!/bin/bash
# The reel's delivery steps, as v3.1 ran them (design/reel/v3/SHOTLIST-v3.md §8.2 and §11): the score, the silent
# film, the film with its score, the poster frame, the finished MP4s (cover art, `moov` first, no video edit
# list), the checks and the contact sheet, into $REEL_DIR/v31/out (REEL_DIR defaults to work/ here).
# REEL=060 makes the 0.6 update video instead (Reel060.swift; design/reel/v4.1/SHOTLIST-0.6.md), into
# $REEL_DIR/060/out, its poster the end card at 138.0 s (v4.1; 133.2 in its first cut, v4's at 77.2).
#
# Everything runs at utility priority with the renderer's software H.264 encoder: Sill.app may be streaming, and
# it shares the Mac's one hardware video encoder. The script refuses the hardware encoder and the test switches,
# and before each encoding step waits until no device is connected to Sill.app (the repository's
# Scripts/encoder-check/no-device.sh, when it is there), pausing the step while one connects.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
export REEL_DIR=${REEL_DIR:-$HERE/work}
export REEL=${REEL:-v31}
if [ "$REEL" = "060" ]; then
    OUT=$REEL_DIR/060/out; POSTER_T=138.0; POSTER_PNG=poster/still-S22-138.000.png
else
    OUT=$REEL_DIR/v31/out; POSTER_T=75.2; POSTER_PNG=poster/still-S32-75.200.png
fi
RR=$HERE/.build/release/ReelRenderer
NO_DEVICE=${NO_DEVICE:-$HERE/../../Scripts/encoder-check/no-device.sh}
# The renderer takes the hardware encoder whenever SILL_HW_ENCODER is set, to any value (Render.swift), empty included.
[ -z "${SILL_HW_ENCODER+set}" ] || { echo "SILL_HW_ENCODER is set: refusing (the software encoder only)"; exit 1; }
[ -z "${REEL_V31_NO_ARROW:-}${REEL_V31_FLAT:-}${REEL_V31_NO_GRAIN:-}" ] || { echo "a REEL_V31_ test switch is set: refusing"; exit 1; }
# The type's test switches (GlyphText.swift) take effect when set to anything, empty included.
[ -z "${REEL_TYPE_LEGACY+set}${REEL_TYPE_OFFSET+set}" ] || { echo "REEL_TYPE_LEGACY or REEL_TYPE_OFFSET is set: refusing"; exit 1; }
# Waits (up to an hour, a look every 30 s) until no device is connected to Sill.app.
guard_device() {
    [ -x "$NO_DEVICE" ] || { echo "no-device check not found at $NO_DEVICE: going on"; return 0; }
    for _ in $(seq 1 120); do
        if "$NO_DEVICE" > /dev/null 2>&1; then echo "no device connected to Sill.app ($(date +%H:%M:%S)): $1"; return 0; fi
        echo "a device is connected to Sill.app: waiting before $1"; sleep 30
    done
    echo "still a device connected after an hour: stopping before $1"; exit 1
}
# Runs one encoding step at utility priority, writing its output to a log, once no device is connected to Sill.app,
# and pauses it (SIGSTOP) while one connects, resuming it (SIGCONT) when it leaves: nothing encodes while a device is
# connected. taskpolicy execs the step in place, so its pid is the step's.
guarded() {
    local what=$1 log=$2; shift 2
    guard_device "$what"
    taskpolicy -c utility "$@" > "$log" 2>&1 &
    local pid=$! paused=0
    if [ -x "$NO_DEVICE" ]; then
        while kill -0 "$pid" 2>/dev/null; do
            sleep 10
            kill -0 "$pid" 2>/dev/null || break
            if "$NO_DEVICE" > /dev/null 2>&1; then
                if [ "$paused" = 1 ]; then kill -CONT "$pid"; paused=0; echo "no device connected ($(date +%H:%M:%S)): $what resumed"; fi
            elif [ "$paused" = 0 ]; then
                kill -STOP "$pid"; paused=1; echo "a device connected to Sill.app ($(date +%H:%M:%S)): $what paused"
            fi
        done
    fi
    wait "$pid"
}
(cd "$HERE" && taskpolicy -c utility swift build -c release)
mkdir -p "$OUT"
cd "$OUT"
[ -f score.wav ] || taskpolicy -c utility "$RR" score score.m4a --wav score.wav
# The render checks every frame's type against its path (README, The type) and fails if a glyph strays.
START=$(date +%s)
guarded "the render" render.log "$RR" render --out silent.mp4 --typecheck || { tail -40 render.log; exit 1; }
echo "the render took $(( $(date +%s) - START )) s (render.log has the typecheck)"
guarded "the mux" mux.log "$RR" mux silent.mp4 score.wav scored.mp4 || { cat mux.log; exit 1; }
taskpolicy -c utility "$RR" stills poster "$POSTER_T"
taskpolicy -c utility "$RR" finalize --cover "$POSTER_PNG" --poster-out poster.jpg scored.mp4 silent.mp4
taskpolicy -c utility "$RR" verify scored.mp4 silent.mp4 > verify.log
taskpolicy -c utility "$RR" sheet scored.mp4 contact-sheet.png
ls -la scored.mp4 silent.mp4 poster.jpg contact-sheet.png
echo "pipeline done: $OUT"
