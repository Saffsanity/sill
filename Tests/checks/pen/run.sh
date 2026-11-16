#!/bin/bash
# Sources/StreamProtocol/Pen.swift on its own: the wire shape of kind 45, what the host accepts of a
# batch, the tilt and place mapping, the tablet area's fit, and the pen's state machine.
#   Tests/checks/pen/run.sh             compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O Sources/StreamProtocol/Pen.swift "$here/main.swift" -o "$out/check"
"$out/check"
