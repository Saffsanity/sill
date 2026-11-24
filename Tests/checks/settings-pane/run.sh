#!/bin/bash
# SettingsPane (iOSClient/SettingsPane.swift), with DuoPosture.swift for the fold: Settings as a whole-screen
# pane (docs/settings-pane-plan.md): where its two parts go at the real sizes and over a grid of every width
# from 200 to 1,400 pt, without a fold, around the book pose's and the laptop pose's, left to right and right
# to left; and what each way of closing it brings.
#   Tests/checks/settings-pane/run.sh             compile and run the check
#   Tests/checks/settings-pane/run.sh --mutants   one-line mutants of SettingsPane.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/SettingsPane.swift iOSClient/DuoPosture.swift "$here/main.swift" -o "$out/check"
"$out/check"
