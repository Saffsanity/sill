#!/bin/zsh
# TEST ONLY. Probe P4 (2026-11-26; docs/steps/2026-11-18-virtual-desktop-2b.md, "P3's result, and probe P4"): where the
# line runs between the Virtual Desktops macOS keeps at 2x and those it runs at 1x. P3 found that macOS keeps an iPhone
# 15 Pro's Full Screen sizes (589×1189, 1101×589) and not the two with its controls showing (1077×448, 800×499). This
# makes "Sill Probe" at 589×1189 and follows it in place through two ladders of sizes, one for each of those shapes, and
# a few sizes that tell the shorter side from the height and from the pixels; then makes four sizes as they are, two of
# them at 60 Hz (probe-floor.swift's header has every size). Each size ends with a verdict line, "P4 … kept at 2x:
# yes|no (…)", and the last two lines name the smallest size kept of each shape.
#
# Noah, from Terminal.app, with Sill quit and no device connected, one line (about a minute and a half, the build
# included; never more than 160 s):
#   zsh ~/Downloads/wt-vd-2b/Scripts/display-modes-probe/p4/run.sh
# Everything it prints also goes to .build/display-modes-probe/p4/out-<date>-<time>.txt in the worktree.
#
#   run.sh --case N       one case of the five
#   run.sh --dry-run      the plan only: looks up the private API, makes no display (what an agent runs)
#   run.sh --build        builds the probe (an agent: through the heavy lock), then stops
# Built into .build/display-modes-probe/p4/probe-floor (swiftc -Onone: Sources/SillHost/VirtualDisplay.swift and
# probe-floor.swift alone, no VideoToolbox, no ScreenCaptureKit), and built again when either source is newer. Refused
# without a terminal (an agent's shell) and while Sill.app, the bare SillMenuBar or a SillHost runs (one could be
# streaming, and Sill would take the probe's display for its own Desktop display). This script stops a run that is still
# going 152 s after its start (its display goes with its process); Ctrl-C stops it, and its display goes with it.
emulate -L zsh
setopt no_unset
typeset -F SECONDS
HERE=${0:A:h}
ROOT=${0:A:h:h:h:h}
OUT=$ROOT/.build/display-modes-probe/p4
BIN=$OUT/probe-floor
SRC=$ROOT/Sources/SillHost/VirtualDisplay.swift
RUN_LIMIT=150

build() {
  print -r -- "run.sh: building the probe, into $BIN (swiftc, under a minute)"
  mkdir -p "$OUT"
  # swiftc takes top-level code from a file named main.swift alone (beside another file, under any other name it is
  # "expressions are not allowed at the top level"), so the probe is compiled as a copy of that name, as P3's.
  local T=$OUT/tmp-src
  rm -rf "$T" && mkdir -p "$T" || return 1
  cp "$HERE/probe-floor.swift" "$T/main.swift" || return 1
  if ! swiftc -swift-version 5 -Onone "$SRC" "$T/main.swift" -o "$BIN.new"; then
    rm -rf "$T" "$BIN.new"
    return 1
  fi
  rm -rf "$T"
  mv -f "$BIN.new" "$BIN"
  linked_ok || return 1
  print -r -- "run.sh: built $BIN"
}

linked_ok() {
  if otool -L "$BIN" | /usr/bin/grep -Eq 'VideoToolbox|ScreenCaptureKit'; then
    print -r -- "REFUSED: the probe links VideoToolbox or ScreenCaptureKit"
    rm -f "$BIN"
    return 1
  fi
}

stale() { [[ ! -x $BIN || $SRC -nt $BIN || $HERE/probe-floor.swift -nt $BIN ]] }

dry=0
rebuild=0
args=()
while (( $# > 0 )); do
  case $1 in
    --dry-run) dry=1 ;;
    --build) rebuild=1 ;;
    --case) shift; args+=(--case "${1:-0}") ;;
    *) print -r -- "run.sh: unknown argument $1 (it takes --case N, --dry-run, --build)"; exit 2 ;;
  esac
  shift
done

if (( rebuild )); then build; exit $?; fi
if (( dry )); then
  # An agent's run: never a compile here, and no display made.
  if stale; then
    print -r -- "run.sh: no current build. Build it first: zsh $HERE/run.sh --build (an agent: through the heavy lock)"
    exit 1
  fi
  linked_ok || exit 1
  "$BIN" --dry-run "${args[@]}"
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
if stale; then build || { print -r -- "run.sh: the build failed; nothing was made"; exit 1 }; fi
linked_ok || exit 1

mkdir -p "$OUT"
LOG=$OUT/out-$(date +%Y%m%d-%H%M%S).txt
: >> "$LOG"
print -r -- "Probe P4, $(date '+%Y-%m-%d %H:%M:%S'), macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model); Sill not running; the output: $LOG" | tee -a "$LOG"
"$BIN" --make --log "$LOG" "${args[@]}" &
pid=$!
trap 'kill -TERM $pid 2>/dev/null; print -r -- "run.sh: stopped; the probe'"'"'s display went with its process."; exit 130' INT TERM HUP
start=$SECONDS
while kill -0 $pid 2>/dev/null; do
  if (( SECONDS - start > RUN_LIMIT + 2 )); then
    kill -TERM $pid 2>/dev/null; sleep 1; kill -KILL $pid 2>/dev/null
    print -r -- "run.sh: the probe passed its limit of $RUN_LIMIT s and was stopped; its display went with its process." | tee -a "$LOG"
    break
  fi
  sleep 0.2
done
wait $pid 2>/dev/null
code=$?
print -r -- ""
print -r -- "The verdict lines together (each also above):"
/usr/bin/grep '^P4 ' "$LOG"
print -r -- ""
print -r -- "The whole run took $(( SECONDS - start )) s (exit $code). All of it is in $LOG."
