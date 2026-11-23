#!/bin/zsh
# TEST ONLY. Probe P2b (2026-11-23; docs/steps/2026-11-18-virtual-desktop-2b.md, fourth part): can Sill's Desktop display
# take a device's turn, or a second device's shape, in place, by applySettings: on the live display? Noah ran it on his Mac
# (macOS 27.2.1) on 2026-11-23 at 16:23; its findings decided VirtualDesktopSize.followWay. probe2.swift is the probe as he
# ran it (sha256 20e8ece5…c7ba), compiled with ../VirtualDisplay-b7339612.swift, Sources/SillHost/VirtualDisplay.swift as
# it was then (sha256 ad031531…bdbf8); probe2.swift's header and its steps say what each case does and every safety.
#
# Noah, from Terminal.app, with Sill quit and no device connected, one line (about 30 s):
#   zsh Scripts/display-modes-probe/p2b/run.sh
# runs both cases, one display at a time, each removed before the next:
#   1. the iPad mini lying down: 1218x800 at 60 Hz (the Virtual Desktop's size for its 1133x744), the other shape the
#      iPhone's 1496x800;
#   2. the iPhone 15 Pro lying down: 1496x800 at 120 Hz (for its 735x393 room), the other shape the iPad mini's 1218x800.
# Everything it prints also goes to .build/display-modes-probe/p2b/out-<date>-<time>.txt.
#
#   run.sh WxH [HZ] [--other WxH]    one case at that room and rate
#   run.sh --dry-run [WxH] [HZ]       the plan only: looks up the private API, makes nothing (what an agent runs)
#   run.sh --build                    builds the probe (an agent: through the heavy lock), then stops
# Built into .build/display-modes-probe/p2b/probe2 (swiftc -Onone, as Noah's: the probe's timings are macOS's, not its
# own), and built again only when that file is missing: by Noah's first real run if no agent has built it, never by
# --dry-run. Refused without a terminal (an agent's shell), and while Sill.app, the bare SillMenuBar or a SillHost runs
# (one could be streaming, and Sill would take the probe's display for its own Desktop display). Each case is stopped at
# 26 s (its display goes with its process); Ctrl-C stops it, and the probe removes its display first. It links no
# VideoToolbox or ScreenCaptureKit (checked).
emulate -L zsh
setopt no_unset
HERE=${0:A:h}
ROOT=${0:A:h:h:h:h}
OUT=$ROOT/.build/display-modes-probe/p2b
BIN=$OUT/probe2
LIMIT=24
# The sources as Noah ran them on 2026-11-23, and their sha256.
SRC_FILES=($HERE/../VirtualDisplay-b7339612.swift $HERE/probe2.swift)
SRC_SHAS=(ad031531605b17800fdf1444415d9f7c32d083994ed25f5a8fd05ca2710bdbf8 20e8ece51c92059a4ed8cd3c4e1af82f5245535cccd5d52d0ff4ed0750bcc7ba)

say() { print -r -- "$1"; [[ -n ${LOG:-} ]] && print -r -- "$1" >> $LOG }

build() {
  print -r -- "run.sh: building the probe, into $BIN (swiftc, under a minute)"
  mkdir -p $OUT
  local i
  for i in {1..${#SRC_FILES}}; do
    [[ $(shasum -a 256 "$SRC_FILES[$i]" | cut -d' ' -f1) == $SRC_SHAS[$i] ]] \
      || print -r -- "run.sh: NOTE ${SRC_FILES[$i]:t} is not the source Noah ran on 2026-11-23 (sha256 ${SRC_SHAS[$i][1,8]}…)"
  done
  local T=$OUT/tmp-src
  rm -rf $T && mkdir -p $T || return 1
  cp $HERE/../VirtualDisplay-b7339612.swift $T/VirtualDisplay.swift && cp $HERE/probe2.swift $T/main.swift || return 1
  if ! swiftc -swift-version 5 -Onone $T/VirtualDisplay.swift $T/main.swift -o $BIN.new; then
    rm -rf $T $BIN.new
    return 1
  fi
  rm -rf $T
  mv -f $BIN.new $BIN
  if otool -L $BIN | /usr/bin/grep -Eq 'VideoToolbox|ScreenCaptureKit'; then
    print -r -- "REFUSED: the probe links VideoToolbox or ScreenCaptureKit"
    rm -f $BIN
    return 1
  fi
  print -r -- "run.sh: built $BIN"
}

dry=0
rebuild=0
args=()
for a in "$@"; do
  case $a in
    --dry-run) dry=1 ;;
    --build) rebuild=1 ;;
    --make) ;;   # the old probe's word for the real run: the real run is the default here
    *) args+=("$a") ;;
  esac
