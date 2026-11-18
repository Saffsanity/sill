**A nightly is offered the release of its own version (2026-11-15, branch `release-over-nightly` from main at a025d9e, with main's 4d12c46 merged).**

- **Asked for.** Noah, 2026-11-15: "Someone on a 0.6.2 nightly should get offered official 0.6.2 release." Until
  now a release was newer by its version alone, so the people on a version's nightlies (the candidate's testers)
  saw nothing when that version was released and waited for the next one. Asked what a nightly built after the
  release should get (main keeps a version until App Review approves the release, so such nightlies come for
  weeks): it keeps waiting for the next version, since the release would be older code ("Second case yes").
- **The rule** (`UpdateInstallPolicy.isNewer`, one function behind the offer, GitHub's answer, `prepare`, the
  downloaded app's verdict and the automatic start): a higher version always; within this Sill's version a
  nightly by a higher build, and a release only over a nightly, when its build is at least the nightly's (the
  same commit or a later one). The release's build is its manifest's, signed with the update key.
- **Read before any offer.** Only the signed build tells, so a nightly reads the latest release's manifest
  first (`AppUpdater.lookAtRelease`, `UpdateInstaller.releaseBuild`, which is `prepare` run early: the listing,
  the manifest, a stop): after a check that answered, and at launch only while the daily check is on; only for
  the signed release of its own version; once for each release (`releaseLookDue`). No release is offered that
  Update Now would refuse. One log line says what it found: "Update: Sill 0.6.2 is build 1604 and this nightly
  is build 1600: the release has this nightly’s code, so it is offered."
- **The same version and the same build.** A release tagged on the candidate's own commit has the nightly's
  version and build, and the pending note named the new copy by exactly those. The note's fourth line, its
  channel, now counts (`noteNames`), at the launch that follows an update, for a copy the watcher kept, and at a
  quit: without it the nightly that was replaced would have answered the watcher for the release as it quit, and
  a nightly the watcher put back would have taken itself for the update that worked.
- **The automatic update** treats that release as any release (two days after the first sight, the quiet
  minutes). `UpdateAutoPolicy.bounded` keeps what a nightly remembers of its own version's release (the first
  sight, a stop, the attempts): it dropped everything not above the running version, which would have started
  that release's wait over at every write.
- **Words.** Under the switch: "…Sill keeps the nightly you have until a release that is at least as new." and
  "You have a nightly build, 0.6.3 (1520). Sill updates to the next release that is at least as new." A
  failure's line and the menu name a nightly with its build ("Sill 0.6.2 didn’t start, so Sill nightly 0.6.2
  (1597) is back.", "You have nightly 0.6.2 (1597); update it in Settings"). The site's support page says the
  same as the switch.
- **Found on the way.** `Tests/update-harness` did not compile since #375 (UpdateInstaller uses ProcessLife,
  which run.sh did not copy), and its case "a process running from it" counted a process the harness starts
  itself, which the look leaves out since #375 (a helper Sill is starting is no other copy of Sill). run.sh
  copies ProcessLife; the case starts its other copy through a shell that exits, and checks that its own child
  is left out. Four of the harness's own mutants name the installer's check lines as they are now.
- **Verified.** `update-install`: 1061 of 1061 (61 new checks; 39 new mutants, 9 with their lines as they are
  now; every one of its 216 mutants run). `Tests/update-harness`: 296 of 296, with six new cases (the release
  installs over a nightly of its version built before it and on its very commit; refused over one built after
  it, over one whose build isn't known, over a release of its version, and a lower version over a nightly) and
  the look (the build read; none of a release that moved on, isn't signed or is stopped). `swift build -c
  release`.
- **Not tried.** On a real Mac with real releases: the first one is 0.6.2 itself, for whoever runs the
  candidate nightly. VoiceOver for the new words.
