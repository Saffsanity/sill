#!/bin/bash
# duorig (TEST ONLY; README.md): folds and turns an iPhone Duo in the iOS Simulator the way Xcode 27.1's
# Device Hub does, and photographs it, so the Duo's poses can be driven with no hand on Device Hub.
#
#   Tests/duorig/run.sh build                       compile duorig for the simulator: .build/duorig/duorig
#   Tests/duorig/run.sh UDID hinge DEG              0 closed, 90 half-folded, 180 flat (jump, don't creep)
#   Tests/duorig/run.sh UDID orient O               portrait | pud | landscape-left | landscape-right | faceup | facedown
#   Tests/duorig/run.sh UDID pose NAME              closed-upright | closed-side | flat-portrait | flat-landscape | laptop | book
#   Tests/duorig/run.sh UDID shot NAME FILE.png     the display NAME's pose shows (the cover when closed, else the inner)
#   Tests/duorig/run.sh UDID services | watch [S]   read-only: the simulator's HID services, or every event for S seconds
#
# Only a booted simulator of the iPhone Duo device type (com.apple.CoreSimulator.SimDeviceType.iPhone-Duo,
# which exists from iOS 27.1) is accepted, by UDID. Nothing here reaches the Mac's own HID system: duorig runs inside
# the simulator (`xcrun simctl spawn`) and refuses to run anywhere else.
#
# Poses (Device Hub's terms; the inner display is landscape when the device is held upright):
#   closed-upright   hinge 0,   portrait         the cover display, upright (466×678 pt)
#   closed-side      hinge 0,   landscape-left   the cover display on its side (678×466 pt)
#   flat-portrait    hinge 180, landscape-left   the inner display, portrait (669×951 pt), fold inactive
#   flat-landscape   hinge 180, portrait         the inner display, landscape (951×669 pt), fold inactive
#   laptop           hinge 90,  landscape-left   the inner display, portrait, fold active across it (y 475.5)
#   book             hinge 90,  portrait         the inner display, landscape, fold active down it (x 475.5)
# Close only with an app in front: closing over the Home Screen puts the simulated device to sleep
# (the cover goes dark and screenshots repeat its last frame); opening (hinge 90 or 180) wakes it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/duorig"
bin="$out/duorig"

build() {
    mkdir -p "$out"
    # The simulator reads a process's entitlements from its __TEXT,__entitlements section; the code
    # signature itself stays ad hoc and carries none (launchd_sim refuses an ad hoc signature that
    # claims private entitlements: "Security policy issue").
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -Wall -Werror -O1 \
        -framework Foundation -framework CoreFoundation "$here/duorig.m" -o "$bin" \
        -Wl,-sectcreate,__TEXT,__entitlements,"$here/duorig.entitlements"
    codesign -s - --force "$bin" 2>/dev/null
    echo "built $bin"
}

[ "${1:-}" = build ] && { build; exit 0; }
[ $# -ge 2 ] || { sed -n '5,10p' "$0" | sed 's/^# //' >&2; exit 2; }
udid="$1"; shift
# Only a Duo simulator, by UDID: never a device, never another simulator.
line="$(xcrun simctl list devices --json | python3 -c '
import json, sys
udid = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == udid:
            print(d["deviceTypeIdentifier"], runtime, d["state"])
' "$udid")"
case "$line" in
    com.apple.CoreSimulator.SimDeviceType.iPhone-Duo\ *Booted) ;;
    "") echo "duorig: no simulator $udid" >&2; exit 2 ;;
    *) echo "duorig: $udid is not a booted iPhone Duo simulator ($line)" >&2; exit 2 ;;
esac
[ -x "$bin" ] || build >/dev/null
# A simulator's process cannot open a file under ~/Downloads (the open blocks), where this repository
# lives: duorig runs from the simulator's own data/tmp, a copy made when it changed.
simbin="$(xcrun simctl getenv "$udid" HOME)/tmp/duorig"
cmp -s "$bin" "$simbin" 2>/dev/null || install -m 755 "$bin" "$simbin"

spawn() { xcrun simctl spawn "$udid" "$simbin" "$@"; }

pose_of() {
    case "$1" in
        closed-upright) echo "0 portrait" ;;
        closed-side) echo "0 landscape-left" ;;
        flat-portrait) echo "180 landscape-left" ;;
        flat-landscape) echo "180 portrait" ;;
        laptop) echo "90 landscape-left" ;;
        book) echo "90 portrait" ;;
        *) echo "duorig: no pose $1" >&2; exit 2 ;;
    esac
}

cmd="$1"; shift
case "$cmd" in
    hinge|orient|services|watch|sweep) spawn "$cmd" "$@" ;;
    pose)
        p="$(pose_of "${1:-}")" || exit 2
        read -r deg orientation <<< "$p"
        spawn pose "$deg" "$orientation"
        # The display hands over and the app lays out again: let it settle before a photograph.
        sleep "${DUORIG_SETTLE:-3}" ;;
    shot)
        p="$(pose_of "${1:-}")" || exit 2
        [ -n "${2:-}" ] || { echo "duorig: shot needs a file" >&2; exit 2; }
        read -r deg _ <<< "$p"
        display=primary-1                         # the inner display ("LCD-1", 2007×2853 px)
        [ "$deg" = 0 ] && display=primary         # the cover display ("LCD", 1398×2034 px)
        xcrun simctl io "$udid" screenshot --display="$display" "$2" >/dev/null ;;
    *) echo "duorig: no command $cmd" >&2; exit 2 ;;
esac
