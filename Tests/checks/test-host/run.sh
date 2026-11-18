#!/bin/bash
# AppIdentity (Sources/SillMenuBar), which launches are Sill.app itself and so take no test hook (the
# security scan of 2026-10-18, finding 1; fixed 2026-10-29): Sill.app's code is Sill.app wherever it runs from, by its
# signing identifier (the kernel's), a certificate, a bundle that says it is Sill or a .app folder,
# and only the bare SillMenuBar binary as swift build makes it is a test host; with IdentityStorePlan,
# a renamed copy never reads SILL_TEST_REMOTE_DIR's trust list. Its reader runs for real on copies of
# this check's own binary made in a temporary folder (codesign -s -, ad hoc: no keychain), each
# started under sandbox-exec with the network denied, and removed after.
#   Tests/checks/test-host/run.sh             compile and run the check
#   Tests/checks/test-host/run.sh --mutants   one-line mutants of AppIdentity.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
