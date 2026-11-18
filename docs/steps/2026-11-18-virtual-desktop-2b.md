**The Virtual Desktop, phase 2b's first part: the modes probe and one manager for every display Sill makes (2026-11-18,
branch `virtual-desktop-2b` from `virtual-desktop-2a` at 84d60f3, draft PR #395, which merged main at eb48ac9; phase 2b
of `docs/virtual-desktop-plan.md` as revised 2026-11-18, the revision in
`~/Downloads/sill-handoff/next/virtual-desktop/plan.md`; draft PR #408).** Noah's words, 2026-11-18: "Work on #200, the
option to give Sill its own virtual display (for headless macs or for adding an additional screen, if so allow the user
to select resolution, should default to resolution and refresh of client device, not what we originally proposed)".
Phase 2b is the Virtual Desktop itself: its switch at both ends, its stop after the Mac's screens, its size by default
the device's room and rate, its lifetime, its windows, following the device's turn. This first part is the plan's
commits 1 to 3 of twelve; nothing a person sees changes, and nothing changes on the wire.
- The modes probe, P2 (commit 1, TEST ONLY): can Sill's Desktop display take a device's turn without being removed and
  made again (plan §5)? `VirtualDisplay` is made with more than one mode when asked (`otherModes`: the asked mode first,
  then the others, each once, `modeList`; the descriptor's maximum sized for the largest, `maxPixels`; none by default,
  so every display Sill makes is made as before), moves the live display to another listed mode with public
  CoreGraphics (`switchMode`: `selectRequestedMode`, CGConfigureDisplayWithDisplayMode, as `waitUntilOnline` already
  selects the mode asked at creation), and takes a new list on the live display (`applyModes`: `applySettings:` sent
  again). Nothing in Sill calls the last two. `Scripts/display-modes-probe/run.sh` builds `probe.swift` with
  VirtualDisplay.swift alone: its dry run, the default, looks up the private API (no display) and prints the modes, their
  backing and the steps; `--make` is Noah's (below).
