#!/bin/bash
# AppIconChoice (iOSClient/AppIconChoice.swift) on its own, and the build's wiring of the icons it names: the
# Home Screen icon of Sill for iPhone and iPad, chosen in Settings beside the version (Noah, 2026-11-18;
# docs/app-icons-plan.md): the choices and their names, every word, which icon shows for any name iOS keeps
# (an unknown one included), what a tap asks of iOS, whether the group shows; then, read from the repository,
# the project's primary and alternate icon names, each icon's document as a resource with every layer it
# names, no icon set of the same name, each preview, and Sill for Mac's icon the original.
#   Tests/checks/app-icon/run.sh             compile and run the check
#   Tests/checks/app-icon/run.sh --mutants   one-line mutants of AppIconChoice.swift, and of the wiring in a
#                                            copy of the files it reads; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/AppIconChoice.swift "$here/main.swift" -o "$out/check"
"$out/check"
