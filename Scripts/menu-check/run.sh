#!/bin/zsh
# The menus' checks that need Accessibility but no host, no network and no encoder, from any
# directory (docs/menu-bar-plan.md §10). Each runs against a fresh Scripts/menufixture.swift, the only
# app anything here presses:
#   reader  MenuReader (the real file, with MenuFormat, MenuPolicy and StreamProtocol) against the
#           fixture: the top level and Probe; a bar item and a submenu item refused with nothing
#           opened; presses by the kept element and by the path; the title check (a kept element
#           under another title, Dynamic N, a rebuilt menu); Deep; 600 Items; Slow Action, and a
#           read while its action holds the fixture's main thread
#   budget  the same reader built with a 5 ms readBudget: a read stops early and counts the rest
#   mirror  MenuMirror (the real file) with that reader and stubs for the server's send, a
#           connection, Stats and print: H4–H8's and H10's logic end to end (versions, the cache,
#           presses, the refusals, rates, stale and its retry, a top level that fails to read, the
#           app gone, subscribers leaving)
# usage: Scripts/menu-check/run.sh [reader] [budget] [mirror]   (no argument: all)
# Everything builds under .build/menu-check/. The fixture runs with the prohibited policy and cannot
# take the front; `lsappinfo front` is sampled every 0.1 s through each run, and a change fails it.
# Needs Accessibility for the process that runs it (the terminal, or the app that started it). Safe
# while Sill.app streams: no binary here links VideoToolbox (checked with otool), nothing listens,
# and the host's gates through a synthetic host (H2, H4–H11) are not here: they encode.
set -u
ROOT=${0:A:h:h:h}
HERE=${0:A:h}
OUT=$ROOT/.build/menu-check
mkdir -p $OUT
steps=("$@"); (( ${#steps} )) || steps=(reader budget mirror)
failed=0

encoder_free() {   # BINARY: refuse it if it links VideoToolbox
  if otool -L $1 | grep -q VideoToolbox; then
    echo "REFUSED: $1 links VideoToolbox"; return 1
  fi
}

echo "== the fixture"
swiftc -O $ROOT/Scripts/menufixture.swift -o $OUT/menufixture -framework AppKit || exit 1
encoder_free $OUT/menufixture || exit 1

for step in $steps; do
case $step in
reader|budget)
  echo "== $step"
  if [[ $step == budget ]]; then $HERE/build.sh reader $OUT/reader-budget 0.005 || { failed=1; continue }
  else $HERE/build.sh reader $OUT/reader || { failed=1; continue }; fi
  bin=$OUT/reader; [[ $step == budget ]] && bin=$OUT/reader-budget
  encoder_free $bin || { failed=1; continue }
  python3 $HERE/fixture.py $OUT/menufixture $OUT/$step $bin ${${step:#reader}:+budget} || failed=1
  ;;
mirror)
  echo "== mirror"
  $HERE/build.sh mirror $OUT/mirror || { failed=1; continue }
  encoder_free $OUT/mirror || { failed=1; continue }
  python3 $HERE/fixture.py $OUT/menufixture $OUT/mirror $OUT/mirror || failed=1
  ;;
*)
  echo "unknown step $step (reader, budget, mirror)"; failed=1
  ;;
esac
done
(( failed )) && echo "menu-check: FAILED" || echo "menu-check: all passed"
exit $failed
