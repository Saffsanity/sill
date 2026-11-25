#!/bin/bash
# KeycodeTyping and HangulRun (Sources/SillHost/KeycodeTyping.swift) on their own: the keys an app that
# reads only a key event's virtual key (Parallels Desktop) is sent for a device's text, a US key per
# character and a Hangul character's 2-set keys, against a model of the guest's Korean input method.
#   Tests/checks/keycode-typing/run.sh   compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O -package-name sill Sources/SillHost/KeycodeTyping.swift "$here/main.swift" -o "$out/check"
"$out/check"
