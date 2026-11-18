**Nightly builds (2026-10-29, branch `nightly-builds` from main at 35a9c47c, PR #246; issue #134;
the brief and its Progress are in ~/Downloads/sill-handoff/nightly-plan.md, the procedure in
docs/release-checklist.md, "Nightlies").** Noah: "Setup the nightly build strategy" (the nine secrets set
2026-10-29), then, before the build: "hold off on giving the testflight build to public beta until I try it
out in Insiders first tomorrow". Merge "Version 0.5.5 for both apps" (PR #244, branch `version-0.6.0`) first.
- `.github/workflows/nightly.yml`: 09:17 UTC while the repository variable `SILL_NIGHTLY` is `true`, and by
  hand (`verify_only` forces the ad hoc, no-upload path); a scheduled night whose main is the sha at the end
  of the pre-release's notes builds nothing; only main publishes. decide writes the night's words once
  (`Scripts/nightly-notes.sh`: the pull requests merged since the newest `v<version>` tag) and fixes the
  date and build number (the commit count). Sill for Mac: the pure checks, then with `SILL_SIGN_IN_CI`
  release.yml's keychain and notary steps, the profile decoded from `SILL_PROVISION_PROFILE`, and
  `release.sh --nightly --publish` (built and checked as a release, but universal: `SILL_UNIVERSAL=1`, as the
  first nightly by hand and #62's word on the next version; no tag rule, the profile required) as
  `Sill-nightly-<yyyymmdd>-<sha7>.dmg` and `.zip` with their `.sha256` on the rolling pre-release
  `nightly` (never latest; its tag moved to the commit; the seven newest kept; the commit's sha last in its
  notes); else ad hoc artifacts. Sill for iPhone and iPad: `release-ios.sh --build-number <commit count>`
  (unsigned, export or upload as testflight.yml; with the key, `asc.swift groups` first, reads only, the
  real group names in the summary; an upload App Store Connect has already is skipped), then
  `Scripts/asc.swift distribute`: waits up to 90 minutes for processing, What to Test, every internal
  TestFlight group, and the public beta group (the external group with the public link) only while
  `SILL_NIGHTLY_PUBLIC_BETA` is `true`, with Beta App Review right after; asc.swift refuses `--public-beta`
  unless its environment says that too. Unset at first, on Noah's word.
- A nightly is main's version with the commit count N as its build on both apps, never committed: 0.5.5 (N)
  until 2026-10-31, 0.6.0 (N) since (the 0.6.0 release's own builds are 0.6.0 (1276)), 0.6.1 (N) once main
  moves on after App Review approves 0.6.0. The update check never offers
  one (`UpdatePolicy.feed` is /releases/latest, which lists no pre-release; `UpdatePolicy.release` refuses
  `prerelease: true`; "nightly" is no version), and offers a nightly nothing until a release newer than its
  version exists. A nightly reads the release's data-protection keychain items (same team, bundle ID and
  profile), so a device paired with one stays paired with the other.
- Also: release.yml's publish job decodes `SILL_PROVISION_PROFILE` too (the nightly turns on
  `SILL_SIGN_IN_CI`, which arms it; without the profile a CI release would have moved every Mac to the
  login keychain); testflight.yml takes the commit count as its build number; `release-ios.sh
  --whats-new FILE` (with `--upload`, `--api-key`) sets What to Test after an upload; make-app.sh's
  `SILL_RELEASE_NIGHTLY=1`; README's Good to know and site/download.html one line each.
