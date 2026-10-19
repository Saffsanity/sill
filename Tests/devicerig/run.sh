#!/bin/bash
# devicerig (TEST ONLY; README.md): an XCUITest runner that drives the Sill already installed on a
# physical iPad or iPhone, by its bundle identifier, through a script of steps: taps, holds, drags,
# pinches, typed text and keys, screenshots and the accessibility tree.
#
#   Tests/devicerig/run.sh build                           build the runner (build-for-testing), for devices and the simulator
#   Tests/devicerig/run.sh UDID "<script>" [LAUNCH ARGS…]  run the script on that device: the runner is installed there,
#                                                          and `launch` starts the app with LAUNCH ARGS
#
# For example (README.md lists every step; coordinates are points in the app's first window):
#   Tests/devicerig/run.sh 00008110-0016793226E0401E 'launch; wait 4; shot first; drag 560,300 560,500 0.1; shot after; terminate' \
#       -SillConnect 169.254.71.35:60606
#
# UDID is a paired device's (xcrun devicectl list devices) or a booted simulator's of your own, for trying
# a script first; never a shared simulator. A run leaves .build/devicerig/NAME/ (NAME: RIG_NAME, or the
# time): run.log (xcodebuild's output), rig.log (the rig's own lines), NAME.xcresult, and shots/, with
# each `shot` as NAME.png and each `tree` as tree-N.txt, exported from the result bundle with
#   xcrun xcresulttool export attachments --path NAME.xcresult --output-path attachments
# and named from attachments/manifest.json's suggestedHumanReadableName ("NAME_0_<UUID>.png").
#
# Environment: RIG_APP (the bundle identifier, me.saffer.sill), RIG_NAME (the run's folder), RIG_TREE_LINES
# (how much of the tree `tree` prints, 300), RIG_TIMEOUT (seconds before xcodebuild is stopped, 600),
# RIG_DERIVED (the runner's DerivedData, .build/devicerig/DerivedData).
#
# It installs only the runner (me.saffer.sill.devicerig.xctrunner) and launches the app; it never builds,
# installs or removes the app. A device must be paired, unlocked and in Developer Mode, and the first run
# asks on the device for Touch ID or Face ID to enable UI Automation (README.md). The scheme keeps no
# screen recording (screenshots only, none kept), and xcodebuild collects no diagnostics.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/devicerig"
derived="${RIG_DERIVED:-$out/DerivedData}"
project="$here/DeviceRig.xcodeproj"

usage() { sed -n '6,8p' "$0" | sed 's/^#   //' >&2; exit 2; }

build_for() {   # $1: the destination, $2: the log
    if ! xcodebuild build-for-testing -project "$project" -scheme DeviceRig -configuration Debug \
            -destination "$1" -derivedDataPath "$derived" -allowProvisioningUpdates > "$2" 2>&1; then
        grep -E 'error:' "$2" | sort -u | head -20 >&2 || true
        tail -3 "$2" >&2
        echo "devicerig: the build for $1 failed (log: $2)" >&2
        exit 1
    fi
    # Compiler warnings only: the App Intents metadata step's note is in every build without App Intents.
    grep -E ' warning: ' "$2" | grep -v appintentsmetadataprocessor | sort -u | head -20 || true
}

build() {
    mkdir -p "$out"
    echo "devicerig: building the runner for devices and for the simulator (logs: $out/build-*.log)"
    build_for 'generic/platform=iOS' "$out/build-device.log"
    build_for 'generic/platform=iOS Simulator' "$out/build-simulator.log"
    echo "devicerig: built $(cd "$derived/Build/Products" && ls -d *.xctestrun | tr '\n' ' ')"
}

[ "${1:-}" = build ] && { build; exit 0; }
[ $# -ge 2 ] || usage
udid="$1"; script="$2"; shift 2
launch_args="$*"
[ -n "$script" ] || usage

# A paired device, or a booted simulator.
platform="$(xcrun simctl list devices --json | python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == sys.argv[1]:
            print("simulator" if d["state"] == "Booted" else "shutdown")
' "$udid")"
case "$platform" in
    simulator) products=iphonesimulator ;;
    shutdown) echo "devicerig: the simulator $udid is not booted" >&2; exit 2 ;;
    *)
        xcrun devicectl list devices 2>/dev/null | grep -F "$udid" | grep -q 'available (paired)' || {
            echo "devicerig: no paired device $udid is available (xcrun devicectl list devices)" >&2; exit 2; }
        products=iphoneos ;;
esac
ls "$derived"/Build/Products/DeviceRig_${products}*.xctestrun >/dev/null 2>&1 || build

name="${RIG_NAME:-$(date +%Y%m%d-%H%M%S)}"
work="$out/$name"
rm -rf "$work"; mkdir -p "$work/shots"
log="$work/run.log"
echo "devicerig: running on $udid (log: $log)"
set +e
# xcodebuild hands the TEST_RUNNER_ variables to the runner without the prefix (DeviceRig.swift).
TEST_RUNNER_RIG_SCRIPT="$script" TEST_RUNNER_RIG_LAUNCH_ARGS="$launch_args" \
TEST_RUNNER_RIG_APP="${RIG_APP:-me.saffer.sill}" TEST_RUNNER_RIG_TREE_LINES="${RIG_TREE_LINES:-300}" \
perl -e 'alarm shift; exec @ARGV' "${RIG_TIMEOUT:-600}" \
    xcodebuild test-without-building -project "$project" -scheme DeviceRig -configuration Debug \
        -destination "id=$udid" -derivedDataPath "$derived" \
        -only-testing:DeviceRigUITests/DeviceRig/testScript -collect-test-diagnostics never \
        -resultBundlePath "$work/$name.xcresult" > "$log" 2>&1
status=$?
set -e
grep -E '^rig: ' "$log" > "$work/rig.log" || true
cat "$work/rig.log"

# The screenshots and trees, out of the result bundle and named after their steps.
if [ -d "$work/$name.xcresult" ]; then
    xcrun xcresulttool export attachments --path "$work/$name.xcresult" --output-path "$work/attachments" \
        > /dev/null 2>&1 || true
    python3 - "$work/attachments" "$work/shots" <<'PY'
import json, os, re, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
manifest = os.path.join(src, "manifest.json")
if not os.path.exists(manifest):
    sys.exit(0)
for test in json.load(open(manifest)):
    for a in test.get("attachments", []):
        exported = a["exportedFileName"]
        stem, ext = os.path.splitext(a.get("suggestedHumanReadableName") or exported)
        # XCTest names an attachment "NAME_0_<UUID>": the step's NAME is what goes before.
        m = re.match(r"^(.*)_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}$", stem)
        stem = m.group(1) if m else stem
        ext = ext or os.path.splitext(exported)[1]
        target = os.path.join(dst, stem + ext)
        n = 2
        while os.path.exists(target):
            target = os.path.join(dst, f"{stem}-{n}{ext}"); n += 1
        shutil.copyfile(os.path.join(src, exported), target)
        print("devicerig: " + ("shot " if ext == ".png" else "attachment ") + target)
PY
fi
if [ $status -ne 0 ]; then
    grep -E 'error|Error|failed|Failed' "$log" | grep -v -E '^rig: |IDESchemeActionSDKRecord' | sort -u | tail -12 >&2 || true
    if grep -q 'Timed out while enabling automation mode' "$log"; then
        echo "devicerig: the device did not allow UI Automation: its owner answers \"Enable UI Automation\" on it with Touch ID or Face ID (README.md)" >&2
    fi
    echo "devicerig: xcodebuild exited $status (log: $log)" >&2
    exit $status
fi
echo "devicerig: done ($work)"
