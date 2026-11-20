**The wire: kind numbers held for the camera, the microphone, files and the pen, and kind 47 in the compatibility floor (2026-11-18, branch `reserve-kinds` from main at 8dbbb50, main at eb48ac9 merged in since; draft PR #392).**
Noah, 2026-11-18: "Work on #200, … microphone passthrough to Mac with toggle, screen recording, camera from iOS
passed to Mac, share files and photos between iOS and Mac, Privacy mode options (blank local display when remote
access is being used)". The overview of those six (sill-handoff's `next/OVERVIEW.md`, §1.1, §1.4 and §4.1's first
item) gives each new kind its number; this, the first step of its order, writes the numbers where every branch reads
them, so that no two branches take one. Comments and Markdown only: no code, wire, check or behaviour changes.
- What, in `Sources/StreamProtocol/StreamMessage.swift`: the comment above kind 47 says that 45 and 46 are held for the
  pen and the camera, and that 47 and the Desktop's three fields are in the floor since both apps' 0.6.2; a list of the
  held numbers right before `unknown = 255`: 29–31, 33 and 35–42 #66's (#158's 33, `editableFocus`, for #158 and #66
  to settle); 34 files' bytes, both ways, as #66's `FileChunk`; 45 the pen (#175, #381, #382); 46 the camera (#193),
  types 1 and 2 device → host, type 3 host → device; 48 the microphone (#191, redone), types 1 to 3 device → host; 49
  files' `FileTransfer`, both ways; 50 #175's `cursorKind`, host → device, moved from 46; 51–59 and 62–249 free; 60
  and 61 #195's relay; 250–254 never a kind (the checks' mutants renumber onto them, docs/audio-plan.md §3.1). A number
  becomes a case only in the work named for it, which takes its line out as it adds the case; a new claim adds a line.
- What, in the compatibility floor (docs/COMPATIBILITY.md; written in CLAUDE.md's section, below): kinds 0–28, 32, 44
  and 47; "29 to 31, 33 and 35 to 42 stay free, pull
  request #66's" (34 is files' now, OVERVIEW §1.1); 34, 45, 46, 48 to 50, 60 and 61 held, as StreamMessage.swift's list
  says, where every new kind's number is claimed first; and the Desktop's stops: `desktopDisplays` (how many, 2 or
  more), `desktopDisplay` (the one shown, or come back to, from 1 in the order a step goes) and `desktopDisplayNames`
  (each stop's name, empty when it has none), all three left out with one stop, while the Mac is locked or another
  user is on its console, and by every host before them; kind 47 empty, only to a host that says 2 stops or more, the
  next stop; and, since 0.6.2's host reads no payload (StreamCoordinator's `.nextDisplay` case), a later device's
  payload (#296's `{"number": n}`) only to a host that says it takes one.
- Why the floor gains 47 now: the Desktop's stops shipped in both apps' 0.6.2 (#355, on addhumal's #173; Sill for Mac
  0.6.2 on GitHub on 2026-11-16, Sill 0.6.2 on the App Store on 2026-11-17), and the desktop-displays step file had left
  them out only because no public build carried them. The other new kinds and fields join the floor once a public
  build carries them (OVERVIEW §2.7).
- Where it went: the floor's lines were written in CLAUDE.md's Compatibility floor (a7ea609); #388 merged into main
  minutes later, moving that section word for word to docs/COMPATIBILITY.md, and main's merge into this branch
  (e74aa6e) carried them there with `Scripts/migrate-notes.py`, so CLAUDE.md here is main's lean file, unchanged.
  docs/LAYOUT.md's entry for Audio.swift still says "29 to 31 and 33 to 42 are PR #66's": why 43 was taken in
  2026-10, left as it is.
- Defaults taken for Noah to confirm (OVERVIEW §1.4 and its decision 11): the pen keeps 45, which #175, #381 and #382
  all use, and the microphone, which #191 put on 45, is redone on 48; the camera keeps 46, which main's comment gave
  it, and #175's `cursorKind` moves to 50, which its author has not been asked about (decision 11 has Noah ask him);
  files take 34 in #66's layout, as the clipboard took 32, and 49 for `FileTransfer` (the files plan asked for 48,
  which the microphone plan asked for too); #158's 33 against #66's stays theirs to settle.
- For the branches that add these cases (nothing here changes a check): `compatibility`'s mutants "kind 47 as 48 (the
  Desktop's next stop)" and "kind 47 as 46 (an open pull request's)" stop compiling once 48 and 46 are cases, and a
  mutant that does not compile counts as not caught, so the microphone's and the camera's branches move them onto
  250–254, as docs/audio-plan.md §3.1 did for 29; `compatibility`'s check that 45 and 46 are not this build's,
  `pointer-control`'s list of the kinds this build does not know and `display-wake`'s count of kinds (34) change with
  each new case.
- Verified: the diff is comments and Markdown only; every string the checks' scripts use that occurs in the two files
  occurs as often as before, so no mutant's pattern moved (the `case … = N` lines are as they were); `repo-rules` 10 of
  10 rules; `compatibility` 165 checks; `Tests/checks/run-all.sh` all 74 checks passed (666 s, through heavy.sh), among
  them the ones that compile StreamMessage.swift (`protocol`, `pointer-control` 160, `display-wake` 272, `clipboard`
  340, `menus` 309, `message-reader`, `viewport-bounds` 87, `lock-policy` 1,411) and `desktop-displays` 140, the
  Desktop's stops, on a7ea609 before main's merge; after it, on e74aa6e, `repo-rules` 11 of 11 (its new rule: CLAUDE.md
  at most 12,000 bytes), `protocol`, `compatibility`, `home-txt` 49, `key-strokes` 505, `pointer-control` and
  `display-wake`, the checks #388 touched and the kind tables, and the patterns again against main's two files. The
  mutants were not run: no pattern they apply moved.
- Nothing for Noah to try: no build changes. No words for the site, What's New or the review notes: nothing a person
  sees changes.
