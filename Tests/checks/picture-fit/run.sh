#!/bin/bash
# PictureFit (iOSClient/PictureFit.swift) on its own: where the streamed picture is drawn in its pane. Aspect-fit in the
# pane's middle as before, but one for one from the pane's top-left pixel where the picture is the pane's own pixels less
# a hairline (an iPhone's pixel-for-pixel Virtual Desktop, Noah 2026-11-24: an iPhone 15 Pro's 1178×2378 picture in its
# 1179×2379-pixel pane). The iPhone 15 Pro's layouts by hand, an iPad's, windows; then 50,000 random panes and pictures.
#   Tests/checks/picture-fit/run.sh             compile and run the check
#   Tests/checks/picture-fit/run.sh --mutants   one-line mutants of PictureFit.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PictureFit.swift "$here/main.swift" -o "$out/check"
"$out/check"