- `SillDisplays` (commit 2): every display Sill makes, in one place (plan §9). For each role (`SillDisplayRole`, pure:
  the stage's "Sill" 0x5111/0x0001/1 since milestone 3, the Desktop's "Sill Desktop" 0x5111/0x0002/2 since #200; macOS
  remembers a display by them and DesktopDisplays.role tells them apart by them, so they never change; the raw value is
  the guard's marker word) it makes the display with the role's identity, writes the guard for #380's marker (`willMake`)
  and takes it back when a make throws and once the wait ends, waits until the display is online and until
  ScreenCaptureKit lists it, hears it lost (the role's newest display alone, hopped to the main actor, handed to the
  role's `onLost`), removes it at once (`destroy`), and gives the stage's IDs to the catalog. The stage (VirtualStage)
  asks it for its display, in the order it always made it: the marker before its old display goes (#380's stops came
  right after "Removed virtual display N"), the make, the wait, the menu bar's measure and remake, the listing; with the
  same lines and failures. It keeps its window, its sizes and its menu-bar remake; `VirtualStage.vendorID` and the rest
  read the stage role's identity.
- The Desktop's display under it (commit 3): the display a Mac with no working screen gets (PR #200, phase 2a) is made,
  waited for and removed through it; the coordinator keeps no display of its own (`headlessDisplay` reads the `.desktop`
  role's). A test host's display that is only said to be made (SILL_TEST_HEADLESS) is `SillDisplays.say`, the seam the
  Virtual Desktop's dry run will go through; it counts as up for a test host's guard, as before. macOS's reconfiguration
  callback (#200's) is `watchReconfiguration`: one for the process, registered once, never removed, a change's
  beginning left out; the coordinator hears each change through it as before. Quit and the signals: the stage's window
  home and its display gone (`stage.release()`), then `removeAll`.
- One difference, in a race only (commit 3): a Desktop display removed while its make still waited for it to come up
  (at most 3 s, beside a removal that had waited 5 s for the switch to end) is destroyed at once and prints no "created"
  line; before, the wait's own reference kept it up until the wait ended, and its line and Settings' row then named a
  display already let go.
- Checks: `virtual-display-api` gains the modes (ModeSize.turned, modeList, maxPixels) and `init`'s and `switchMode`'s
  wiring read as text in the VirtualDisplay.swift it compiled (its build.sh now keeps that file beside the binary, a
  mutant's too); `sill-displays` (new) holds the roles' identities against DesktopDisplays.role and the guard's marker,
  and the wiring read as text (no display made anywhere but `SillDisplays.make` and the self test; each role's display
  made, waited for, listed, lost and removed there; the stage's marker before its old display goes; the said display;
  Quit; the one callback). `stage-release` is unchanged and passes as before.
- Wire: nothing. No kind, field or flag; the iPhone and iPad app is untouched.
- Docs: docs/LAYOUT.md (VirtualDisplay's modes, SillDisplays and SillDisplayRole, the probe), docs/BUILD-AND-RUN.md
  (the probe's command).

**Defaults taken for Noah to confirm:**
1. This part is the plan's commits 1 to 3 (the probe and the manager); 4 to 12 follow on this branch, each group pushed
   as it is done (the plan's order: VirtualDesktopLife, DesktopWindowLedger and `follow`; the wire's fields; the
   setting's places; the stop; the coordinator; the device; Sill.app; the CLI and gates; the words).
2. The probe's display is "Sill Probe" with the Desktop's vendor and product and serial 0xF00D, so macOS remembers
   nothing for Sill's own display; the room 1376 × 1032 (an iPad Pro 13-inch sideways) and its turn by default, at 60 Hz;
   refused while a Sill runs.
3. The Desktop's display gets no lost callback yet: as in #200 and #395, macOS removing it by itself is found at the next
   Desktop (offline) and it is made again. The plan's §6 ("when macOS removes it (its termination handler)") comes with
   the Virtual Desktop's lifetime, commit 8.
4. The race above: removed during its make's wait, destroyed at once, no "created" line.
5. A check of its own, `sill-displays`, for the identities and the wiring, rather than growing `stage-release`.
6. No switch in this part. The Virtual Desktop's switch (commits 6, 9, 10) goes where Settings is on this base (Sill
   for Mac's Virtual Display tab, the device's Settings panel) and moves into #393's whole-screen pane, its Mac part,
   once that lands.
7. The plan's open decisions that phase 2b builds (5 following the device, 11 changing it from away, 12 switched on from
   a device shows it at once, 13 Aa dimmed on it, 14 its lifetime, 15 the name) are taken as the plan recommends, each
   listed here again by the commit that builds it; none is built in this part.

**Verified** (on this Mac; nothing made a display, posted input, locked, slept or switched anything):
- The probe's dry run (`Scripts/display-modes-probe/run.sh`, and with `1133x744 120`): built (VirtualDisplay.swift and
  probe.swift alone, no VideoToolbox), the private API's 17 selectors present by lookup, the modes, their backing (the
  room both ways: 2752 × 2752 px) and the steps printed, nothing made; a bad argument and a room under 320 points exit 2.
- SillHostCore typechecks clean after each commit (`swiftc -typecheck` against the StreamProtocol module built from this
  tree). `virtual-display-api` 302 checks, `sill-displays` 45, `stage-release` 847, each passing; every mutant's pattern
  found once (92, 33 and 25) before the mutants ran.
- PENDING: the release build, the mutants and run-all (one turn of the heavy lock), the live gates and H2 against 2a's
  CLI; filled in below when they finish.

**For Noah** (only he can: each makes a display, or needs Sill.app on his Mac; the same list is in the pull request):
1. P2, the modes probe, on a Mac at rest (Sill quit, nothing streaming, no device connected; it makes "Sill Probe" for
   about ten seconds and a window of its own on it): `cd ~/Downloads/wt-vd-2b && Scripts/display-modes-probe/run.sh
   --make`, then upright at 120 Hz: `Scripts/display-modes-probe/run.sh --make 1032x1376 120`. Its last three lines
   decide plan §5 ("P2 in place by the modes listed at creation: yes|no", "P2 new modes on the live display …: yes|no",
   and what a mode beyond the display's backing did); the output goes into PR #408.
2. P1 (from #395, still open), on the same Mac at rest: `swift build -c release && for a in "60 1218x800" "120
   1376x1032" "120 1496x800" "60 1133x744"; do .build/release/SillHost --virtual-display-selftest $a; done`.
3. The stage as before (its display now goes through SillDisplays): this branch built as a release and installed
   (`SILL_RELEASE_DRY_RUN=1 SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'
   SILL_PROVISION_PROFILE=/Users/noah/Downloads/winstream/Packaging/embedded.provisionprofile Scripts/make-app.sh
   --release --install --open`), Virtual Display on: pick a window from the iPad (`Virtual display … created …`, the
   window on Sill's display); pick another (the first home, the display kept); pick the Desktop (`Removed virtual
   display N (… home after … ms)`); then Quit Sill with a window staged (the window home, no "Sill" left in System
   Settings › Displays).
