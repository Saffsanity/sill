#!/bin/zsh
# Hardware verification of this tree's encoder against a base commit's. USES THE MAC'S HARDWARE
# VIDEO ENCODER. Before every run it checks that no device is connected to this Mac's Sill.app
# (no-device.sh: its log's last idle/"Client left" line newer than its last "Client connected", and
# no "[1s] … · N client" stats line in the last 60 s) and skips the run if one is; a watcher stops a
# run if a device connects while it runs. One run at a time, each under 60 s. Before each run it
# also says whether another process is encoding (engine-free.sh, the kernel's AppleAVE2 HeartBeat
# of the last 12 s): a shared engine is a different experiment (the Claude app's iOS Simulator panel
# encodes its screen at priority 60), and the Retina Desktop's slow state needs the engine to
# itself (CLAUDE.md, "The 33 fps plateau").
#
# usage: Scripts/encoder-check/verify-hardware.sh [parity] [stream] [harness] [probe] [keyframe]   (none: all five)
#   parity   SillHost --synthetic idle 35 s, base then new: new's stdout masked and sorted must
#            equal base's
#   stream   SillHost --synthetic + Scripts/sillclient.py picking the Desktop (3024×1898 @ 60 fps)
#            30 s, new then two: enc.out / enc.mailboxDrop per second, AppleAVE2 HeartBeat times
#   harness  the real HEVCEncoder at 3024×1964, 40 Mbps, new then two: 3 s at 60 fps, 6 s of one
#            frame every 0.3 s (to bring on the slow state), 20 s at 60 fps; per second enc.out,
#            mailboxDrop, capture-to-output latency; HeartBeat per-frame times
#   probe    EncoderProbe.throughput, new then two, 3 times at 3024×1904 and at 1512×948
#   keyframe base then new, 6 sessions at 3024×1964: 12 frames at 60 fps, a keyframe asked for 5,
#            20 or 40 ms after the last (a device joining just after a repaint), then still for
#            0.5 s: base answers none (the next repaint would carry it), new every one, 60 ms
#            and a turnaround after the last frame (HEVCEncoder.keyframeCheck)
# The builds compared: base is ENCODER_CHECK_BASE (default 4fe37d4, encoder-recovery, one frame
# inside), from git archive under .build/encoder-check/; new is this working tree as it ships (one
# inside); two is this tree with SILL_TEST_ENCODER_IN_FLIGHT=2 (two inside on the hardware, the
# plateau experiment). ENCODER_CHECK_VARIANTS="base new two" runs those in every step but parity.
# It builds everything first (building never touches the encoder). Results:
# .build/encoder-check/hw/*.txt, and a summary on stdout.
set -u
HERE=${0:A:h}
ROOT=${HERE:h:h}
OUT=$ROOT/.build/encoder-check
HW=$OUT/hw
BASE=${ENCODER_CHECK_BASE:-4fe37d4}
CLIENT=$ROOT/Scripts/sillclient.py
SILLLOG=${SILL_LOG_DIR:-$HOME/Library/Logs/Sill}/Sill.log
mkdir -p $HW
steps=("$@"); (( ${#steps} )) || steps=(parity stream harness probe keyframe)

# The builds each step compares: the SillHost binary, the harness binary, the environment.
typeset -A HOST HARNESS ENVV
HOST[base]=$OUT/tree-$BASE/.build/release/SillHost; HARNESS[base]=$OUT/harness-base; ENVV[base]=""
HOST[new]=$ROOT/.build/release/SillHost;            HARNESS[new]=$OUT/harness-new;  ENVV[new]=""
HOST[two]=$ROOT/.build/release/SillHost;            HARNESS[two]=$OUT/harness-new;  ENVV[two]="SILL_TEST_ENCODER_IN_FLIGHT=2"
typeset -A VARIANTS
VARIANTS[parity]="base new"
VARIANTS[stream]=${ENCODER_CHECK_VARIANTS:-"new two"}
VARIANTS[harness]=${ENCODER_CHECK_VARIANTS:-"new two"}
VARIANTS[probe]=${ENCODER_CHECK_VARIANTS:-"new two"}
VARIANTS[keyframe]=${ENCODER_CHECK_VARIANTS:-"base new"}

echo "building (never touches the encoder): this tree, $BASE from git archive, the harness"
{
  (cd $ROOT && swift build -c release --product SillHost) &&
  $HERE/harness/build.sh &&
  (cd $OUT/tree-$BASE && swift build -c release --product SillHost)
} > $HW/build.log 2>&1 || { echo "build failed: see $HW/build.log"; exit 1 }

guard() {   # NAME: 0 when no device is connected to Sill.app
  if $HERE/no-device.sh > $HW/$1.guard.txt 2>&1; then
    $HERE/engine-free.sh || { echo "note: $1 shares the encoder with:"; sed 's/^/    /' $OUT/engine-busy.txt | tail -1; }
    return 0
  fi
  echo "SKIP $1: a device is connected to Sill.app"; sed 's/^/    /' $HW/$1.guard.txt; return 1
}
stamp() { date "+%Y-%m-%d %H:%M:%S" }
ave() {     # NAME FROM TO: the AppleAVE2 lines of that window, parsed
  /usr/bin/log show --info --debug --style compact --start "$2" --end "$3" --predicate 'sender == "AppleAVE2"' > $HW/$1.ave.txt 2>/dev/null
  python3 $HERE/hbparse.py $HW/$1.ave.txt > $HW/$1.hb.txt
}
# Watches Sill.log while the given pids live; stops them if a device connects. By the lines'
# timestamps, not by bytes appended: two Sill.app processes (a relaunch) write the file at their
# own offsets, so a new line can land in the middle of it.
watch_pids() {
  local since=$(date "+%Y-%m-%d %H:%M:%S")
  while true; do
    local alive=0
    for p in "$@"; do kill -0 $p 2>/dev/null && alive=1; done
    (( alive )) || return 0
    if grep -hE "Client connected|Remote client connected" $SILLLOG 2>/dev/null | awk -v s="$since" 'substr($0, 1, 19) >= s { f = 1 } END { exit !f }'; then
      echo "ABORT: a device connected to Sill.app during the run; stopping it"
      for p in "$@"; do kill -INT $p 2>/dev/null; done; sleep 1; for p in "$@"; do kill -9 $p 2>/dev/null; done
      return 1
    fi
    sleep 0.5
  done
}
port_of() { lsof -nP -iTCP -sTCP:LISTEN -a -p $1 2>/dev/null | awk 'NR>1 {n=split($9,a,":"); print a[n]; exit}' }
stats_summary() {   # FILE: mean enc.out and enc.mailboxDrop over the [1s] lines with a client, first 4 s left out
  python3 - "$1" <<'PY'
import re, sys
rows = [l for l in open(sys.argv[1]) if '[1s]' in l and '· 1 client' in l]
rows = rows[4:-1]
def get(k, l):
    m = re.search(r'\b' + re.escape(k) + r' (\d+)', l); return int(m.group(1)) if m else 0
if not rows: print('    no stats lines'); sys.exit()
for k in ('cap.complete', 'enc.out', 'enc.mailboxDrop', 'enc.error', 'net.sent'):
    v = [get(k, l) for l in rows]
    print(f'    {k:16} mean {sum(v)/len(v):5.1f}  min {min(v):3d}  max {max(v):3d}  ({len(v)} s)')
PY
}

for step in $steps; do
case $step in
parity)
  names=(${=VARIANTS[parity]})
  for name in $names; do
    guard parity-$name || continue
    env ${=ENVV[$name]} ${HOST[$name]} --synthetic > $HW/parity-$name.out 2>&1 &
    hp=$!
    ( sleep 35; kill -INT $hp 2>/dev/null; sleep 1; kill -9 $hp 2>/dev/null ) &
    killer=$!
    watch_pids $hp || { kill $killer 2>/dev/null; echo "    parity-$name aborted"; continue }
    wait $killer 2>/dev/null
    sed -E 's/[0-9]+/N/g' $HW/parity-$name.out | sort > $HW/parity-$name.masked
    sleep 2
  done
  a=$HW/parity-${names[1]}.masked
  for name in ${names[2,-1]}; do
    b=$HW/parity-$name.masked
    [[ -s $a && -s $b ]] || continue
    if diff $a $b > $HW/parity-$name.diff; then
      echo "parity: $name's idle stdout masked and sorted IDENTICAL to ${names[1]}'s ($(wc -l < $HW/parity-$name.out | tr -d ' ') lines)"
    else
      echo "parity: $name DIFFERENT from ${names[1]}"; sed 's/^/    /' $HW/parity-$name.diff
    fi
  done
  ;;
stream)
  for name in ${=VARIANTS[stream]}; do
    guard stream-$name || continue
    t0=$(stamp)
    env ${=ENVV[$name]} ${HOST[$name]} --synthetic > $HW/stream-$name.host.txt 2>&1 &
    hp=$!
    port=""; for i in {1..100}; do port=$(port_of $hp); [[ -n $port ]] && break; sleep 0.1; done
    python3 -u $CLIENT $port 30 desktop --stats > $HW/stream-$name.client.txt 2>&1 &
    cp=$!
    watch_pids $cp || { kill -INT $hp 2>/dev/null; sleep 1; kill -9 $hp 2>/dev/null; echo "    stream-$name aborted"; continue }
    kill -INT $hp 2>/dev/null; sleep 1; kill -9 $hp 2>/dev/null
    t1=$(stamp)
    ave stream-$name "$t0" "$t1"
    echo "stream $name (SillHost --synthetic, 3024×1898 @ 60 fps, the CLI's 15 Mbps, 30 s):"
    stats_summary $HW/stream-$name.host.txt
    grep -E "fps=|frames|C/F" $HW/stream-$name.hb.txt | grep -v first | sed 's/^/    AVE /' | tail -6
    sleep 3
  done
  ;;
harness)
  for name in ${=VARIANTS[harness]}; do
    guard harness-$name || continue
    t0=$(stamp)
    env ${=ENVV[$name]} ${HARNESS[$name]} 3024 1964 40000000 dense:3 sparse:6@0.3 dense:20 > $HW/harness-$name.txt 2>&1 &
    p=$!
    watch_pids $p || { echo "    harness-$name aborted"; continue }
    t1=$(stamp)
    ave harness-$name "$t0" "$t1"
    echo "harness $name (3024×1964, 40 Mbps: dense 3 s, one frame every 0.3 s for 6 s, dense 20 s):"
    grep -E "^t=|^phase|^overlapping|HUNG|^TEST" $HW/harness-$name.txt | sed 's/^/    /'
    grep -vE "first beat|opened: 256" $HW/harness-$name.hb.txt | sed 's/^/    AVE /'
    sleep 3
  done
  ;;
probe)
  for name in ${=VARIANTS[probe]}; do
    guard probe-$name || continue
    : > $HW/probe-$name.txt
    for size in "3024 1904" "1512 948"; do
      env ${=ENVV[$name]} ${HARNESS[$name]} probe ${=size} 3 >> $HW/probe-$name.txt 2>&1 &
      p=$!
      watch_pids $p || { echo "    probe-$name aborted"; break }
    done
    echo "probe $name (EncoderProbe.throughput):"; sed 's/^/    /' $HW/probe-$name.txt
    sleep 2
  done
  ;;
keyframe)
  for name in ${=VARIANTS[keyframe]}; do
    guard keyframe-$name || continue
    env ${=ENVV[$name]} ${HARNESS[$name]} keyframe 3024 1964 40000000 6 > $HW/keyframe-$name.txt 2>&1 &
    p=$!
    watch_pids $p || { echo "    keyframe-$name aborted"; continue }
    echo "keyframe $name (a keyframe asked for just after a burst's last frame, then still; 3024×1964, 40 Mbps):"
    sed 's/^/    /' $HW/keyframe-$name.txt
    sleep 2
  done
  ;;
*) echo "unknown step $step" ;;
esac
done
