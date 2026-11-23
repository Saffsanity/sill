#!/bin/bash
# Builds the recording rig (docs/recording-plan.md, Tests, "The rig") into .build/recording-check (git-ignored):
#   recordcheck  a device that records a loopback test host's stream with the app's own StreamRecorder: this
#                folder's recordcheck.swift with StreamProtocol, SillAudio's AudioDecoder, KeyframeRecovery and
#                the three rules, as one module (their `import StreamProtocol` and `import SillAudio` dropped).
#                Refused if it links any VTCompressionSession symbol: passthrough writing never encodes video.
#   moviecheck   reads a movie with AVFoundation, reading only (it never decodes the picture).
# Heavy (a few hundred source files' worth of compiling): run it inside the heavy lock with run.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/recording-check"
src="$out/src"
rm -rf "$src"; mkdir -p "$src"
for f in "$root"/Sources/StreamProtocol/*.swift "$root/Sources/SillAudio/AudioDecoder.swift" "$root/iOSClient/KeyframeRecovery.swift" \
         "$root/iOSClient/RecordingPolicy.swift" "$root/iOSClient/RecordingClock.swift" "$root/iOSClient/RecordedSound.swift" \
         "$root/iOSClient/StreamRecorder.swift"; do
    grep -v -E '^import (StreamProtocol|SillAudio)$' "$f" > "$src/$(basename "$f")"
done
cp "$here/recordcheck.swift" "$src/main.swift"
target="$(uname -m)-apple-macos14.0"
swiftc -O -target "$target" "$src"/*.swift -o "$out/recordcheck"
if nm -u "$out/recordcheck" | grep -q VTCompressionSession; then
    echo "recordcheck links VTCompressionSession: refused (passthrough writing never encodes video)" >&2
    rm -f "$out/recordcheck"; exit 1
fi
swiftc -O -target "$target" "$here/moviecheck.swift" -o "$out/moviecheck"
echo "built $out/recordcheck and $out/moviecheck"
