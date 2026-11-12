**GitHub Actions (2026-09-25, branch `github-actions` from main at 1f3072a).**
Noah: the download link still fails; a new release should be checked by
GitHub, and does that cost money. The link fails twice over: there is no
release (`release.sh --publish` has never run; `gh release list` is empty), and
Saffsanity/sill is private, so its release files are a 404 to anyone not signed
in with access (docs/release-checklist.md, "Releasing from GitHub Actions",
has both ways out: go public, or publish in sill-site; it went public on
2026-09-26, and v0.3.0 and v0.3.1 are published there). Added:
- `.github/workflows/ci.yml` (Layout): pull requests and pushes to main that
  touch more than documents, the site or design files, and by hand; one job on
  `xcode-27`, 30 minutes, cancelling an older run of the same event and ref.
  Runner: the newest image GitHub offers and the only one with Xcode 27 (macOS
  27.0 26A428 with Xcode 27.0 27A266a as the default, 27.1 installed as
  `Xcode_27.1_beta.app` and a 27.2 beta; a public preview, issue 14404);
  `macos-latest` is macOS 26 with Xcode 26.6 at most, `macos-15` Xcode 16.4
  and 26.3, never tried with this code. `.github/actions/select-xcode` takes
  the newest Xcode 27 whose folder is not a beta (27.0 there, the same build
  as this Mac) and prints `xcodebuild -version`. The `.build` cache is keyed
  on that toolchain and Package.swift (there is no Package.resolved),
  `.build/checks` left out. The iOS build is arm64 only and not `-quiet`:
  Xcode 27's -quiet heads a compile that only warned with "error: the
  following command failed with exit code 0". The CLI runs only where it exits
  before the host starts: `--internet` alone (exit 2) and
  `--print-reachability`. Mutants only by hand, a job per check. Actions
  pinned by commit (checkout v7.0.1, cache v6.1.0, upload-artifact v7.0.1, the
  newest on 2026-09-25).
- `.github/workflows/release.yml`: a pushed tag `v*` or by hand with a tag
  (`SILL_RELEASE_TAG`); checkout with the whole history (make-app.sh's build
  number is the commit count). Repository variable `SILL_SIGN_IN_CI` not
  `true`: verify (the tag, the checks, `make-app.sh` signed ad hoc, the icon
  there, `Sill-<version>-adhoc.zip` as an artifact for 14 days). `true`:
  the checks, a check that the five secrets are set, the .p12 into
  `$RUNNER_TEMP/sill-release.keychain-db` (random password, masked; first in
  the search list and the default keychain, where notarytool keeps profiles),
  `notarytool store-credentials sill-notary --keychain` (validates the key),
  `release.sh --publish` with `GH_TOKEN` (the run's token, `contents: write`,
  or `SILL_RELEASE_TOKEN` for `SILL_RELEASE_REPO`), the notary log as an
  artifact, and an always() step that deletes the keychain and key files.
- `Scripts/release.sh`: `SILL_RELEASE_TAG` in the preflight (the tag must be
  `v<CFBundleShortVersionString>` and, when it is here, name HEAD);
  `--check-tag` checks only that. It refuses a build without Assets.car and
  AppIcon.icns (make-app.sh only warns when Quick Look or actool fail). Publish
  asks `gh api repos/<repo>` instead of `gh auth status`, which asks GET /user,
  and Actions' token can't answer that.
- `Tests/checks/` (Layout): the pure checks from this session's scratch
  folders, the newest of each, the ones run against the sources main now has,
  unchanged but for paths (the compile line in six `main.swift` headers; the
  policy, fence and clientlink mutants scripts read the repository and write
  to `.build/checks/<name>/`): policy 286 (integrate-12's merged check, 70
  mutants), fence 14 modes (review-moves-b's, 19), ledger 90 (ledger-union,
  no mutants), clientlink 89 (14), remote-rules 64 (rf2, 35), origin 66 (10),
  protocol 188 plus crosscheck.py's 8 (20), addresses 41 (step 3, 15),
  pairing-address 80 (pairing-address/fixes, 35). Not here then:
  EncoderMailbox's (only on encoder-two-in-flight, which carried it as
  Scripts/encoder-check; since that branch merged main at 32d532b,
  `encoder-mailbox` and `encoder-slowstate` are here and in CI: "A new
  session for the slow state"), and update-notice's one-line change to
  protocol's kind 23 case.
