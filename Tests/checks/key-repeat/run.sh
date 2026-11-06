#!/bin/bash
# KeyRepeat (Sources/SillHost): a device's key held down repeats on the Mac as the Mac's own keyboard
# repeats a key (#162): after the Mac's Delay Until Repeat, at its Key Repeat Rate, from the settings
# as NSEvent gives them (Off and nonsense repeat nothing); every key but the modifiers' own, Caps Lock,
# fn and the media keys; the last key pressed alone, a modifier's change carried by the repeats after
# it; stopped at its up, another key, text, a gesture's shortcut, its device leaving and input with
# nowhere to land; waiting while input is held for an activation and while its device is quiet, then
# starting over after the delay. Put through a model of InputInjector's glue with the real KeyStrokes:
# scenarios with the exact events and times, then random sessions against the invariants.
# Compiled with StreamProtocol's sources and Sources/SillHost/KeyStrokes.swift as one module (build.sh).
#   Tests/checks/key-repeat/run.sh             compile and run the check
#   Tests/checks/key-repeat/run.sh --mutants   one-line mutants of KeyRepeat.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
