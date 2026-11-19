#!/bin/bash
# PinchGestures (Sources/SillHost): a device's two-finger pinch and turn (InputEvent.magnify, .rotate) as the
# Mac's own trackpad gestures, what InputInjector posts for each: the pointer where a gesture begins (only
# when it is more than a point away, and only for the first of the two), every event of a gesture where it
# began, a began over an open one closing it first, a changed or an ended with none open posting nothing, the
# values bounded and a value that is not a number dropped whole, the magnify and the rotate open together at
# one place, and the watchdog and the host's end closing what a device left open. Then random sessions through
# a model of the injector's glue with its watchdog, against the invariants.
# Compiled with StreamProtocol's sources as one module (build.sh, -package-name sill).
#   Tests/checks/pinch-gestures/run.sh             compile and run the check
#   Tests/checks/pinch-gestures/run.sh --mutants   one-line mutants of PinchGestures.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