- Verified here, nothing pushed and no Actions run: `Tests/checks/run-all.sh`
  passes (all nine, 132 s); every mutant caught (`run-all.sh --mutants`, about
  44 minutes here: policy 70, fence 19, remote-rules 35, pairing-address 35,
  protocol 20, addresses 15, clientlink 14, origin 10); `swift build -c
  release` (28 s, only the CaptureProbe warning); the iOS command (only the
  StreamClient warning; both simulator slices); the CLI step under `bash -eo
  pipefail`; the three YAML files parse (PyYAML) and pass a structural check
  (every action pinned by hash, no expression inside a run script);
  release.sh's `--check-tag` on a match, a mismatch, unset, a tag on another
  commit and an annotated tag (a scratch clone), and a dry run with a wrong
  tag stopping before it builds; the Xcode rule on two fake image layouts; `gh
  api repos/Saffsanity/sill` answers.
- Review fixes (one pass: triggers and permissions, secrets, the Xcode step,
  the cache, injected failures, costs, docs):
  - The Xcode step would have failed every job: the image's `bash` is 3.2 (its
    README), which ends a `$(` at a `case` pattern's `)`, so the loop listing
    the Xcodes stopped short and `sudo xcode-select --switch` was handed the
    rest of the script as a path (reproduced with `/bin/bash`; zsh parses it).
    The loop is a function now. The step takes `version` (27 in both
    workflows: the newest 27.x that is not a beta, compared as text, as awk
    finds 27.10 equal to 27.1) and `fallback` (CI: a warning and the newest
    Xcode there; release.yml: `false`, the job fails); the old message said
    the default stayed selected and exited 1. 13 fake layouts under
    `/bin/bash` with stubbed sudo, xcodebuild and swift; every `run:` block
    parses with `/bin/bash -n`.
  - The cache's `!.build/checks` excluded nothing: actions/cache 6.1.0 globs
    with implicitDescendants off and tars each listed path whole (its
    dist/save/index.js), so `.build` took `.build/checks`; now `.build/*` with
    the exclusion. `.build` is 196 MB here, 135 of it the SDK's precompiled
    modules, module cache and stat caches.
  - `run-all.sh` skipped a check whose `run.sh` had lost its exec bit (seven
    of nine skipped: "All passed.", exit 0) and died on an unbound array with
    none: now every folder with a `run.sh` is a check, a non-executable one
    fails, none at all is an error.
  - Failures injected in a scratch copy: a behaviour mutant for each of the
    nine (the ledger's made by hand), a compile error for each build style
    (swiftc in run.sh; build.sh without `set -e`; with `|| true`), a failing
    cross-check, two broken checks under `bash -eo pipefail` (exit 2), a
    no-op mutant (`--mutants` fails on 14 of 15): every one fails as it
    should.
  - CI's concurrency group has the event, so a push to main no longer cancels
    a mutants run started by hand, nor the other way round.
  - The iOS step builds arm64 only (`ARCHS=arm64`; the generic simulator
    destination also compiled every file for x86_64): 61 compiles, 43 s of CPU
    here, `** BUILD SUCCEEDED **`, only the StreamClient warning.
  - `release.sh --publish` asks gh in its preflight whether it reaches the
    repository and whether the release exists, before building; both used to
    surface only after notarization (a stub gh: exists, missing, no access,
    no gh; `--dry-run` and `--check-tag` make no gh call).
  - The checklist's costs, against the fetched pages: they print no multiplier
    table any more (the prices' ratio is still ten), a budget stops usage
    only with "Stop usage when budget limit is reached" where offered, 15 to
    20 CI runs a month fit in Free's included minutes, the mutants take about
    an hour and a half (some 900 included minutes).
- **Untested, for Noah:** every run on GitHub (the first will be this
  branch's pull request: a draft counts too). The keychain and notary steps
  never ran (they change the keychain search list and the default keychain,
  which is not for this Mac), nor make-app.sh's Quick Look icon, spctl or
  notarytool on a runner. The steps: decide public or sill-site; set the secrets
  (`gh secret set`, the checklist); push a tag with the variable unset and
  try the artifact; then set `SILL_SIGN_IN_CI` and push the next tag. Costs:
  free once public; private, about 10 minutes a CI run against roughly 200
  included macOS minutes a month on GitHub Free (a macOS minute counts ten),
  then $0.062 a minute with a payment method on file, and nothing without one.
  Since (2026-09-27): CI runs on pull requests and pushes to main, and the
  release workflow's verify job ran for v0.3.0 and v0.3.1 (make-app.sh's Quick
  Look icon on the runner included); the repository is public, so the runs
  cost nothing. The sign job never ran (no secrets are set, and
  `SILL_SIGN_IN_CI` is not), so both releases were published by hand with
  `release.sh --publish`.
