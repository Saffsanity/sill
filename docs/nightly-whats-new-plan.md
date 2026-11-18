# Nightly: What to Test on a build it did not upload

2026-11-09, branch `nightly-keeps-whats-new` from main at f224323d. Scripts/asc.swift, nightly.yml and a
new check, `Tests/checks/asc`. No app code, no wire change.

## What happened

On 2026-11-09 Sill 0.6.1 (1304) was uploaded to TestFlight by hand from main's head (the merge of PR #220,
f224323d, whose commit count is 1304) for the reporters of #215 and #322, and given What to Test of its own
(1,139 characters, the session's record) with `asc.swift distribute --public-beta`. That night's nightly (run 42593083786, 09:23
UTC) built the same commit, so the same build number: its upload step asked `asc.swift build-state`,
found 1304 VALID and skipped the upload, as designed ("App Store Connect has build 1304 of 0.6.1 already
(VALID): exported for the artifact, not uploaded again"). Its distribute step then gave the build the
night's notes ("What to Test set (English (U.S.), 736 characters)", 09:26:28 UTC) in place of the hand's
words, and the job's summary ended "Uploaded to App Store Connect and given to TestFlight's groups" though
nothing was uploaded. The words were put back by hand with `asc.swift whats-new`.

The cause, on main at f224323d:

- nightly.yml's distribute step (line 552) runs `asc distribute … --whats-new FILE` (line 572) whether or
  not the upload step (line 530) uploaded: it never knew.
- asc.swift's `setWhatsNew` (line 580) changes the build's English (U.S.) localization if one exists
  (PATCH, line 585), whatever it holds, for `whats-new` and `distribute` alike (lines 669 and 688).

Reproduced against the stand-in App Store Connect with main's asc.swift: a build with What to Test of its
own and the nightly's distribute call give `PATCH /v1/betaBuildLocalizations/l-1` with the night's notes,
"What to Test set"; and through nightly.yml's own two run blocks (the Results).

## The rule

- `asc.swift distribute` gives What to Test only to a build that has none: no localization, or only ones
  whose text is empty or white space. A build that has some, in any language, keeps it, and nothing is
  written ("What to Test left as it is: the build has its own already (English (U.S.), 1139 characters);
  distribute replaces it only with --replace-whats-new"). `--replace-whats-new` asks for the file's text
  whatever the build has, as every `distribute` did before; it goes with `distribute` alone and takes no
  value.
- `asc.swift whats-new` always replaces: it is how a build's words are set, or put back, by hand.
- nightly.yml's upload step (`id: upload`) writes `uploaded=true` once `release-ios.sh --upload` has
  returned, `uploaded=false` when App Store Connect had the build; the distribute step passes
  `--replace-whats-new` only when that output is exactly `true`. So a night that uploaded its build does
  what it always did (the same requests), and a build it found keeps its words, or gets the notes if it
  has none. The step says so in its log and notice, and the summary carries asc's "What to Test …" line.
- The job's summary says "Uploaded to App Store Connect" only for `uploaded=true`; otherwise that App Store
  Connect had the build number already and nothing was uploaded.

## Open questions, and the default taken for each

1. Which way round? Keep by default with `--replace-whats-new` to replace (taken), or replace by default
   with a `--keep-whats-new` the nightly passes when it skipped the upload. Taken because a command whose
   work is the groups should not overwrite words a person gave unless asked, by hand too (a cron that
   runs `distribute` again every half hour, as the watch on 1304 did, would put back its file over any
   edit made in TestFlight meanwhile), and because the workflow then fails safe: an output that is empty
   or anything but `true` keeps the words. Cost: `distribute` by hand on a build that has words keeps
   them; it says so and how to replace them.
2. "Has What to Test": any language (taken) or English (U.S.) only? asc.swift writes only English (U.S.),
   but words a person gave in another language are theirs too. English (U.S.) is named first when both
   have some.
3. A build the nightly did not upload that has no words (a night run again after its distribute step
   failed, a hand upload without What to Test): the notes go to it (taken), so testers see something, and
   no person's words are lost.
4. A build the night did upload that has words already (App Store Connect filling a new build's What to
   Test from the one before, if it does that through the API; or someone typing during the processing
   wait): replaced, as before (taken: "keep a run that did upload exactly as it is"). Whether App Store
   Connect pre-fills a new build is not known here; the summary's "What to Test …" line on the next night
   that uploads shows what happened.
5. The groups on a build the nightly did not upload: given as before ("only gives it its groups again"),
   the public beta group only while `SILL_NIGHTLY_PUBLIC_BETA` is true. Unchanged.
6. A hand `distribute` and the nightly both waiting on the same new build would both see no words, and
   the second POST gets App Store Connect's 409 (a localization exists) and fails that run. Not handled
   (a hand upload and the night of the same commit inside the processing window); run it again and it
   keeps the words.

## Results

All against the stand-in on 127.0.0.1 with throwaway P-256 keys; nothing called App Store Connect, and no
key of the app's was read. Evidence: ~/Downloads/sill-handoff/triage/2026-11-09/nightly/.

- `Tests/checks/asc` (new): the nightly harness of 2026-10-29 (PR #246: its 114 checks over 21 scenarios
  and the review's extras, until now outside the repository) brought in, every run of asc under
  sandbox-exec with only loopback allowed (checked first: a connection elsewhere is refused, EPERM), and
  What to Test's cases: 167 checks, 0 failing; against main's asc.swift 23 fail (the new ones). Its
  stand-in no longer looks up 127.0.0.1's name at bind (`socket.getfqdn` took 35 s here that day, past
  the harness's 5 s wait for the port: every scenario of the old harness failed until then).
- Mutants: the harness's 23 and 13 of the rule (distribute always replacing, the night of 2026-11-09;
  never replacing; replacing by default; the flag unread or ignored; `whats-new` keeping; kept and
  written anyway; only English (U.S.) counting; another language named first; white space, an empty
  text or none counting as words; the flag let through with `whats-new`): see the Progress line below.
- nightly.yml: its run blocks under /bin/bash 3.2 -eo pipefail with GitHub's files and stand-ins (the
  harness's `wf-blocks`, extended): the upload step for missing, VALID, PROCESSING and INVALID (the
  output, release-ios.sh with or without `--upload`, the notice) and a failed upload (no output); the
  distribute step for `UPLOADED` true, false, empty, TRUE, 1, yes and unset, each with the public beta on
  and off. The structural check (`yaml-check`, extended): the step's id, where each output is written,
  the wiring `${{ steps.upload.outputs.uploaded }}`, the flag only for exactly `true`, in one step, the
  summary line. Ten mutants of the gate. Numbers in the report.
- The night replayed through nightly.yml's own two iOS run blocks with the real compiled asc (through a
  wrapper that appends `--api-base` and runs it sandboxed to loopback) against the stand-in: main's
  workflow and asc replace the hand's words (the incident), this branch's keep them; a fresh upload, an
  upload onto a build with words and a hand upload without words send the same requests on both.

## For Noah

- The next night that uploads: its summary says "What to Test set (English (U.S.), N characters)". A night
  whose build is already in App Store Connect (one you uploaded by hand from main's head): "This run did not
  upload build N", and "What to Test left as it is …", the build keeping your words.
- `asc.swift distribute` by hand now keeps a build's words unless given `--replace-whats-new`;
  `asc.swift whats-new` replaces as before.
