#!/bin/bash
# The pacing harness (docs/remote-bundle-plan.md §3 and §11, H3): the host's remote pacing, base
# against new, with no encoder, no Screen Recording and no device. Each case runs a host, a shaped
# path and a device, all on loopback:
#   - the host (main.swift, built by build.sh): StreamServer.swift as it is at BASE (base) and in
#     the working tree (new), serving a remote session over RemoteTLS's TLS 1.3 parameters (home: a
#     home client over plain TCP), fed fake frames of the case's sizes (a keyframe when asked for
#     and every 4 s);
#   - bottleneck.py: a downlink of R Mbit/s behind a Q-byte queue, D ms of round trip (or, for the
#     remote door's slow-link cases, Scripts/sillrelay.py: R Mbit/s read from the host through a
#     64 KB buffer, D ms of round trip, a blackhole after S s);
#   - device.py: the iPad's reader, pings, stats and liveness (--liveness-bytes: MessageReader's).
# Then summarize.py's table: every run, and each case's base and new side by side with the new
# build's gate. Its exit status is the number of runs that could not run, plus one if a gate
# failed. A run starts only while the load average is under 20 (it waits up to 20 minutes), and one
# that ends with the load at 20 or more is run again (twice at most): the host, the relay and the
# device share the Mac's cores with whatever else runs, and a busy Mac makes a stalled path of any
# link. Each run's load at its start and end is in the matrix's load.txt.
#
#   Scripts/pacing/run.sh                  the gate cases once each (about 18 minutes)
#   Scripts/pacing/run.sh --full           the plan's H3 matrix and H4: every case, real24, kf25m32
#                                          and bigkf8 three times each (about 40 minutes)
#   Scripts/pacing/run.sh --cases real24,dip [--repeat 3]
#   Scripts/pacing/run.sh --base 8b0d418   compare with another commit (default origin/main)
#   Scripts/pacing/run.sh --list           the cases and their arguments
#   Scripts/pacing/summarize.py DIR        the table again, from a finished matrix
# Everything goes to .build/pacing (git-ignored): the two packages, the device's key, and each
# matrix's runs in .build/pacing/runs/<date-time>/.
#
# The cases (host arguments -- relay arguments -- device arguments; frame sizes in bytes):
#   real24   1.5 MB keyframes, 30 KB deltas, 24 Mbit/s, 70 ms: the 2026-09-25 hotspot loop at
#            Retina scale (base 39.5 fps and 13 drops a minute; new about 60 fps and none)
#   kf25m32  2.5 MB keyframes, 20 KB deltas, 32 Mbit/s (46 % load): base 1.4 fps, new about 60
#   bigkf8   1.5 MB keyframes, 8 KB deltas, 8 Mbit/s (85 % load): bistable, recorded
#   slowkfB  1.6 MB keyframes on 2 Mbit/s with MessageReader's liveness: no loss, 55 fps or more
#            after the first keyframe
#   ext120   Extreme at 120 fps: 2 MB keyframes, 312.5 KB deltas through 600 Mbit/s: never a drop
#   dip      Low's sizes, 8 Mbit/s with 0.5 from 20 s to 32 s behind a 1 MB queue: no loss, the
#            frame age back at 45 ms within 10 s of the dip's end
#   relay2   the remote door's slow link (the plan's H4; the remote plan's H14): sillrelay.py at
#            2 Mbit/s and +150 ms for 90 s, a stream the size of the synthetic host's (100 KB
#            keyframes, 2 KB deltas): no loss or eviction, a frame in every 5 s, keyframes a minute
#            no more than its base run's
#   blackhole  the same path going dead both ways 5 s into the connection (the remote plan's H15):
#            the host drops the device for its silence about 13 s after it connected (5 + 8)
#   stillend Pro · Retina-sized frames bigger than a 16 Mbit/s hotspot (60 KB deltas, so frames are
#            dropped all along) with the window going still for 8 s three times: the device comes
#            to show the last frame before each still spell (or that frame encoded again) within
#            5 s, not the picture from before a drop until the window next changes
#   restartkf  2.5 MB keyframes, 4 KB deltas on 32 Mbit/s (kf25m32's link), the stream restarting
#            0.1 s after a keyframe three times (a pick, a rotation or a settings change while a
#            keyframe is still being taken): the new stream's deltas follow its keyframe, nothing
#            dropped
#   The link's own cases (docs/remote-bundle-plan.md §6, H11; the new build's Link lines):
#   linkstill  slowkfB's sizes and liveness, the window still for 10 s from 31 s, while its second
#            keyframe is still crossing: never behind or stalled after the first keyframe
#   linkdead   Low's sizes on 8 Mbit/s, the path dead both ways from 20 s: stalled within 8 s (the
#            loopback path's buffers first take 0.7–1 MB)
#   linkdown   the same, the downlink alone at 0 from 20 s (the device's pings still arrive): behind
#            within 3 s of the end of the host's first second withholding frames, never stalled
#   linkrestart  over8's stream on its 8 Mbit/s link, restarting twice at the same quality (a window
#            picked, a rotation: --restart-at): behind within 5 s of the first keyframe and never
#            fine after it, reset included, since a restart that keeps the quality keeps the
#            judgement (the review of 2026-09-27: clearing it there made the device's line go and
#            come back, spoken again, a few seconds later)
#   and the link's gates on real24 (never behind), over8 (behind within 5 s, carried within 20 % of
#   8 Mbit/s, Low suggested for Pro), dip (behind within 3 s of the end of the host's first second
#   withholding frames, which waits for the dip's 1 MB queue to fill; fine within 10 s of its end),
#   slowkfB (never behind or stalled after the first keyframe) and home (never behind)
#   --full adds ext60 (Extreme at 60 fps, 400 Mbit/s), fastbig (150 KB deltas on 100 Mbit/s),
#   low, switch (Pro-sized to Low-sized at 30 s), over8 (a stream bigger than the link), slowkf
#   (the old device's liveness: whole messages) and home (a home client, plain TCP: unchanged).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/pacing"
base=origin/main full=0 repeat=1 only="" list=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base) base="$2"; shift 2 ;;
        --full) full=1; shift ;;
        --repeat) repeat="$2"; shift 2 ;;
        --cases) only="$2"; shift 2 ;;
        --list) list=1; shift ;;
        -h|--help) sed -n '2,72p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "usage: Scripts/pacing/run.sh [--full] [--cases a,b] [--repeat N] [--base REF] [--list]" >&2; exit 2 ;;
    esac
