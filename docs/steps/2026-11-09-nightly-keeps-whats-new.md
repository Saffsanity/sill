**The nightly leaves What to Test alone on a build it did not upload (2026-11-09, branch
`nightly-keeps-whats-new` from main at f224323d; docs/nightly-whats-new-plan.md has the night, the cause
with line numbers, the six open questions with their defaults and the results).** 0.6.1 (1304) was
uploaded by hand from main's head with What to Test of its own; that night's nightly (run 42593083786)
found the build, skipped the upload as designed, and its distribute step replaced the words with the
night's notes (put back by hand with `asc.swift whats-new`). No app code, no wire change.
- `Scripts/asc.swift distribute` gives What to Test only to a build with none (no localization, or only
  empty or white-space ones); a build with some, in any language, keeps it, nothing written ("What to
  Test left as it is: the build has its own already (English (U.S.), N characters) …"), unless
  `--replace-whats-new` (distribute only, no value). `whats-new` always replaces.
- `nightly.yml`: the upload step (`id: upload`) writes `uploaded=true` after `release-ios.sh --upload`,
  `uploaded=false` when App Store Connect had the build (its notice says the words are kept); the
  distribute step passes `--replace-whats-new` only for exactly `true` (fail-safe: anything else keeps),
  says so, and the summary carries asc's "What to Test …" line; the summary's last words say "Uploaded to
  App Store Connect" only for `uploaded=true` (that night's said it for a build it had not uploaded).
- `Tests/checks/asc` (new, in CI and its mutants matrix): the nightly harness of 2026-10-29 brought in
  (outside the repository until now), every run of asc under `sandbox-exec` with only loopback allowed,
  checked first; its stand-in no longer looks up 127.0.0.1's name at bind (35 s here that day). 167
  checks (23 fail on main's asc.swift); mutants: the report. The workflow's run blocks and structure:
  the triage folder's extended harnesses (wf-blocks 118, yaml-check 266; 39 and 9 fail on main), and the
  night replayed through nightly.yml's own two iOS run blocks with the real asc against the stand-in:
  main's replaces the hand's words, this branch keeps them, the other three cases send the same requests.
- **For Noah:** the next night that uploads: "What to Test set (…)" in its summary; a night whose build
  you uploaded by hand: "This run did not upload build N" and "What to Test left as it is". `asc.swift
  distribute` by hand keeps a build's words unless given `--replace-whats-new`.
