#!/bin/bash
# The Mac's sound through AAC-ELD in memory (docs/audio-plan.md H4): SillAudio's encoder
# (Sources/SillAudio/AudioEncoder.swift), packetizer and decoder (Sources/SillAudio/AudioDecoder.swift)
# and the host's test tone (Sources/SillHost/TestTone.swift), compiled together. Each click of the tone lands at its whole second
# of the stamps ±2 frames at 480 and 512 frames a packet, across gaps; one packet a block; a late
# join; the bitrate. A binary that links anything but AudioToolbox of the media frameworks (VideoToolbox,
# CoreMedia, AVFoundation, ScreenCaptureKit) is refused.
#   Tests/checks/audio-codec/run.sh             compile and run the check
#   Tests/checks/audio-codec/run.sh --mutants   one-line mutants of the encoder, decoder and tone; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/SillAudio/AudioEncoder.swift Sources/SillAudio/AudioPacketizer.swift Sources/SillHost/TestTone.swift \
    Sources/SillAudio/AudioDecoder.swift "$here/main.swift" -o "$out/check"
if otool -L "$out/check" | grep -Eq 'VideoToolbox|CoreMedia|AVFoundation|ScreenCaptureKit'; then
    echo "$name: the check links a media framework other than AudioToolbox; refusing it" >&2
    exit 1
fi
"$out/check"