done

# name|seconds|repeats in --full|DOOR|RELAY|host args -- relay args -- device args
# (DOOR: the host's door run.py waits for; RELAY: bottleneck.py or Scripts/sillrelay.py)
cases=(
  "real24|45|3|Remote|bottleneck|--kf 1500000 --delta 30000 -- --rate-mbps 24 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "kf25m32|40|3|Remote|bottleneck|--kf 2500000 --delta 20000 -- --rate-mbps 32 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "bigkf8|45|3|Remote|bottleneck|--kf 1500000 --delta 8000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "slowkfB|50|1|Remote|bottleneck|--kf 1600000 --delta 1000 --gop 30 --icons 20 -- --rate-mbps 2 --delay-ms 70 --queue-bytes 262144 -- --reconnect --liveness-bytes"
  "ext120|25|1|Remote|bottleneck|--kf 2000000 --delta 312500 --fps 120 -- --rate-mbps 600 --delay-ms 6 --queue-bytes 262144 -- --reconnect"
  "dip|60|1|Remote|bottleneck|--kf 150000 --delta 8000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 1048576 --rate-at 20:0.5,32:8 -- --reconnect"
  "relay2|90|1|Remote|sillrelay|--kf 100000 --delta 2000 -- --rate-mbps 2 --delay-ms 150 -- --reconnect --liveness-bytes"
  "blackhole|30|1|Remote|sillrelay|--kf 100000 --delta 2000 -- --rate-mbps 2 --delay-ms 150 --blackhole-after 5 -- --reconnect --liveness-bytes"
  "stillend|55|1|Remote|bottleneck|--kf 1500000 --delta 60000 --still-at 12:8,27:8,42:8 -- --rate-mbps 16 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "restartkf|40|1|Remote|bottleneck|--kf 2500000 --delta 4000 --restart-at 10:0.1,20:0.1,30:0.1 -- --rate-mbps 32 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "linkstill|55|1|Remote|bottleneck|--kf 1600000 --delta 1000 --gop 30 --icons 20 --still-at 31:10 -- --rate-mbps 2 --delay-ms 70 --queue-bytes 262144 -- --reconnect --liveness-bytes"
  "linkdead|35|1|Remote|bottleneck|--kf 150000 --delta 8000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 --blackhole-at 20 -- --reconnect --liveness-bytes"
  "linkdown|35|1|Remote|bottleneck|--kf 150000 --delta 8000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 --rate-at 20:0 -- --reconnect --liveness-bytes"
  "linkrestart|45|1|Remote|bottleneck|--kf 1500000 --delta 60000 --bitrate 40000000 --restart-at 20:0.1,30:0.1 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
)
full_cases=(
  "ext60|25|1|Remote|bottleneck|--kf 2000000 --delta 312500 --fps 60 -- --rate-mbps 400 --delay-ms 6 --queue-bytes 262144 -- --reconnect"
  "fastbig|40|1|Remote|bottleneck|--kf 1500000 --delta 150000 -- --rate-mbps 100 --delay-ms 20 --queue-bytes 1048576 -- --reconnect"
  "low|40|1|Remote|bottleneck|--kf 150000 --delta 8000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "switch|50|1|Remote|bottleneck|--kf 1500000 --delta 30000 --sizes-at 30:150000:8000 -- --rate-mbps 24 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "over8|45|1|Remote|bottleneck|--kf 1500000 --delta 60000 --bitrate 40000000 -- --rate-mbps 8 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "slowkf|50|1|Remote|bottleneck|--kf 1600000 --delta 1000 --gop 30 --icons 20 -- --rate-mbps 2 --delay-ms 70 --queue-bytes 262144 -- --reconnect"
  "home|30|1|Home|bottleneck|--kf 150000 --delta 8000 --home -- --rate-mbps 20 --delay-ms 10 --queue-bytes 262144 -- --plain"
)
all=("${cases[@]}" "${full_cases[@]}")
if [ "$list" = 1 ]; then
    for c in "${all[@]}"; do IFS='|' read -r name secs reps door relay rest <<< "$c"; printf '%-9s %3s s  %-6s %-10s %s\n' "$name" "$secs" "$door" "$relay" "$rest"; done
    exit 0
