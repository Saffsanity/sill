**Branches out of each other's way, and harness photos on shared simulators (2026-11-12, branch
`tooling-speedup` from main at 936d627, PR #356 (a draft), whose description has the numbers).** Noah: "is
there a task that you are wasting a lot of cycles on that could be scripted to be faster to cut down
the time per agent?", then "Script it"; then "I think lets ignore the mutants thing because that
carries too much risk but your other ideas work", and of the mutants job's limit, "Raise it please".
Tooling and documents only: no app code, no wire change, no check's output changed.
- Why: every branch added its notes at the top of CLAUDE.md's "Current step", a row to the table in
  `Tests/checks/README.md`, and its check's name to ci.yml's one-line mutants matrix, CLAUDE.md's
  Layout and DEVELOPMENT.md's list of checks, so each merge into main made every other open pull
  request conflict at those lines (about fifteen such merges by hand on 2026-11-11). The table had
  kept rows two to four times with stale counts, and CLAUDE.md had grown to 777,257 bytes, loaded
  whole into every agent's context.
- Notes: the 85 entries of the old Current step and the two milestones are `docs/steps/<date>-<branch>.md`,
  one each, word for word (`Scripts/migrate-notes.py --convert`; `--verify 936d627` checks it, and every
  non-empty line of the old section is in them in its order); `docs/steps/README.md` lists them in
  their old order, frozen. CLAUDE.md keeps what every task needs and a "Steps" section: where the
  notes are, how to add (`Scripts/steps.sh new`), list (`list`) and find (`find 349`) one, and pointers
  to the rules that hold for all work. 777,257 bytes before, about 137,000 after.
- Checks: each folder's own `README.md` (its name as the heading, **Checks:**, **Compiles:**), made from its
  row(s) with the counts left out (a check prints its own); where merges had kept a row more than
  once, every different text is kept, to be made one when the check next changes. The old README is
  `Tests/checks/HISTORY.md`, frozen. `Tests/checks/list.sh` prints them all, so no table or list of
  checks is kept by hand (not in that README, CLAUDE.md's Layout or DEVELOPMENT.md).
- CI: the mutants matrix comes from the folders (`Tests/checks/mutant-checks.py`), checked before
  any mutant starts against `git ls-files 'Tests/checks/*/mutants.py'` (empty, not JSON, a name
  twice or a check left out fails the run, and writes no matrix); the mutants job's limit is 120
  minutes (Noah, 2026-11-12: remote-rules' 124 mutants take about 58 minutes here, and a job cut off
  at the limit shows red and loses its results). Nothing else about the mutants changed.
- `Tests/checks/repo-rules`: fails a check folder without its README.md, a table or a static
  mutants list coming back, a step entry written into CLAUDE.md, a badly named or empty step file.
- `Scripts/migrate-notes.py`: a branch opened before this runs it once, right after `git merge
  origin/main` stops: its entries become its own step files (a changed old entry is merged into its
  file), its rows its checks' README.md, its other changes to CLAUDE.md, DEVELOPMENT.md and ci.yml are
  merged three ways into main's, and the result is staged; `--move-entries` moves an entry written
  into CLAUDE.md by habit afterwards. Tried on scratch copies (never pushed) of all five open
  branches, this branch standing in for the new main: each resolved in about 2 s, repo-rules held,
  each result merges into this branch without a conflict, each step file is its entry word for word,
  and every other line the branches added to CLAUDE.md is kept but their names in the old list of
  checks. Migrated, picture-in-picture and one-click-update (which today conflict with each other in
  ci.yml and CLAUDE.md) merge with each other with no conflict at all; version-label and
  picture-in-picture had conflicted only in iOSClient/ContentView.swift, their real overlap.
- The first merge of main (57a6d86, #351 the version label) as a test: git stopped on CLAUDE.md (a
  7,734-line and a 73-line hunk), Tests/checks/README.md (150) and ci.yml (5); `--absorb` (the
  migration with the sides swapped, for this branch until it lands) settled them in 1.8 s, and
  `--verify origin/main` found all 88 entries and 88 rows of main where the layout puts them, word
  for word. Had #351 already used the layout, its merge would have stopped on nothing: version-label
  in the new layout merges into this branch with no conflict.
- Harness photos: `Scripts/agent-simulators.sh` made "Sill agents Duo" (iPhone Duo, iOS 27.1) and
  "Sill agents iPad" (iPad Pro 13-inch (M5), iOS 27.0: the 27.1 runtimes refuse any device but the
  Duo, "Incompatible device"); `Scripts/harness-photos.sh` builds a commit once, photographs a cases
  file on one of them inside the heavy lock and compares a baseline pixel for pixel. Its first run
  (version-label against a main that already held it) gave twelve black photos, all "identical": a
  new Duo boots closed and the default screenshot is the dark inner display. So each Duo case now has
  a pose (Tests/duorig, flat-portrait unless the case says otherwise), set once the app is in front,
  the screenshot is that pose's display, and a photo of one colour is BLANK and fails the run. The
  second run (2026-11-12, 02:44, after 822 s waiting for the lock; builds of 27 and 20 s, then
  cached): main at 57a6d86 against 936d627, seven cases on "Sill agents Duo", 133 s with the
  simulator: four identical, duo-connect and duo-settings-end showing #351's version line ("Sill
  0.6.1 (4)" in the footer: 2,121 pixels, 37x207, at 218,1630; the Settings panel's end, 13.9 %),
  and duo-cover a 105x137 patch off by at most 2 levels (identical with `--tolerance 2`). The pair
  is left shut down: the Duo 2.11 GB after its first boot, the iPad 0.02 GB (never booted); the
  cache in ~/Library/Caches/SillAgents 0.27 GB.
- Findings, not changed (the mutants runner was dropped): a mutant that makes a check crash before
  it prints a FAIL line counts as not caught where the script judges by FAIL lines alone (addresses,
  origin, pairing-address, remote-rules and protocol; menus needs both a FAIL line and a failing
  exit), and addresses, origin, pairing-address and menus do not flush, so FAIL lines printed before
  a crash are lost too; seven scripts count a mutant that no longer compiles as caught
  (catalog-windows, installed-apps, keychain, pairing-sharing, settings-window, test-host,
  virtual-display-api), the rest as not caught; a hung mutant ends the run with a traceback in 43
  scripts and in module.py's checks (a timeout with nothing to catch it), hangs it for good in seven
  (no timeout: addresses, asc, clientlink, origin, pairing-address, policy, remote-rules), counts as
  caught in seven and as not caught in text-composition.
- **Untested, for Noah:** CI's mutants run by hand once (the list job, then 66 jobs; the guard has only
  run here); each open branch's owner running the migration at their next merge of main; and
  `git -C ~/Downloads/winstream pull --ff-only` once this merges, so sessions opened there load the
  lean CLAUDE.md (that clone is on main at 5c323e6 with a 464,099-byte CLAUDE.md).
