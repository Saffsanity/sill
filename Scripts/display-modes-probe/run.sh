#!/bin/zsh
# TEST ONLY. The modes probe, P2 of docs/virtual-desktop-plan.md (as revised 2026-11-18; phase 2b's first commit): can
# Sill's Desktop display take a device's turn without being removed and made again? It makes a display with the
# device's room both ways as its modes, switches between them in place with public CoreGraphics
# (CGConfigureDisplayWithDisplayMode, VirtualDisplay.switchMode), gives the live display new modes with applySettings:
# again (VirtualDisplay.applyModes), and says, for each change, the display's ID, its mode, the reconfiguration
# callback's flags (a mode change, or a removal and an addition) and where a window of the probe's own went
# (probe.swift's header has every step). Noah ran it on 2026-11-23 (macOS 27.2.1); P2b (p2b/) and P2c (p2c/), the probes
# that followed it that day, decided how the Virtual Desktop follows its device in place (VirtualDesktopSize.followWay,
# InPlace; docs/steps/2026-11-18-virtual-desktop-2b.md, fourth part); its own verdict lines were corrected then (probe.swift).
# usage: Scripts/display-modes-probe/run.sh [--make] [WxH] [HZ]
#   (no --make)  the dry run, what an agent runs: builds the probe, looks up the private API's surface (no display) and
#                prints the modes, their backing and the steps. Nothing is made, shown, moved or posted.
#   --make       Noah's, on a Mac at rest: makes the display "Sill Probe" for about ten seconds (Sill's Desktop
#                identity with a serial of its own, so macOS remembers nothing for Sill's own display) and a window of
#                its own on it, then removes both. Refused while Sill.app, the bare SillMenuBar or a SillHost runs
#                (one could be streaming, and Sill would take the probe's display for its own Desktop display).
#   WxH          the device's room in points (default 1376x1032, an iPad Pro 13-inch sideways); HZ the rate (60).
# Builds under .build/display-modes-probe/: Sources/SillHost/VirtualDisplay.swift with probe.swift, nothing else (no
# VideoToolbox, no ScreenCaptureKit). Exit 0: the dry run's surface is there, or the real run went to its end (its
# verdict lines say what macOS did); 1: the build failed, the surface is missing or the display was not made; 2: a
# refusal or a bad argument.
set -u
ROOT=${0:A:h:h:h}
HERE=${0:A:h}
OUT=$ROOT/.build/display-modes-probe
mkdir -p $OUT
if (( ${@[(Ie)--make]} )); then
  # The real run makes a display on this Mac, which only Noah does, from Terminal.app: never from an agent's shell.
  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "REFUSED: no terminal. --make makes a display on this Mac, which only Noah does, from Terminal.app. An agent runs the dry run."
    exit 2
  fi
  for p in Sill SillMenuBar SillHost; do
    if pgrep -x $p >/dev/null; then
      echo "REFUSED: $p is running. Quit it first: the probe runs on a Mac at rest, with nothing streaming."
      exit 2
    fi
  done
fi
T=$(mktemp -d)
cp $ROOT/Sources/SillHost/VirtualDisplay.swift $T/VirtualDisplay.swift
cp $HERE/probe.swift $T/main.swift
swiftc -O $T/*.swift -o $OUT/probe || { rm -rf $T; exit 1 }
rm -rf $T
if otool -L $OUT/probe | grep -q VideoToolbox; then echo "REFUSED: the probe links VideoToolbox"; exit 1; fi
$OUT/probe "$@"