fi
selected=()
if [ -n "$only" ]; then
    IFS=',' read -r -a wanted <<< "$only"
    for w in "${wanted[@]}"; do
        hit=""
        for c in "${all[@]}"; do [ "${c%%|*}" = "$w" ] && hit="$c"; done
        [ -n "$hit" ] || { echo "run.sh: no case '$w' (--list)" >&2; exit 2; }
        selected+=("$hit")
    done
elif [ "$full" = 1 ]; then
    selected=("${all[@]}")
else
    selected=("${cases[@]}")
fi

"$here/build.sh" "$base" || exit 1

runs="$out/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$runs"
export PACING_OUT="$out" PACING_RUNS="$runs"
{
    echo "Pacing harness, $(date '+%Y-%m-%d %H:%M')"
    echo "base: $base = $(git -C "$root" rev-parse --short "$base"), StreamServer.swift md5 $(md5 -q "$out/base/Sources/Harness/StreamServer.swift")"
    dirty=""; git -C "$root" diff --quiet HEAD -- Sources/SillHost Sources/StreamProtocol Scripts/pacing || dirty=" with uncommitted changes"
    echo "new:  the working tree at $(git -C "$root" rev-parse --short HEAD)$dirty, StreamServer.swift md5 $(md5 -q "$out/new/Sources/Harness/StreamServer.swift")"
} > "$runs/matrix.txt"

load1() { sysctl -n vm.loadavg | awk '{print $2}'; }
busy() { [ "$(load1 | cut -d. -f1)" -ge 20 ]; }
# Waits (up to 20 minutes) for the load to fall under 20; false if it did not.
calm() {
    local waited=0
    while busy; do
        [ "$waited" -ge 1200 ] && return 1
        sleep 20; waited=$((waited + 20))
    done
}
missed=0
trap 'exit 130' INT TERM
for c in "${selected[@]}"; do
    IFS='|' read -r name secs reps door relay rest <<< "$c"
    n="$repeat"; if [ "$full" = 1 ] && [ -z "$only" ]; then n="$reps"; fi
    read -r -a argv <<< "$rest"
    for i in $(seq 1 "$n"); do
        for build in base new; do
            run="$name-$i-$build"
            for try in 1 2 3; do
                if ! calm; then
                    echo "$(date +%T) skipped $run: load $(load1)" | tee -a "$runs/load.txt"
                    missed=$((missed + 1)); break
                fi
                start="$(load1)"
                echo "$(date +%T) $run (${secs} s, load $start)" | tee -a "$runs/load.txt"
                if ! DOOR="$door" RELAY="$relay" python3 "$here/run.py" "$run" "$build" "$secs" "${argv[@]}" > "$runs/$run.run.txt" 2>&1; then
                    echo "    $run did not run: $(tail -n 1 "$runs/$run.run.txt")" | tee -a "$runs/load.txt"
                    missed=$((missed + 1)); break
                fi
                if busy && [ "$try" -lt 3 ]; then
                    echo "    $run ended with the load at $(load1): again" | tee -a "$runs/load.txt"
                    continue
                fi
                echo "    $run ended with the load at $(load1)" >> "$runs/load.txt"
                break
            done
        done
    done
done
echo
python3 "$here/summarize.py" "$runs"
status=$?
echo
echo "The runs: $runs"
exit $((missed + (status != 0)))
