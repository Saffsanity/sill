#!/bin/bash
# PictureSmoothing (iOSClient), the This-device setting for how the picture is scaled: Windows App's
# five levels, which renderer draws each, the shader's filters and their weights.
#   Tests/checks/picture-smoothing/run.sh             compile and run the check
#   Tests/checks/picture-smoothing/run.sh --mutants   one-line mutants of PictureSmoothing.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check" "$out/gpu"
swiftc -O iOSClient/PictureSmoothing.swift "$here/main.swift" -o "$out/check"
"$out/check"
# The shader on this Mac's GPU against the reference (it passes, saying so, without a Metal device).
mkdir -p "$out/gpu-src" && cp "$here/gpu.swift" "$out/gpu-src/main.swift"     # top-level code lives in main.swift
swiftc -O iOSClient/PictureSmoothing.swift iOSClient/StreamShader.swift "$out/gpu-src/main.swift" -o "$out/gpu" -framework Metal
"$out/gpu"
