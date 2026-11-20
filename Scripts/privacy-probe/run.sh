#!/bin/zsh
# TEST ONLY. G0, the privacy probe (docs/privacy-mode-plan.md, "Tests"; issue #133): what Sill's black windows would do
# on this Mac, measured before darkening is built on them. For Noah to run himself in Terminal.app, about 15 minutes:
# it darkens this Mac's screens in spells of at most 10 s, each under a hard 12 s kill from this shell, and asks after
# each what he saw. Never run by an agent (CLAUDE.md: no agent darkens Noah's screens).
#   1. Do covered windows keep drawing? Its own test window (window.swift: a timer's 60 draws a second and a display
#      link), a Safari window playing a video and an Electron app's window, captured by ScreenCaptureKit, with the
#      Desktop as Sill takes it (the black windows left out), uncovered, then under each candidate: S1 opaque at
#      .screenSaver (#184's), S2 not opaque at .screenSaver, S3 opaque at the shielding level, S4 opaque at 1500.
#   2. What shows in front of them: the window server's list every quarter second while Noah locks the Mac (⌃⌘Q), a
#      notification comes, he presses the volume keys, ⌘Space, F3 (Mission Control) and ⌥⌘⎋, and moves the pointer.
#   3. kill -9 while black, and a frozen probe (kill -STOP, then kill -9): the screen back at once after each kill.
#   4. A posted event with Sill's tag and one without, and Noah's own: whether NSEvent's global monitor tells them apart.
#   5. Black on every screen for 10 s, with whatever Noah sets up first (Night Shift, True Tone, an HDR video, a
#      monitor, Sidecar).
# usage: Scripts/privacy-probe/run.sh [REPORT]      (default .build/privacy-probe/report.txt; appended to)
#        Scripts/privacy-probe/run.sh --build-only  (compiles, runs nothing)
# Builds under .build/privacy-probe/: the test window's app (window.swift in a bundle of its own,
# me.saffer.sill.privacyprobe, never activated) and the probe (probe.swift: AppKit and ScreenCaptureKit, no encoder;
# refused if either links VideoToolbox). Needs Screen Recording and Accessibility for the app this runs in, an unlocked
# screen, and no device connected to Sill (quitting Sill is simplest). Ctrl-C ends it at any time, the screen back at once.
set -u
ROOT=${0:A:h:h:h}
HERE=${0:A:h}
OUT=$ROOT/.build/privacy-probe
APP=$OUT/Window.app
PROBE=$OUT/probe
WINDOW=$APP/Contents/MacOS/window
mkdir -p $APP/Contents/MacOS
cp $HERE/Info.plist $APP/Contents/Info.plist
swiftc -O $HERE/window.swift -o $WINDOW || exit 1
codesign -s - --force $APP 2>/dev/null || exit 1
swiftc -O $HERE/probe.swift -o $PROBE || exit 1
for b in $PROBE $WINDOW; do
  if otool -L $b | grep -q VideoToolbox; then print "REFUSED: $b links VideoToolbox"; exit 1; fi
done
if [[ ${1:-} == --build-only ]]; then print "Built $PROBE and $APP; nothing run."; exit 0; fi

REPORT=${1:-$OUT/report.txt}
mkdir -p ${REPORT:h}
exec > >(tee -a $REPORT) 2>&1

CUR=0
WIN=0
GUARD=0
cleanup() {
  (( CUR )) && kill -9 $CUR 2>/dev/null
  (( WIN )) && kill $WIN 2>/dev/null
  (( GUARD )) && { pkill -P $GUARD sleep 2>/dev/null; kill $GUARD 2>/dev/null }
}
trap 'cleanup; print "\nStopped. The report so far: $REPORT"; exit 130' INT TERM
trap cleanup EXIT

# guard PID: kill -9 PID 12 s from now if it is still the probe; prints the guard's own pid, for `unguard`.
guard() {
  local pid=$1
  ( trap - INT TERM EXIT
    sleep 12 & wait $!
    [[ $(ps -p $pid -o comm= 2>/dev/null) == *probe* ]] && kill -9 $pid 2>/dev/null && print "(the probe was killed after 12 s)" ) &
  GUARD=$!
}
unguard() { pkill -P $GUARD sleep 2>/dev/null; kill $GUARD 2>/dev/null; GUARD=0 }

# spell CMD...: CMD in the background under a hard 12 s kill from here; its exit status.
spell() {
  "$@" &
  CUR=$!
  guard $CUR
  wait $CUR
  local st=$?
  unguard
  CUR=0
  return $st
}

# go WHAT: waits for Return before a spell.
go() { read -r "?$1 Press Return to start. " }

# ask TAG QUESTION: Noah's answer, into the report.
ask() {
  local a=""
  read -r "a?$2 "
  print "ANSWER $1: ${a:-(none)}"
}

