#!/bin/bash
# CatalogWindows (Sources/SillHost/CatalogWindows.swift), which on-screen windows the catalog lists, the
# tiles in a device's window strip (issue #114): an app's window by owner, layer, size and process, and
# the helpers' windows left out (LayerProbeParent, macOS's own interface, a tool's untitled window);
# this Mac's list as a read-only probe saw it, Stage Manager's strip, the lines Sill.log gets, and
# 20,000 seeded random windows.
#   Tests/checks/catalog-windows/run.sh             compile and run
#   Tests/checks/catalog-windows/run.sh --mutants   one-line mutants of CatalogWindows.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/SillHost/CatalogWindows.swift "$here/main.swift" -o "$out/check"
"$out/check"
