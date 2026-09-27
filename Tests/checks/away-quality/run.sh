#!/bin/bash
# Away from home on the host (docs/remote-bundle-plan.md §5): HostConfig's away pair (standard,
# validated(), changes(to:), effective(away:)), DeviceSettings' streamSettings(away:), applyingAway and
# accepted, and AwayPolicy (who is away, when the away quality is the target, its two log lines).
# Compiled as one module with StreamProtocol's HostSettings.swift (build.sh).
#   Tests/checks/away-quality/run.sh             compile and run the check
#   Tests/checks/away-quality/run.sh --mutants   one-line mutants of those files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
