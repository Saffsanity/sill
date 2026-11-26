#!/bin/zsh
# TEST ONLY. Probe P2c (2026-11-23; docs/steps/2026-11-18-virtual-desktop-2b.md, fourth part): what P2b left open about
# turning Sill's Desktop display in place: the turn in two steps (applySettings: with the turn alone, then a CoreGraphics
# switch to the usable 2x mode), what applyModes sends against creation, and a display made with the room alone. Noah ran
# it on his Mac (macOS 27.2.1) on 2026-11-23 at 16:53; its findings decided how VirtualDesktopSize.InPlace turns the Virtual
# Desktop. probe3.swift is the probe as he ran it (sha256 3196f593…76a8), compiled with ../VirtualDisplay-b7339612.swift
# with VirtualDisplay-probe.patch applied (two PROBE ONLY changes: init's `probeBackingAtLeast`, and an extension at the
# end that reads type encodings and holds the live object for read-backs), which gives the file he ran (sha256
# 1d15bdfa…2f11); probe3.swift's header and steps say what each case does and every safety.
#
# Noah, from Terminal.app, with Sill quit and no device connected, one line (about 25 s, never more than 44 s):
#   zsh Scripts/display-modes-probe/p2c/run.sh
# runs four cases, one display at a time, each removed before the next:
#   1. the iPad mini lying down, 1218x800 at 60 Hz, made with the room both ways (as P2b): steps 1 and 2;
#   2. the iPhone 15 Pro lying down, 1496x800 at 120 Hz, made the same way: steps 1 and 2;
#   3. and 4. the same two, made with the room alone and the same square backing: step 4.
# Everything it prints also goes to .build/display-modes-probe/p2c/out-<date>-<time>.txt.
#
#   run.sh WxH [HZ] [--room-alone]    one case at that room and rate
#   run.sh --dry-run [WxH] [HZ]       the plan only: looks up the private API, makes no display (what an agent runs)
#   run.sh --build                    builds the probe (an agent: through the heavy lock), then stops
# The probe's step 3 (the private `rotation` setting) is never run: its units cannot be read from macOS, and a value of
# the wrong units could reach the window server; `--quarter-turn` is refused here.
# Built into .build/display-modes-probe/p2c/probe3 (swiftc -Onone, as Noah's), and built again only when that file is
# missing: by Noah's first real run if no agent has built it, never by --dry-run. Refused without a terminal (an agent's
# shell), and while Sill.app, the bare SillMenuBar or a SillHost runs (one could be streaming, and Sill would take the
# probe's display for its own Desktop display). Each case stops itself at its limit (20 s, less when what is left of the
# run's 44 s is less) and is killed two seconds later (its display goes with its process); a case that no longer fits in
# the 44 s is skipped. Ctrl-C stops it, and the probe removes its display. It links no VideoToolbox or ScreenCaptureKit.
emulate -L zsh
setopt no_unset
typeset -F SECONDS
HERE=${0:A:h}
ROOT=${0:A:h:h:h:h}
OUT=$ROOT/.build/display-modes-probe/p2c
BIN=$OUT/probe3
CASE_LIMIT=20
RUN_LIMIT=44
# The sources as Noah ran them on 2026-11-23, and their sha256 (the VirtualDisplay.swift once the patch is applied).
PROBE_SHA=3196f5930a372d607032eb2352162070971542f9b82359348d0b292406be76a8
BASE_SHA=ad031531605b17800fdf1444415d9f7c32d083994ed25f5a8fd05ca2710bdbf8
PATCHED_SHA=1d15bdfac6f971084880e62944fdfe6bb50eca59feb8ff655afc505e21932f11

say() { print -r -- "$1"; [[ -n ${LOG:-} ]] && print -r -- "$1" >> "$LOG" }
sha() { shasum -a 256 "$1" | cut -d' ' -f1 }

build() {
  print -r -- "run.sh: building the probe, into $BIN (swiftc, under a minute)"
  mkdir -p "$OUT"
  local T=$OUT/tmp-src
  rm -rf "$T" && mkdir -p "$T" || return 1
  [[ $(sha "$HERE/../VirtualDisplay-b7339612.swift") == $BASE_SHA ]] \
    || print -r -- "run.sh: NOTE VirtualDisplay-b7339612.swift is not the file P2c was made from (sha256 ${BASE_SHA[1,8]}…)"
  if ! /usr/bin/patch -s -o "$T/VirtualDisplay.swift" "$HERE/../VirtualDisplay-b7339612.swift" "$HERE/VirtualDisplay-probe.patch"; then
    print -r -- "run.sh: the probe's patch did not apply"
    rm -rf "$T"
    return 1
  fi
  [[ $(sha "$T/VirtualDisplay.swift") == $PATCHED_SHA ]] \
    || print -r -- "run.sh: NOTE the patched VirtualDisplay.swift is not the one Noah ran on 2026-11-23 (sha256 ${PATCHED_SHA[1,8]}…)"
  [[ $(sha "$HERE/probe3.swift") == $PROBE_SHA ]] \
    || print -r -- "run.sh: NOTE probe3.swift is not the source Noah ran on 2026-11-23 (sha256 ${PROBE_SHA[1,8]}…)"
  cp "$HERE/probe3.swift" "$T/main.swift" || return 1
  if ! swiftc -swift-version 5 -Onone "$T/VirtualDisplay.swift" "$T/main.swift" -o "$BIN.new"; then
    rm -rf "$T" "$BIN.new"
    return 1
  fi
  rm -rf "$T"
  mv -f "$BIN.new" "$BIN"
  if otool -L "$BIN" | /usr/bin/grep -Eq 'VideoToolbox|ScreenCaptureKit'; then
    print -r -- "REFUSED: the probe links VideoToolbox or ScreenCaptureKit"
    rm -f "$BIN"
    return 1
  fi
  print -r -- "run.sh: built $BIN"
}

