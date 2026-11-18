**CLAUDE.md lean: its Layout, Build and run and Compatibility floor move to docs, word for word
(2026-11-18, branch `lean-claude-md` from main at 8dbbb50).** Noah, 2026-11-18: "Keep CLAUDE.md lean
and prune MCPs. Unused MCP tool definitions and bloated project instructions get re-sent on every
agentic turn, compounding context size. Make sure to keep storing the data, but not in Claude.md,
feel free to store what you think makes sense in there." This is the CLAUDE.md half (the MCPs are
handled elsewhere). Documents and tooling only: no app code but comments, no wire change.
- Why: CLAUDE.md was 149,033 bytes (about 41,000 tokens), read whole into every turn of every session
  and subagent: its Layout 87,694 bytes, Build and run 46,917, Compatibility floor 10,231, Steps
  2,260, Decisions 1,059, Conventions 570.
- Moved: the three long sections, word for word, to `docs/LAYOUT.md` (87,884 bytes),
  `docs/BUILD-AND-RUN.md` (47,098) and `docs/COMPATIBILITY.md` (10,394), each under a title and a
  two-line note: what it is, that it moved on 2026-11-18, and how to read what it says of itself
  ("this file" in LAYOUT.md is CLAUDE.md, its "Build and run below" BUILD-AND-RUN.md, and "Current
  step" in BUILD-AND-RUN.md a step file). Proof, by a one-off script against origin/main: 1,814 lines
  moved (Layout 1,162, Build and run 537, Compatibility floor 115, headings and empty lines included),
  0 missing, each section's text one unbroken block, byte for byte, in its file (the headings stay in
  CLAUDE.md); with one line of LAYOUT.md changed it reports it missing and fails.
- Kept in CLAUDE.md (7,214 bytes): the intro, the four rules found in the steps, Conventions and
  Decisions, byte for byte, so other branches' merges meet as few changed lines as possible; Steps
  tightened, its sentence on a code comment that cites `CLAUDE.md, "<title>"` kept; a new rule, the
  file stays lean (rules and pointers only, Noah, 2026-11-18); and sections under the three old names,
  short, so that every older mention ("CLAUDE.md, Layout", "CLAUDE.md's Compatibility floor", in the
  plans and step files) still leads to the text: Layout a map (the code's five folders, a new iOS
  file's four pbxproj entries, where everything else is written), Build and run the three commands
  every piece of work runs, the headless test host's variables (`--synthetic` with
  SILL_TEST_LOOPBACK, SILL_TEST_SOFTWARE_ENCODER and SILL_TEST_NO_ROUTER, and SILL_TEST_NO_SCREEN
  unless a real window is needed), test input only to such a host and no test against GitHub, and a
  line saying to read BUILD-AND-RUN.md before running anything; the Compatibility floor its headline
  rules (additive only, kinds never reused, anything new only to a peer that said it takes it or
  skips it unharmed, a device refused and never served wrong, the protocol and the ALPNs).
- The guard: `Tests/checks/repo-rules` fails when CLAUDE.md passes 12,000 bytes, and its failure says
  why and where the rest belongs (LAYOUT.md, BUILD-AND-RUN.md, COMPATIBILITY.md, a step file). The
  check has no mutants. CI starts no run for a change to documents alone (ci.yml's `paths-ignore`
  has `**.md` and `docs/**`), so a pull request that grows CLAUDE.md and nothing else meets the guard
  in `Tests/checks/run-all.sh` run by hand, or in the next CI run that builds (it checks the merge
  with main); not changed here: a job of its own for CLAUDE.md is Noah's call.
- References made true: docs/DEVELOPMENT.md's five ("CLAUDE.md has the rest: the layout, ... every
  test hook", "CLAUDE.md, Layout, goes through the code", "CLAUDE.md, Build and run, has them all"
  and two more); the compatibility floor cited as CLAUDE.md in Audio.swift, RemoteTLS.swift and the
  home-txt, protocol and key-strokes checks (comments); the harness photos' cases ("CLAUDE.md's Debug
  harness"); release-ios.sh's warning ("the Layout note in CLAUDE.md"). Left as written on purpose:
  `docs/steps/` and `Tests/checks/HISTORY.md` (frozen); the plans' 127 mentions of CLAUDE.md, 52 of
  them its Layout, Build and run, floor or harness, which record each plan's work as it was done and
  still lead to the text through the same-named sections; the code comments that cite a step's title
  (`CLAUDE.md, "The 33 fps plateau"`, "trackpad stutter"), which the Steps sentence covers; README.md's
  "the conventions and decisions in CLAUDE.md", still true. The moved text itself is untouched, so
  LAYOUT.md's lines on `repo-rules` and `migrate-notes.py` do not name what this branch added to them;
  each one's own header and README.md do.
- `Scripts/migrate-notes.py`: right after `git merge origin/main` stops, it now also merges a branch's
  changes to the three sections (its text against the merge base's) into the file each moved to, and
  gives both texts main's short section before merging the rest of CLAUDE.md, for a branch opened
  before 2026-11-12 (its Current step entries moved as before) or after; a branch whose merge base
  already had the move is left to git. Tried in a throwaway clone on ten open pull requests merging
  this branch (#66, #71, #89, #100, #122, #166, #167, #175, #195, #207): every line they added to the
  sections reached the new file, every line they removed left it, CLAUDE.md came out as main's lean
  file plus their other changes (#207's section of its own, #167's line in Conventions), and #166's
  DEVELOPMENT.md as git's own merge; #100 and #66 keep one conflict each in docs/LAYOUT.md, the same
  one a plain merge of the section with main's own Layout meets. `--move-entries` finds nothing to
  move; `--verify 936d627` reports the same six check READMEs changed since the conversion as on main.
- For other branches: a branch that edits CLAUDE.md's Layout, Build and run or Compatibility floor
  moves those lines to the new file when it merges main: `python3 Scripts/migrate-notes.py` right
  after the merge stops does it (CLAUDE.md's Steps says so), or by hand.
- Verified: `Tests/checks/run-all.sh`, all 74 checks passed (11 min 44 s, on a Mac busy with another
  agent's simulator); repo-rules 11 of 11, and failing at 12,130 bytes. Nothing built, nothing run on a
  device or a simulator; nothing for Noah's devices.
