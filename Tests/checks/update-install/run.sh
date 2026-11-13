#!/bin/bash
# Update Now, the one-click update (docs/one-click-update-plan.md §4): UpdateInstallPolicy's rules (the
# trust and the endpoints Sill.app uses, every refusal and its words, what GitHub's release must say,
# the judgement of a downloaded bundle, the state machine, Settings' and the menu's words),
# UpdateManifest's format and signature (with a key made here and thrown away), UpdateArchive's reading
# of zips built here (every hostile kind the plan names), and the app's sources read as text: Sill.app
# makes no Trust or Endpoints but the two constants, and no updater file reads a default, the
# environment or the arguments.
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/update-install/run.sh             compile and run the check
#   Tests/checks/update-install/run.sh --mutants   one-line mutants of the four files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check" "$root/Sources/SillMenuBar"
