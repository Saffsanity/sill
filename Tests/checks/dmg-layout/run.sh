#!/bin/bash
# Scripts/dmg-layout's .DS_Store and alias writer (DSStore.swift, FinderAlias.swift, DMGLayout.swift)
# on its own: the window Scripts/make-dmg.sh gives Sill.dmg, read back byte by byte against Finder's
# own layout of the file, the background's alias field by field, the encoder and the decoder, the
# volume icon's flag, and that make-dmg.sh and design/DMGBackground.svg still give that window. No
# disk image is made (make-dmg.sh checks the real one as it makes it).
#   Tests/checks/dmg-layout/run.sh             compile and run the check
#   Tests/checks/dmg-layout/run.sh --mutants   one-place mutants of the three files, make-dmg.sh's
#                                              layout and the SVG; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
# make-dmg.sh's layout arguments, one per line: sourced, the script only defines them.
/bin/bash -c 'source Scripts/make-dmg.sh && printf "%s\n" "${layout[@]}"' > "$out/layout.txt"
swiftc -O Scripts/dmg-layout/DSStore.swift Scripts/dmg-layout/FinderAlias.swift Scripts/dmg-layout/DMGLayout.swift \
    "$here/main.swift" -o "$out/check"
"$out/check" "$out" "$out/layout.txt" design/DMGBackground.svg
