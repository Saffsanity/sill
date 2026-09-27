#!/bin/bash
# The touch rig (docs/trackpad-gestures-plan.md §9.2, H7): the app's real TrackpadView.swift and
# InputOverlay.swift, with TrackpadGestures.swift where the sources have it, compiled into a scratch
# app for the iOS simulator that drives both surfaces with synthesized touches (TouchSynth, private
# UIKit calls, test only) and logs what each would send the Mac. Nothing reaches the Mac: `send` and
# `sendGesture` only log. Never linked into the app.
#
#   Tests/touchrig/run.sh NAME                 the working tree's surfaces; the log is .build/touchrig/NAME.log
#   Tests/touchrig/run.sh --rev REV NAME       the surfaces as they are at REV (git show), for a baseline
#   Tests/touchrig/run.sh --switch off NAME    sendGesture answers false, as with the device's switch off
#   Tests/touchrig/compare.py BASE.log NEW.log [OFF.log]   H7's verdict
#
# It runs on a simulator of its own, named by SILL_TOUCHRIG_SIM (default "Sill touchrig"), made (an
# iPad Pro 11-inch (M5) on the newest iOS) when there is none and deleted afterwards only when this
# run made it. Never the shared iPad Pro 13", never `simctl io recordVideo`, no XCUITest. About 2.5 GB
# while the simulator exists. Limits: synthesized touches, not glass; iPadOS's own gestures and the
# editing overlay are out of its reach.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rev="" switch=on name=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rev) rev="$2"; shift 2 ;;
        --switch) switch="$2"; shift 2 ;;
        -*) echo "usage: Tests/touchrig/run.sh [--rev REV] [--switch on|off] NAME" >&2; exit 2 ;;
        *) name="$1"; shift ;;
    esac
done
[ -n "$name" ] || { echo "usage: Tests/touchrig/run.sh [--rev REV] [--switch on|off] NAME" >&2; exit 2; }
out="$root/.build/touchrig"
work="$out/$name"
rm -rf "$work"; mkdir -p "$work/src" "$work/TouchRig.app"

# The sources, from the working tree or REV. A file REV does not have is left out.
fetch() {
    if [ -z "$rev" ]; then
        [ -f "$root/$1" ] && cp "$root/$1" "$work/src/$(basename "$1")" || true
    else
        git -C "$root" show "$rev:$1" > "$work/src/$(basename "$1")" 2>/dev/null || rm -f "$work/src/$(basename "$1")"
    fi
}
for f in iOSClient/TrackpadView.swift iOSClient/InputOverlay.swift iOSClient/PointerPresence.swift \
         iOSClient/TrackpadGestures.swift iOSClient/PortraitStreamScreen.swift Sources/StreamProtocol/Input.swift; do
    fetch "$f"
done
cd "$work/src"
# One module: StreamProtocol's Input.swift is compiled in, so its import goes.
sed -i '' '/^import StreamProtocol$/d' TrackpadView.swift InputOverlay.swift
# KeyModifiers and HIDKey, the app's own, cut from PortraitStreamScreen.swift.
sed -n '/^\/\/ MARK: - Keys$/,/^\/\/ MARK: - Screen$/p' PortraitStreamScreen.swift > Keys.swift
rm PortraitStreamScreen.swift
flags=()
# The gestures when the surfaces have them (the stroke gate and `sendGesture`).
if grep -q "var sendGesture" TrackpadView.swift; then flags+=(-D GESTURES); fi
cp "$here/Stubs.swift" "$here/main.swift" "$here/TouchSynth.h" "$here/TouchSynth.m" "$here/Bridging.h" .

target=arm64-apple-ios17.0-simulator
xcrun -sdk iphonesimulator clang -target $target -fobjc-arc -Wall -c TouchSynth.m -o TouchSynth.o
xcrun -sdk iphonesimulator swiftc -target $target -swift-version 5 -module-name TouchRig -Onone ${flags[@]+"${flags[@]}"} \
    -import-objc-header Bridging.h Stubs.swift Keys.swift Input.swift $(ls PointerPresence.swift TrackpadGestures.swift 2>/dev/null) \
    TrackpadView.swift InputOverlay.swift main.swift TouchSynth.o -o "$work/TouchRig.app/TouchRig"
cat > "$work/TouchRig.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TouchRig</string>
<key>CFBundleIdentifier</key><string>me.saffer.sill.touchrig</string>
<key>CFBundleName</key><string>TouchRig</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
<key>UIApplicationSupportsIndirectInputEvents</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign -s - --force "$work/TouchRig.app" >/dev/null 2>&1

# The simulator.
sim="${SILL_TOUCHRIG_SIM:-Sill touchrig}"
udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True): print(d["udid"]); raise SystemExit
' "$sim")"
made=0
if [ -z "$udid" ]; then
    runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(ios, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')"
    udid="$(xcrun simctl create "$sim" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB "$runtime")"
    made=1
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$work/TouchRig.app"
log="$out/$name.log"
SIMCTL_CHILD_RIG_SWITCH="$switch" perl -e 'alarm shift; exec @ARGV' 600 \
    xcrun simctl launch --console-pty --terminate-running-process "$udid" me.saffer.sill.touchrig > "$log" 2>&1 || true
xcrun simctl uninstall "$udid" me.saffer.sill.touchrig || true
if [ "$made" = 1 ]; then xcrun simctl shutdown "$udid" || true; xcrun simctl delete "$udid" || true; fi
grep -q '^RIG done' "$log" || { echo "touchrig: the run did not finish; see $log" >&2; exit 1; }
echo "touchrig: $(grep -c '^===' "$log") scenarios, the log is $log"
