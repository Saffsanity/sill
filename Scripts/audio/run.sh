#!/bin/bash
# The encoder-free sound harness (docs/audio-plan.md §11: H5, H6, H8, H12): the real StreamServer and
# the sound's host files with the test tone and fake frames (build.sh), a device that decodes every
# kind 29 and finds the tone's clicks (Scripts/audiocheck.swift), and on the away cases a shaped path
# (Scripts/pacing/bottleneck.py, Scripts/sillrelay.py), all on 127.0.0.1. No encoder, no Screen
# Recording, no sound captured or played, no device. Then summarize.py's table and gates; the exit
# status is the number of gates that failed, plus one for each run that could not run.
#
#   Scripts/audio/run.sh                   every case (about 7 minutes)
#   Scripts/audio/run.sh --cases home,home-off
#   Scripts/audio/run.sh --list
# Everything goes to .build/audio (git-ignored): the host package, audiocheck, and each matrix's runs in
# .build/audio/runs/<date-time>/.
#
# The cases (name|seconds|DOOR|RELAY|DEVICES|HOSTENV|gate|host args -- relay args -- device args):
#   home       H5: 60 s at home, Balanced-sized frames (300 KB keyframes, 30 KB deltas) at 60 fps, Send
#              Audio on: 100 ± 1 packets a second, no seq gap, every click within 1 ms of its second
#   home-off   the same with Send Audio off: no sound, and the picture's net.sent, net.dropped and
#              frame age as with it (H5), the host's CPU (H12)
#   home1024   H5 with 1024-frame chunks (SILL_TEST_AUDIO_CHUNK): 93.75 packets a second
#   segments   H8 on two devices: each tone paused 50 ms at 3 s and 500 ms at 6 s after it starts, the
#              source changed at 12 s: a segment start at each resumed chunk, placed by its stamp (the
#              clicks), nothing more than 40 ms after its stamp, a new epoch with its format first on
#              each device
#   away8      H6: the remote door (TLS) through an 8 Mbit/s bottleneck, 70 ms, 1.5 MB keyframes and
#              30 KB deltas (more than the link): frames dropped, the sound never; packets no later
#              than the frames + 20 ms; away8-off the same without sound
#   away4      the same at 4 Mbit/s
#   dip        H6: Low-sized frames on 8 Mbit/s with 0.5 from 20 s to 32 s: sound and frames late
#              together (the packets no later than the frames + 20 ms and the sound's own time before
#              it goes out), and back together (the sound's age back in the second the frames' is)
#   relay2     H6: the remote door's slow link (sillrelay.py, 2 Mbit/s, +150 ms), the synthetic host's
#              frame sizes: no eviction, the sound never dropped
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
only="" list=0
while [ $# -gt 0 ]; do
    case "$1" in
        --cases) only="$2"; shift 2 ;;
        --list) list=1; shift ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "usage: Scripts/audio/run.sh [--cases a,b] [--list]" >&2; exit 2 ;;
    esac
done
cases=(
  "home|60|Home|none|1||home|--audio -- --"
  "home-off|60|Home|none|1||same-as=home|-- --"
  "home1024|30|Home|none|1|SILL_TEST_AUDIO_CHUNK=1024|home1024|--audio -- --"
  "segments|20|Home|none|2|SILL_TEST_AUDIO_PAUSE=0.05@3,0.5@6|segments|--audio --switch-at 12 -- --"
  "away8|45|Remote|bottleneck|1||away-drops|--audio --kf 1500000 --delta 30000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 --"
  "away8-off|45|Remote|bottleneck|1||none|--kf 1500000 --delta 30000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 --"
  "away4|45|Remote|bottleneck|1||away-drops|--audio --kf 1500000 --delta 30000 -- --rate-mbps 4 --delay-ms 70 --queue-bytes 262144 --"
  "dip|50|Remote|bottleneck|1||dip=20-32|--audio --kf 100000 --delta 8000 -- --rate-mbps 8 --rate-at 20:0.5,32:8 --delay-ms 70 --queue-bytes 1048576 --"
  "relay2|60|Remote|sillrelay|1||away|--audio --kf 100000 --delta 2000 -- --rate-mbps 2 --delay-ms 150 --"
)
if [ "$list" = 1 ]; then printf '%s\n' "${cases[@]}"; exit 0; fi
"$here/build.sh" || exit 1
runs="$root/.build/audio/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$runs"
specs=() broken=0
for c in "${cases[@]}"; do
    IFS='|' read -r name seconds door relay devices hostenv gate rest <<< "$c"
    if [ -n "$only" ] && [[ ",$only," != *",$name,"* ]]; then continue; fi
    echo "==> $name ($seconds s)"
    # shellcheck disable=SC2086
    if ! AUDIO_RUNS="$runs" DOOR="$door" RELAY="$relay" DEVICES="$devices" HOSTENV="$hostenv" \
         python3 "$here/run.py" "$name" "$seconds" $rest; then
        echo "    $name could not run" >&2
        broken=$((broken + 1))
    fi
    specs+=("$name:$gate")
done
python3 "$here/summarize.py" "$runs" "${specs[@]}"
status=$?
exit $((status + broken))
