#!/bin/bash
# TextComposition (iOSClient/TextComposition.swift) on its own: an input method's composition stays on
# the device until committed, and dictation's and an input method's edits reach the Mac as backspaces
# and text (#138).
#   Tests/checks/text-composition/run.sh             compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O iOSClient/TextComposition.swift "$here/main.swift" -o "$out/check"
"$out/check"