print "=== Sill privacy probe (G0), $(date '+%Y-%m-%d %H:%M %Z') ==="
print "Every black spell lasts at most 10 s. Ctrl-C ends the probe at once, and the screen comes back."
print "The report goes to $REPORT."
print ""
$PROBE check || { print "The probe can't run yet (see above)."; exit 2 }
print ""

print "--- Step 1 of 5: do the windows under the black keep drawing? (4 spells of 4 s) ---"
print "Before you go on: play a video in Safari (a YouTube video in a window, not full screen) and open VS Code"
print "(or Slack, Discord, Notion; else Chrome) beside it, both fully on screen. A small test window will appear"
print "at the top left. Each spell: 2 s as it is, 4 s black, then it comes back."
go "When Safari's video plays and the other app is on screen,"
$WINDOW 40 60 420 260 180 > $OUT/window.log &
WIN=$!
sleep 1.5
for c in S1 S2 S3 S4; do
  spell $PROBE cover $c $OUT/window.log
  sleep 1
done
kill $WIN 2>/dev/null
WIN=0
ask step1 "Anything odd in step 1 (a spell longer than 4 s, a screen that stayed black, a flash)? Return if not:"
print ""

print "--- Step 2 of 5: what shows in front of the black? (7 spells of 9–10 s) ---"
print "Each spell shows a short instruction on the black screen. Do it, and look."
go "Spell 1: when the screen goes black, press Control-Command-Q to lock the Mac. If you see the lock screen, unlock it with Touch ID or your password. If you see only black, wait: it lifts within 10 s."
spell $PROBE levels lock --seconds 10 --text "Press Control-Command-Q now." --text "Then unlock with Touch ID or your password."
ask lock "Did the lock screen show over the black? Could you unlock while it was black? After unlocking, was the screen still black until the spell ended?"
go "Unlock the Mac if it is still locked. Spell 2: a notification will come by itself; just watch."
spell $PROBE levels notification --notify --text "Watch for a notification."
ask notification "Did the notification banner show over the black?"
go "Spell 3: press the volume keys (or the brightness keys) a few times during the spell."
spell $PROBE levels volume --text "Press the volume keys now."
ask volume "Did the volume (or brightness) indicator show over the black?"
go "Spell 4: press Command-Space, look, then press Escape."
spell $PROBE levels spotlight --text "Press Command-Space, then Escape."
ask spotlight "Did Spotlight show over the black?"
go "Spell 5: press F3 (Mission Control; or Control-Up Arrow), look, then press it again."
spell $PROBE levels missioncontrol --text "Press F3 (Mission Control), then press it again."
ask missioncontrol "What did Mission Control show: only black, your windows over the black, or something else?"
go "Spell 6: press Option-Command-Escape, look, then press Escape."
spell $PROBE levels forcequit --text "Press Option-Command-Escape, then Escape."
ask forcequit "Did the Force Quit window show over the black?"
go "Spell 7: move the mouse around."
spell $PROBE levels pointer --text "Move the mouse."
ask pointer "Did you see the pointer on the black?"
print ""

print "--- Step 3 of 5: Sill killed, or stuck, while the screen is black (2 spells) ---"
go "The screen goes black, and 3 s later the probe is killed (kill -9): it should come back at once."
$PROBE hold 10 &
CUR=$!
guard $CUR
sleep 3
kill -9 $CUR 2>/dev/null
$PROBE gone $CUR
unguard
CUR=0
ask kill "Did the screen come back at once after the kill?"
go "The screen goes black; after 2 s the probe is frozen (kill -STOP) and the screen STAYS black for 3 s (what a stuck Sill would leave, which Sill's watchdog will end), then it is killed and should come back at once."
$PROBE hold 10 &
CUR=$!
guard $CUR
sleep 2
kill -STOP $CUR 2>/dev/null
sleep 1
$PROBE gone $CUR --present
sleep 2
kill -9 $CUR 2>/dev/null
$PROBE gone $CUR
unguard
CUR=0
ask stop "While it was frozen, was the screen black? After the kill, did it come back at once?"
print ""

print "--- Step 4 of 5: telling Sill's own input from a person's (no black) ---"
print "The probe posts a pointer move (to where the pointer already is) and a Shift press, once with Sill's tag and"
print "once without; then it asks you to move the mouse a little and press Shift once."
go "When ready,"
spell $PROBE events
print ""

print "--- Step 5 of 5: is the black black? (1 spell of 10 s) ---"
print "Before you go on, if you can: turn on Night Shift and True Tone (Control Center › Display), play an HDR"
print "video (YouTube's HDR, or the TV app) where the black will cover it, and connect an external monitor or a"
print "Sidecar iPad if you have one at hand."
ask setup "What did you set up (Night Shift, True Tone, an HDR video, a monitor, Sidecar)?"
go "Every screen goes black for 10 s. Look at each, from the side too."
spell $PROBE black 10
ask black "Was every screen pure black? Any glow, bright HDR spots, a band, or a screen that stayed lit? Which screens?"
print ""
print "=== Done. Thank you. The report: $REPORT ==="
