#!/bin/bash
# The recording rig (docs/recording-plan.md, gate G3): the device's recorder without a device. Builds recordcheck and
# moviecheck (build.sh), then runs each case against a synthetic SillHost on 127.0.0.1 alone (SILL_TEST_LOOPBACK,
# SILL_TEST_SOFTWARE_ENCODER, SILL_TEST_NO_ROUTER, SILL_TEST_NO_SCREEN: never the hardware encoder, the router or a
# screen recording), each under a minute, and reads every movie with moviecheck. run.py has the cases and their
# gates; the exit status is the number of gates that failed. Needs `swift build -c release` first (the host).
# Heavy: run it inside the heavy lock (Noah's Mac shares its one video encoder with his stream; this never uses it,
# but the builds and hosts are work).
#   Scripts/recording-check/run.sh              every case (about 6 minutes)
#   Scripts/recording-check/run.sh plain still  those cases
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
"$here/build.sh" || exit 1
python3 "$here/run.py" "$root" "$root/.build/recording-check/runs/$(date +%Y%m%d-%H%M%S)" "$@"
