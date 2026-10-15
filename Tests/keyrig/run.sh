#!/bin/bash
# keyrig (TEST ONLY; README.md): a hardware keyboard and a mouse for the iOS Simulator, posted from a virtual
# HID service inside the simulator, so UIKit routes them as a real keyboard's and mouse's.
#
#   Tests/keyrig/run.sh build                         compile keyrig for the simulator: .build/keyrig/keyrig
#   Tests/keyrig/run.sh UDID keys SPEC [SETTLE] [HOLD]    SPEC: USAGE[:down|:up],… in hex (29 Esc, 04 a, e3 ⌘)
#   Tests/keyrig/run.sh UDID point SCRIPT [SETTLE] [HOLD] SCRIPT: move DX,DY | wheel DY | phase P DX,DY | momentum B DY | wait S
#
# Only a booted simulator, by UDID: one of your own, made for the test (never a shared one: the keys go to
# whatever app is in front, and once a simulator has had keys from a keyboard UIKit counts one as attached
# there, so its software keyboard stops coming up). Nothing here reaches the Mac's own HID system: keyrig
# runs inside the simulator (`xcrun simctl spawn`) and refuses to run anywhere else.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/keyrig"
bin="$out/keyrig"

build() {
    mkdir -p "$out"
    # As duorig: the simulator reads a process's entitlements from its __TEXT,__entitlements section,
    # and the code signature stays ad hoc and carries none.
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -Wall -Werror -O1 \
        -framework Foundation -framework CoreFoundation "$here/keyrig.m" -o "$bin" \
        -Wl,-sectcreate,__TEXT,__entitlements,"$here/keyrig.entitlements"
    codesign -s - --force "$bin" 2>/dev/null
    echo "built $bin"
}

[ "${1:-}" = build ] && { build; exit 0; }
[ $# -ge 3 ] || { sed -n '5,7p' "$0" | sed 's/^# //' >&2; exit 2; }
udid="$1"; shift
state="$(xcrun simctl list devices --json | python3 -c '
import json, sys
udid = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == udid:
            print(d["state"])
' "$udid")"
case "$state" in
    Booted) ;;
    "") echo "keyrig: no simulator $udid" >&2; exit 2 ;;
    *) echo "keyrig: $udid is not booted ($state)" >&2; exit 2 ;;
esac
[ -x "$bin" ] || build >/dev/null
# A simulator's process cannot open a file under ~/Downloads, where this repository lives: keyrig runs
# from the simulator's own data/tmp, a copy made when it changed.
simbin="$(xcrun simctl getenv "$udid" HOME)/tmp/keyrig"
cmp -s "$bin" "$simbin" 2>/dev/null || install -m 755 "$bin" "$simbin"
case "$1" in
    keys|point) xcrun simctl spawn "$udid" "$simbin" "$@" ;;
    *) echo "keyrig: no command $1" >&2; exit 2 ;;
esac
