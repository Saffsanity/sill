#!/bin/zsh
# TEST ONLY. The restore probe (issue #57; docs/restore-window-frames-plan.md): the real
# WindowSizer.resize and the per-window restore StreamCoordinator.restoreFits runs (WindowRestore's
# fit and stop, through WindowSizer.AXWindows) against a window of its own, frames before, during and
# after: a stop (its whole frame back), a rotation's re-fit, moved on the Mac (its own size where it
# is), moved then re-fitted, resized on the Mac (left alone), an app's minimum, a window that closes, a
# fit's nudge undone, a window that cannot be resized (its nudge put back at once), an app that does not
# answer (SIGSTOP: about a second, no writes), the virtual display's way home (worked out only), two
# windows (a pick, then the last device leaving), an app that stops answering during a fit (its size
# unanswered and recorded, taken once it runs again, then put back), and a resize from the left edge
# that a re-fit undid (no move: the whole frame back).
# usage: Scripts/restore-probe/run.sh
# Builds under .build/restore-probe/: the window's app (owner.swift in a bundle of its own,
# me.saffer.sill.restoreprobe, never activated) and the driver (driver.swift with the worktree's
# WindowSizer.swift, WindowRestore.swift and StreamProtocol's sources as one module). It touches no
# other window, posts no input, makes no virtual display and links no VideoToolbox; the front app is
# read before and after and must not change. Needs Accessibility and Screen Recording for the app that
# runs it (the terminal), and an unlocked screen: it says which is missing and exits 2. Exit 0: every
# step as expected; 1: a step failed.
set -u
ROOT=${0:A:h:h:h}
HERE=${0:A:h}
OUT=$ROOT/.build/restore-probe
APP=$OUT/Probe.app
mkdir -p $APP/Contents/MacOS
cp $HERE/Info.plist $APP/Contents/Info.plist
swiftc -O $HERE/owner.swift -o $APP/Contents/MacOS/owner || exit 1
codesign -s - --force $APP 2>/dev/null || exit 1
T=$(mktemp -d)
cp $ROOT/Sources/StreamProtocol/*.swift $T/
sed '/^import StreamProtocol$/d' $ROOT/Sources/SillHost/WindowSizer.swift > $T/WindowSizer.swift
cp $ROOT/Sources/SillHost/WindowRestore.swift $T/WindowRestore.swift
cp $HERE/driver.swift $T/main.swift
swiftc -O -package-name sill $T/*.swift -o $OUT/driver || { rm -rf $T; exit 1 }
rm -rf $T
for b in $OUT/driver $APP/Contents/MacOS/owner; do
  if otool -L $b | grep -q VideoToolbox; then echo "REFUSED: $b links VideoToolbox"; exit 1; fi
done
$OUT/driver $APP/Contents/MacOS/owner
