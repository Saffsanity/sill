#!/bin/bash
# CatalogLook (Sources/SillHost/CatalogLook.swift) on its own: whether a capture may be built from the
# catalog's last look at the windows and displays, or the catalog looks again first (2026-10-28: Sill.app
# 36.5 hours with no device, the look's display gone, the Desktop refused by ScreenCaptureKit and the
# screen black), at the rule's edges and in 20,000 random looks; the Desktop's line and its one more
# try's; the age's words.
#   Tests/checks/catalog-look/run.sh             compile and run the check
#   Tests/checks/catalog-look/run.sh --mutants   one-line mutants of CatalogLook.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/SillHost/CatalogLook.swift "$here/main.swift" -o "$out/check"
"$out/check"
