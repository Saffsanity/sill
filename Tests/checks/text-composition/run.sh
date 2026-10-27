#!/bin/bash
# TextComposition (iOSClient/TextComposition.swift) on its own, with StreamProtocol's Input.swift: an
# input method's composition stays on the device until it is committed, and dictation's and an input
# method's edits reach the Mac as backspaces and text (#138); what was typed is kept whole while the
# text system may revise it, trimmed only past its limit, and a correction taken before a forget or a
# trim sends nothing; a Return or a Tab typed as text makes what came before it final (the fence: a
# correction of it sends nothing, one of what follows it goes, Korean's rebuild across it sends the
# Return once); and TextInputRules: which input moves
# the Mac's caret, where a Return or a Tab typed ends, which input modes are keyboards, and whose
# ⌃Space it is.
#   Tests/checks/text-composition/run.sh             compile and run the check
#   Tests/checks/text-composition/run.sh --mutants   one-line mutants of TextComposition.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/TextComposition.swift Sources/StreamProtocol/Input.swift "$here/main.swift" -o "$out/check"
"$out/check"