done

linked_ok() {
  if otool -L $BIN | /usr/bin/grep -Eq 'VideoToolbox|ScreenCaptureKit'; then
    print -r -- "REFUSED: the probe links VideoToolbox or ScreenCaptureKit"
    return 1
  fi
}

if (( rebuild )); then build; exit $?; fi
if (( dry )); then
  # An agent's run: never a compile here (an agent's compiles go through the heavy lock), and nothing made.
  if [[ ! -x $BIN ]]; then
    print -r -- "run.sh: no build yet. Build it first: zsh $HERE/run.sh --build (an agent: through the heavy lock)"
    exit 1
  fi
  linked_ok || exit 1
  $BIN "${args[@]}"
  exit $?
fi

# The real run: Noah's alone, refused before anything is built or made.
if [[ ! -t 0 || ! -t 1 ]]; then
  print -r -- "REFUSED: no terminal. The real run makes a display on this Mac, which only Noah does, from Terminal.app. An agent runs: zsh $HERE/run.sh --dry-run"
  exit 2
fi
for p in Sill SillMenuBar SillHost; do
  if pgrep -x $p >/dev/null; then
    print -r -- "REFUSED: $p is running. Quit it first: the probe runs on a Mac at rest, with nothing streaming."
    exit 2
  fi
done
if [[ ! -x $BIN ]]; then build || { print -r -- "run.sh: the build failed; nothing was made"; exit 1 }; fi
linked_ok || exit 1

mkdir -p $OUT
LOG=$OUT/out-$(date +%Y%m%d-%H%M%S).txt
: >> $LOG
pid=0

stop_probe() {
  if (( pid > 0 )) && kill -0 $pid 2>/dev/null; then
    kill -TERM $pid 2>/dev/null
    local i
    for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
    kill -KILL $pid 2>/dev/null
  fi
  pid=0
}
trap 'stop_probe; say "run.sh: stopped; the probe removes its display, which goes with its process in any case."; exit 130' INT TERM HUP

# One case: the probe in the background, so this script can stop it at the limit; its own limit comes first.
run_case() {
  $BIN --make --log $LOG --limit $LIMIT "$@" &
  pid=$!
  local me=$pid start=$SECONDS code
  while kill -0 $me 2>/dev/null; do
    if (( SECONDS - start > LIMIT + 2 )); then
      stop_probe
      say "run.sh: the probe passed its limit of $(( LIMIT + 2 )) s and was stopped; its display went with its process."
      break
    fi
    sleep 0.2
  done
  wait $me 2>/dev/null
  code=$?
  pid=0
  return $code
}

say "Probe P2b, $(date '+%Y-%m-%d %H:%M:%S'), macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model); Sill not running; the output: $LOG"
if (( ${#args} == 0 )); then
  say ""
  say "Case 1 of 2: the iPad mini lying down"
  run_case 1218x800 60 --other 1496x800 --label "iPad mini 1218x800 at 60 Hz"
  say "  (exit $?)"
  sleep 1
  say ""
  say "Case 2 of 2: the iPhone 15 Pro lying down"
  run_case 1496x800 120 --other 1218x800 --label "iPhone 1496x800 at 120 Hz"
  say "  (exit $?)"
else
  run_case "${args[@]}"
  say "  (exit $?)"
fi

verdicts=( "${(@f)$(/usr/bin/grep '^P2b ' $LOG)}" )
say ""
say "The verdict lines together (each also above):"
for v in $verdicts; do say "$v"; done
say ""
say "All of it is in $LOG."