dry=0
rebuild=0
args=()
while (( $# > 0 )); do
  case $1 in
    --dry-run) dry=1 ;;
    --build) rebuild=1 ;;
    --make) ;;   # the old probe's word for the real run: the real run is the default here
    --quarter-turn)
      print -r -- "REFUSED: --quarter-turn. The rotation setting's units cannot be read from macOS, and it is never used."
      exit 2 ;;
    *) args+=("$1") ;;
  esac
  shift
done

linked_ok() {
  if otool -L "$BIN" | /usr/bin/grep -Eq 'VideoToolbox|ScreenCaptureKit'; then
    print -r -- "REFUSED: the probe links VideoToolbox or ScreenCaptureKit"
    return 1
  fi
}

if (( rebuild )); then build; exit $?; fi
if (( dry )); then
  # An agent's run: never a compile here, and no display made.
  if [[ ! -x $BIN ]]; then
    print -r -- "run.sh: no build yet. Build it first: zsh $HERE/run.sh --build (an agent: through the heavy lock)"
    exit 1
  fi
  linked_ok || exit 1
  "$BIN" "${args[@]}"
  exit $?
fi

# The real run: Noah's alone, refused before anything is built or made.
if [[ ! -t 0 || ! -t 1 ]]; then
  print -r -- "REFUSED: no terminal. The real run makes a display on this Mac, which only Noah does, from Terminal.app. An agent runs: zsh $HERE/run.sh --dry-run"
  exit 2
fi
for p in Sill SillMenuBar SillHost; do
  if pgrep -x "$p" >/dev/null; then
    print -r -- "REFUSED: $p is running. Quit it first: the probe runs on a Mac at rest, with nothing streaming."
    exit 2
  fi
done
if [[ ! -x $BIN ]]; then build || { print -r -- "run.sh: the build failed; nothing was made"; exit 1 }; fi
linked_ok || exit 1

mkdir -p "$OUT"
LOG=$OUT/out-$(date +%Y%m%d-%H%M%S).txt
: >> "$LOG"
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

RUN_START=$SECONDS

# One case: the probe in the background, so this script can stop it at its limit; its own limit comes first. $1 is the
# least the case needs, in seconds: a case that no longer fits in what is left of the run's limit is skipped.
run_case() {
  local -i need=$1
  shift
  local -i left=$(( RUN_LIMIT - (SECONDS - RUN_START) ))
  local -i lim=$(( left - 2 < CASE_LIMIT ? left - 2 : CASE_LIMIT ))
  if (( lim < need )); then
    say "  skipped: $left s left of the run's $RUN_LIMIT s, and this case needs $need s or more"
    return 0
  fi
  "$BIN" --make --log "$LOG" --limit "$lim" "$@" &
  pid=$!
  local me=$pid start=$SECONDS code
  while kill -0 $me 2>/dev/null; do
    if (( SECONDS - start > lim + 2 )); then
      stop_probe
      say "run.sh: the probe passed its limit of $(( lim + 2 )) s and was stopped; its display went with its process."
      break
    fi
    sleep 0.2
  done
  wait $me 2>/dev/null
  code=$?
  pid=0
  return $code
}

say "Probe P2c, $(date '+%Y-%m-%d %H:%M:%S'), macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model); Sill not running; the output: $LOG"
if (( ${#args} == 0 )); then
  say ""
  say "Case 1 of 4: the iPad mini lying down, made as P2b made it (steps 1 to 3)"
  run_case 10 1218x800 60 --label "iPad mini 1218x800 at 60 Hz"
  say "  (exit $?)"
  sleep 0.5
  say ""
  say "Case 2 of 4: the iPhone 15 Pro lying down, made as P2b made it (steps 1 to 3)"
  run_case 10 1496x800 120 --label "iPhone 1496x800 at 120 Hz"
  say "  (exit $?)"
  sleep 0.5
  say ""
  say "Case 3 of 4: the iPad mini lying down, made with the room alone (step 4)"
  run_case 6 1218x800 60 --room-alone --label "iPad mini 1218x800 at 60 Hz, made with the room alone"
  say "  (exit $?)"
  sleep 0.5
  say ""
  say "Case 4 of 4: the iPhone 15 Pro lying down, made with the room alone (step 4)"
  run_case 6 1496x800 120 --room-alone --label "iPhone 1496x800 at 120 Hz, made with the room alone"
  say "  (exit $?)"
else
  run_case 6 "${args[@]}"
  say "  (exit $?)"
fi

verdicts=( "${(@f)$(/usr/bin/grep '^P2c ' "$LOG")}" )
say ""
say "The verdict lines together (each also above):"
for v in "${verdicts[@]}"; do say "$v"; done
integer took=$(( SECONDS - RUN_START ))
say ""
say "The whole run took $took s. All of it is in $LOG."