- Verified (the plan's Progress has every number): asc.swift against a stand-in App Store Connect on
  127.0.0.1 with a throwaway P-256 key (each token's ES256 signature checked with openssl; header, claims,
  exp − iat 900 s), 114 of 114 checks over 21 scenarios and 23 of 23 mutants, the token in no output;
  release.sh's nightly mode and nightly-notes.sh against a stand-in gh in a synthetic repository, 103 of
  103 (the release path's 15 preflight cases and publish_release identical to origin/main's in words, exit
  statuses and gh calls); release-ios.sh against a stand-in xcodebuild playing run 40843967209's real
  .ipa, 48 of 48 (its App Store path identical to origin/main's); 30 of 30 mutants of the new shell paths caught (15 in release.sh's nightly mode and its release path, 7 in nightly-notes.sh, 8 in release-ios.sh's flags); the workflows: 5 files
  parse (PyYAML), 46 run blocks under /bin/bash -n, 200 structural checks (actions pinned by the commits
  already used, no expression in a run script, secrets only in env, the gates); nightly.yml's run blocks executed under /bin/bash 3.2 -eo pipefail with GitHub's output, env and summary files and the stand-ins, 44 of 44 (decide's skip rule on a schedule only, publishing only from main and not verify only, the notes through the outputs, the Mac's and the iOS mode matrices, `--public-beta` only for exactly `true`), and 8 of 8 mutants of its gates caught; a 12-minute real-time wait (the build listed after 11.5 min, a look a minute): 20 requests, every token valid, renewed once at 600 s; on GitHub
  `gh workflow run testflight.yml --ref nightly-builds` with `SILL_TESTFLIGHT_IN_CI` unset (`gh variable
  list` empty) → run 40843967209 passed: Xcode_27.1.app 27A9275, archived with CURRENT_PROJECT_VERSION=987,
  exported through the key; the downloaded .ipa says 0.5.1 (987) while the project says 4, signed "Apple
  Distribution: NOAH WILLIAM SAFFER (9B2KKVM937)", the App Store profile, get-task-allow false; nothing
  uploaded. Tonight's real notes: 36 pull requests since v0.5.1, What to Test 3,179 bytes. nightly.yml
  itself runs only once it is on main.
- The review (2026-10-29, after ba85e191; the plan's "The review"): seven findings, each reproduced, then
  fixed in a commit of its own. testflight.yml uploaded from any branch with the commit count, so a branch
  four commits ahead of main had the count of a later nightly, which took the branch's build for its own
  and gave it to TestFlight's groups (both workflows' run blocks in a synthetic repository): uploads only
  from main's first-parent line now, other branches export (7c62d6c1; the mode step 12 of 12, 9 before).
  The first nightly, published by hand that morning (0.5.5 (987), tag `nightly` at 150479b5), is universal
  and its notes give the TestFlight public beta link: the workflow's Mac job builds with `SILL_UNIVERSAL=1`
  (598d68be) and `nightly_testflight_link` keeps the link in every night's notes (0458239d; the hand-made
  pre-release taken over with the stand-in gh, 8 of 8, 7 before). A malformed .p12 or notary key ended at
  security's or notarytool's words with the file left until the cleanup: named errors in nightly.yml and
  release.yml (2623acee; 16 of 16, 4 before). The distribute step's 100 minutes equalled asc.swift's 90 +
  10 (measured: 300 s of processing, then 601 s for the review state): 110 (86e59547). Docs: the privacy
  manifest's ActiveKeyboards is PR #243's, on main (e3dbf133); part 2 contradicted Nightlies on the iOS
  build number, and a release must move main to the next version before the next night (df11fb07).
  Re-run, all passing: asc.swift 114 and the review's 9, 23 of 23 mutants, a 13-minute token wait (20
  requests, renewed at 600 s); release.sh and the notes 104 (a link check added); release-ios.sh 48; 31 of
  31 shell mutants; the workflows 204 structural checks and 46 blocks under bash -n, 44 of 44 run blocks
  executed; the signing run's artifact rechecked (0.5.1 (987), Apple Distribution, get-task-allow false).
  Not changed here, for the session that talks to Noah: the version (the handoff records his 08:55 UTC
  decision that pre-release builds say 0.5.5 and the release 0.6: #244 and these docs say 0.5.5 since the main session's fix-up of 2026-10-29) and the hour (09:17 UTC, applied the same way); PR #247's README and download-page words repeat this one's.
- The environments (2026-10-29, the security batch's item for the scan's findings 5 and 6; Noah: "the
  environments as a checklist step before SILL_SIGN_IN_CI goes on"): the nine secrets were repository
  secrets, which reach a run on any branch or tag, and release.yml and testflight.yml run by hand from
  any ref with that ref's scripts. release.yml's publish job now runs in the environment `release` (only
  `v*` tags; Noah its required reviewer, so a release waits for his click), nightly.yml's Mac and iOS
  jobs and testflight.yml's job in `nightly` (only main; no reviewer, so a night runs unattended). An
  environment without its secrets gives empty strings, so each job names the environment and what is
  missing when the run needs it: release.yml's first step, before the checkout (it also stops a run by
  hand that didn't start from the tag it releases); the nightly mode steps as before, in the
  environment's words, a notice when the iOS key is absent. decide builds nothing off main; testflight.yml
  runs from main only (its first-parent check kept). docs/release-checklist.md, "Secrets and variables":
  the step before the variables (the two environments with `gh api` PUT and their branch and tag
  policies, written from GitHub's REST reference and not run: nothing may be created here; the check
  with `gh api` GETs; the secrets with `--env`; the nine repository secrets deleted), and Nightlies'
  first run gains it as step 4; DEVELOPMENT.md's three paragraphs. Verified: the workflows' structural
  check 245 of 245 (its stale 03:17 rule moved to 09:17, 41 new for the environments; 25 problems on
  984d7f0c), 46 run blocks under /bin/bash -n; nightly.yml's run blocks executed 52 of 52 (9 failing on
  984d7f0c); the environments' run blocks 19 of 19 (16 failing on 984d7f0c); testflight.yml's mode 12
  of 12; the keychain steps 16 of 16; 15 of 15 mutants of the environment rules caught; the look's jq
  filters against the documented response shapes, on the live endpoint (read-only: no environment
  exists yet) and, when the work resumed after a usage stop, on other public repositories' real
  environments (a tag rule with a required reviewer, a `main` branch rule), the REST reference read
  again (the PUT's fields; the POST's `name` and `type`, 404 without `custom_branch_policies`, 303 for a
  rule already there); actionlint 1.7.12 with the `xcode-27` label declared: only the 17 shellcheck
  notes 984d7f0c has too; CI's Build and check on 5d2bb590 (run 40865615093). The checklist's
  TestFlight key line names the Admin key's own file, not the notary key's. The review (2026-10-29;
  four findings, all in the docs, each fixed in commits of its own; the report's "The review"): "What
  the environments don't do" understated the route through main: `nightly` holds the same Developer ID
  and notary keys as `release`, and the Admin key, so a commit on main reaches them, and the nightly
  Mac job's token that can publish any release, at the next run from main with no approval, and a
  ruleset requiring pull requests closes that only with a required approval, and then only against
  someone else's write access (78248187, 2596e910; a loopback run of the workflows' own steps on main,
  GitHub's rule emulated with Ruby's File.fnmatch, handed an attacker's release.sh the signing
  identity, the notary profile and the token, and release-ios.sh the key file); any `v*` tag waits on
  the approval alone, so What a tag does says to approve only the tag you pushed, on the commit you
  tagged (a7c6787e); testflight.yml no longer "exports other branches" (732c374f); steps 2 and 3 and
  the two variable lines lost their inline comments, which zsh as it starts hands to `gh` as arguments
  (39b9ecfd: pasted into `zsh -f -i`, 7 of 29 calls broken before, none after). The harness again on
  the head's workflows, unchanged by the review: 245, 52, 19, 12 and 16 of the same, 15 of 15 mutants.
  The second review (2026-10-29, on edda6b6e; the report's "The second review"): one finding, in the
  workflow. The approval is the tag route's gate, but the publish job checked out the tag by name, and
  given a ref actions/checkout v7.0.1 checks nothing against github.sha, so a tag force-moved after
  the run began (or right after the approval) built and signed another commit while Noah's look still
  matched (his local tag never moves). Reproduced on loopback (tag-move.py in nightly/tests: git
  daemon on 127.0.0.1, checkout's git sequence from its source, the job's own steps with stand-ins):
  the moved commit's release.sh got the identity, the notary profile and the token, a pushed tag, by
  hand and annotated alike. Now the checkout is `${{ github.sha }}` and the tag check stops the run,
  before the keychain and any build, when HEAD or the tag is not that commit (e6545f2b, with the
  checklist's What a tag does, a tag ruleset's part, DEVELOPMENT.md and release.sh's comment): the
  moved cases refused, the unmoved ones on. The harness on it: check.py 257 (12 new; 3 problems on
  edda6b6e), run.py 52, env-steps.py 26 (7 new; 4 failing on edda6b6e), tf-mode.py 12, kc-steps.py 16,
  rel-test 104, 21 of 21 mutants (6 new), zsh-paste 36 calls exact, actionlint's 17 notes as before.
- **Untested, for Noah (docs/release-checklist.md, "Nightlies", "The first run"):** the privacy
  manifest's ActiveKeyboards (#147's `UITextInputMode.activeInputModes`, ITMS-91053) is declared on main
  since PR #243 (54BD.1; release-ios.sh's check of run 40843967209's binary against main's manifest: every
  API declared). Merge #244, then this; the environments `release` and `nightly` with their rules, the
  secrets in each, the nine repository secrets deleted ("Secrets and variables", steps 1 to 3: the `gh api`
  calls were never run); `gh workflow run nightly.yml -f verify_only=true` and its artifacts (the iOS key
  from `nightly`); the first release through the environment `release` (its tag check passes on the
  run's own commit, which the run's page shows);
  `SILL_SIGN_IN_CI` and `SILL_TESTFLIGHT_IN_CI` true; a run by hand: the pre-release, the notarized dmg on
  a second Mac (quarantined: opens, drags, opens, the iPad still paired), TestFlight's groups (the real
  names: the step lists them) and What to Test; `SILL_NIGHTLY` true; after his Insiders test,
  `SILL_NIGHTLY_PUBLIC_BETA` true (Test Information filled in; the first build of a version reviewed in full).
