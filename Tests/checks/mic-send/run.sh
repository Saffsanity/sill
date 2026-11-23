#!/bin/bash
# The device's microphone on its way to the Mac (iOSClient/MicrophoneSender.swift and MicrophoneCapture.swift,
# docs/microphone-plan.md §3.4, §5.6), with SillAudio and StreamProtocol as one module (module.txt), on the Mac with
# no audio device: the format, ten packets a capture buffer, stamps, every click at its second, gaps, other buffer
# sizes, epochs, the Mac's limits, the capture's conversion of 16 and 24 kHz buffers, the test tone.
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol` and
# `import SillAudio`).
#   Tests/checks/mic-send/run.sh             compile and run the check
#   Tests/checks/mic-send/run.sh --mutants   one-line mutants of the sender and the capture; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
