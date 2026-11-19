#!/bin/bash
# The device's rules for recording the stream (#284, docs/recording-plan.md): RecordingPolicy (what is offered,
# the count and the keyframe ask, where the movie starts, the pre-roll, the picture's chain, parts and names,
# what ends it, space, the light's words and every sentence, what the Mac is told), RecordingClock (the movie's
# timeline from the Mac's stamps: the floor, the anchor, the clock's steps, the stop) and its RecordingTimeline
# (the recorder's order of things), RecordedSound (the sound track: segments, joins, gaps, overlaps, silence,
# the tail in hand); then 20,000 random recordings against the invariants; and the source rules (only
# SillDocuments names Documents; the rules import Foundation alone). Compiled with the files in module.txt as
# one module, from the repository's root (the source rules read the iOS app's files there).
#   Tests/checks/recording/run.sh             compile and run the check
#   Tests/checks/recording/run.sh --mutants   one-line mutants of the three rules; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
