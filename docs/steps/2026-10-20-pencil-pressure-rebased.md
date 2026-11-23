**Apple Pencil pressure and tilt (2026-10-20, branch `pencil-pressure-rebased` from main at d1fa97e,
main at 9a8e30c merged in since: Hunter Ahlquist's `pencil-pressure` (HunterAhlquist/sill at a85fba7;
issue #81) merged as it is, his five commits keeping their authorship, then the maintainer's;
docs/pencil-pressure-plan.md has the plan, the open questions with their defaults, every result and the
rebase).** Noah: "Work on Apple Pencil pressure (the contributor's work needs a free message number, 44
or above …)". A Pencil on the stream draws as a tablet pen in a Mac app that reads `NSEvent`'s pressure
and tilt, and is the mouse everywhere else.
- Wire: kind 45 `pen` (Pen.swift: `PenInput {phase, samples}`, six phases, at most 32 samples), only to a
  host whose window list says `pencil` 1; kind 26's `seen` counts kinds 8 and 45. 45, not the 29 it took on
  985a733: main keeps 29 to 31 free, 32 is the clipboard, 43 the Mac's sound and 44 the keyframe request.
- Host: `PenTablet` (pure) decides, `PenEvents` stamps the tablet fields on the mouse events Sill posts
  anyway and builds the proximity events, `InputInjector.pen` posts them on a button of the pen's own, as
  Sidecar's Pencil (mouse input never ends a stroke or takes the pen out of range). `in.pen`,
  `in.penProximity`; `SillHost --pen-selftest` (nothing posted); `PenProbe` (posts only with
  `--post-to-this-mac`).
- Device: `PenStrokes` (pure): a stroke's mode fixed as the tip lands, every coalesced reading, the leave,
  and the palm (finger strokes silent while the tip is down and 0.5 s after; on the picture the guard is in
  `handlePan` before #80's shared `scroll(gesture, .finger)`). Settings › This iPad: Pencil Pressure
  (`Sill.pencilPressure`, on, an iPad's only, never sent). The stale hover that drew a line back to each
  stroke's start goes nowhere; on main's mouse path alone that is the branch's first commit, 593cc12.
- The hover cursor (Hunter's db5e2ae, on top of the rebase; the plan's Q1, "The cursor while hovering"
  and "Only an app's own cursor"): while a Pencil hovers as a pen the device's arrow shows, in the Mac
  cursor's shape, only over an app's own cursor (a drawing app's brush outline), never over a standard
  arrow, I-beam or hand, and it hides as the tip lands. Kind 46 `cursorKind` (JSON `CursorKind
  {standard}`, host → device, just before each kind 14; the first number after the pen's), from the
  host's `CursorClass` (pure: the cursor's pixels against AppKit's standard cursors, or the window
  server's 1×–10× images); the device's `PointerPresence.Origin.penHover` and `cursorIsAppOwn`.
- Merged with main at 52dbbde (2026-11-02, Sill 0.6.1; one merge commit, not a rebase; 21 files
  conflicted, each settled keeping both sides). Main took 43 (the Mac's sound) and 44 (a device's
  keyframe request), so 45 and 46 stay this branch's; #191 (microphone, 45) and #193 (camera, 46),
  opened after this pull request, hold the same numbers, so whichever merges second renumbers. Where
  the Pencil meets main's new rules: a device the Mac no longer serves (`revoked`) and a locked Mac
  (`LockPolicy`) judge kind 45 as kind 8 (only what lets its pen go, `PenTablet.stillGoes`, from a
  revoked or locked-out device; StreamServer's revoked loop hands on an up, a cancel and a leave,
  `PenTablet.mayLetGo`; the held input's `.pen` the same; a paired session at a locked screen draws as
  it types); the lock gate withholds kind 46 with kind 14; `DisplayWake` counts kind 45 as a person's
  input; InputInjector's buttons carry their owner (`from device`), the pen's too; the palm guard ends a
  finger's scroll before main's picture zoom (`zoomStroke`) decides whose stroke it is.
- Merged with main at eb48ac9 (2026-11-18, after 0.6.2 and the lean CLAUDE.md, #388; one merge
  commit; 16 files conflicted). CLAUDE.md's entry, Layout, Build and run and Compatibility floor
  went where main's layout puts them through `Scripts/migrate-notes.py` (this file, docs/LAYOUT.md,
  docs/BUILD-AND-RUN.md, docs/COMPATIBILITY.md, the `pen` and `compatibility` checks' README.md,
  the latter's three copies made one). Main took 47 (`nextDisplay`, #91), so 45 and 46 stay this
  branch's and 48 is the first free number: the checks that said 47 is free (`compatibility`,
  `protocol`, `pointer-control`) say 48, main's check that 45 and 46 are not this build's names the
  pen and the cursor's kind, and the mutants that renumbered a kind onto a taken one (ours onto 47,
  main's 47 onto 46) use 48 and 251. Main's #401 (camera, 46) and another contributor's #381 and
  #382 (a pen at 45) now hold the same numbers too. InputOverlay.swift keeps this branch's side, as
  main's #322 (0844bdc) asked: PenStrokes.hover in place of its `pencilTouching` flag, which is
  gone. `lockDecision` takes the pen beside main's `arrived` and now readings; the cursor's kind goes
  with the cursor shape under `lockAllowed.pointer`; `DisplayWake` counts kinds 45 and 47 (its check
  36 kinds); `sendPen` counts as the person's use, as `sendInput` does since #230 and #291 (the
  auto-lock hold, Picture in Picture); the pointer feed's DEBUG line names a Pencil's phase. Not
  done: main's #228 (a press on a display that reads asleep only wakes it) reads kind 8 alone, so a
  Pencil tap on a black picture still clicks.
- After the merge (328314f): kind 45; PenStrokes.swift's project IDs A045/F045 (AC01/FC01 are
  HardwareKeyboardPolicy.swift's since #80); the workspace file out; privacy.html's Pencil items between
  `<!-- Pencil` markers (release-checklist part 1 §3 cuts them before the release); sillclient.py's
  `pencil=`; the docs.
- Verified (the plan's "Rebased onto main"): `swift build -c release` from `git archive`, only the
  CaptureProbe warning; the iOS app Debug and Release for the simulator and Debug for a device, only the
  StreamClient capture warning; `SillHost --pen-selftest` 37 of 37, nothing posted; `run-all.sh`, all 46;
  `pen` 197 and 5,000 sessions, 92 of 92 mutants; `compatibility` 157, 41 of 41; `pointer-control` 158,
  33 of 33; `protocol` 193 + 8, PROTOCOL of 24; `menus` 43 of 43; `fence` 33 of 33; H4 against main's
  CLI (idle identical; with a client identical but for when its stats seconds fell); H5 and S1 on
  loopback (this host: the pen's enter, tilt, pressure, drags, up and leave, a finger's tap as plain mouse
  events; main's host, and the app facing it: the mouse alone).
- **Untested, for Hunter and Noah (the plan's P0 per-app run and P1–P10, on a device):** pressure and tilt
  in Krita, Blender, Affinity or Photoshop, Pixelmator Pro, Aseprite and a browser canvas; hover, a
  resting palm, a stroke cut by a rotation, a pick or Wi-Fi; the switch; mixed builds; and on this rebase a
  finger's scroll, the iPad's trackpad and a wheel beside the Pencil. The README, the site's intro and the
  App Store's Pencil bullet wait for P1–P4.
