#!/bin/bash
# RecordingNotice (Sources/SillHost/RecordingNotice.swift; #284, docs/recording-plan.md): what the Mac says
# of a device recording the stream. `generation` (the window list's `recordings`), the log's words, and
# each connection's lines from the device's reports (ClientStats.recording): a change written at once,
# then at most a line every 10 s, the changes in between counted in the next and the state brought up to
# date by the first report after the spacing; the line as the connection closes (left while recording, a
# held stop, nothing). Scripted sessions, then 20,000 random ones against the invariants.
# Compiled with the files in module.txt as one module.
#   Tests/checks/recording-notice/run.sh             compile and run the check
#   Tests/checks/recording-notice/run.sh --mutants   one-line mutants of RecordingNotice.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
