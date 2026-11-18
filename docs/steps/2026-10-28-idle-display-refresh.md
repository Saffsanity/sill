**A Desktop after a spell with no device (2026-10-28, branch `idle-display-refresh` from main at 6c5b5d24,
PR #239; the diagnosis is sill-handoff's `triage/2026-10-20-reports/verdicts-2026-10-27/glitch-wired-black-2026-10-28.md`,
the report `verdicts-2026-10-28/idle-display-report.md`).** Noah, 2026-10-28 18:15 on the iPad mini over the cable
with a fresh Debug build: connected, black, left after 7.4 s; the Wi‑Fi tap 25 s later "worked flawlessly". Sill.app
had sat 36.5 hours with no device while the dock's two displays came back under new IDs through ~290 sleeps; the
catalog looks only while a device is connected ("idle means idle"), so it still held display 21 (the displays were
53 and 52). The first pick built the Desktop's filter on 21's SCDisplay, read before an await during which the
poll's first look had already replaced it; ScreenCaptureKit refused it ("Start stream failed … The stream is nil",
CoreGraphicsErrorDomain 1003); the host printed it, sent "nothing streams" and never tried again; the device had
just asked, its next lists (0.18 and 0.25 s) came within the 10 s spacing, and no list came after: black until
left. Any second pick would have streamed. Not a regression (the Desktop's cached display dates from 2026-09-22).
No wire change.
- The host (CatalogLook, pure, `Tests/checks/catalog-look`): before any window or Desktop capture (never the test
  pattern) the catalog looks again (one ScreenCaptureKit call, about 50 ms) when its last look's display is not
  among `CGGetActiveDisplayList`'s (gone, or asleep: harmless), it had none while macOS has one, there was no look,
  or the look is older than two poll intervals (4 s) on the clock that counts sleep (`WindowCatalog.lookedAt`,
  `lookAge`; an empty list of displays leaves it to the age). A look the poll keeps fresh needs none, so a pick
  mid-session is as before. The Desktop reads its display after its last await (`desktopCapture`: Sill's own app
  looked up, then the display and the app from the newest look), and says "Desktop: display 21 → 53 (the displays
  changed since the last look, 36 h ago)." when the look changed it. A Desktop start that fails looks again and
  tries once more with one line, "Could not start streaming the whole desktop: ‹error›. Looked at the displays
  again: trying once more on display 53." (`startDesktopAgain`; the test pattern tries the same start again,
  "… Trying once more."); a second failure is the old line, nothing streams.
- The device (`DiscoveryPolicy.autoDesktop`, `autoDesktopRecheck`, StreamClient's `askForDesktopByItself` and
  `recheckDesktop`): within the 10 s spacing after its own Desktop request, a list that says nothing streams
  (watching nothing, or the Desktop the Mac stopped) and no choice of the person's since that request (a pick, a
  launch, a pick made again after a move: `choicesAtLastAuto`) sets one re-check when the spacing ends (`askIn`;
  a clock set back waits the spacing, never longer); due, it asks only while nothing streams still, nobody chose
  and no other automatic request went out. So a Desktop that failed is asked for again 10 s after, a Mac that
  keeps failing every 10 s, never faster, and a Desktop the Mac stopped within the spacing is asked for when it
  ends (issue #69's re-ask was held back there). A window that closes within the spacing is left as before. The
  re-check is cancelled by the next automatic request, at a session's end and at a move. DEBUG console:
  `session: nothing streams after this device's Desktop request; asking again in 9.8 s, when the 10 s spacing
  ends`, `session: still nothing streams 10 s after this device's Desktop request; asking for it again`. Against
  Sill for Mac 0.5.1 (the stale display unfixed there) the second ask should stream too: the diagnosis found the
  first session's own look had replaced the display 0.1 s in, so any second pick streamed (read, not run).
- TEST ONLY `SILL_TEST_DESKTOP_FAIL=<n>`, honoured only by a `--synthetic` host ("Test Desktop: …" at start;
  otherwise one "ignored" line): the first n Desktop starts fail where the capture would start, as on 2026-10-28.
  With 1 the host's one more try streams; with 2 nothing streams and a device's second ask does.
- Not done (the report's items 3, 4 and 6, for Noah): the first catalog sent only after the first fresh look (a
  device shows a list up to a day old for about 50 ms); a display reconfiguration callback marking the look stale
  while idle; dropping a client whose path goes unsatisfied before its 8 s grace (the dead cable connection the Mac
  served for 7.6 s). Nor the pair dialog of the same evening (the diagnosis leaves it open: Add a Mac's card or an
  iPadOS alert; the iPad's console or a screenshot would settle it).
- Verified: `swift build -c release` (only the CaptureProbe warning); `catalog-look` 64 checks and 25 of 25
  mutants (in CI's matrix); `policy` 486 (22 new) and 176 of 176 mutants (N24–N28 follow the new code, N29–N39
  the re-check); the patterns of the other three checks that compile DiscoveryPolicy.swift (`home-device` 131,
  `home-model` 14, `remote-rules` 17) each still found once, their mutants not run again (none calls `autoDesktop`);
  `run-all.sh`, all 56; the three iOS builds on Xcode 27.1 (Debug for the generic simulator as CI builds it, Release
  for the simulator, Debug for a generic device), only the known `StreamClient` capture warning (now line 4162);
  H2: the CLI from `git archive` of 6c5b5d24 against this branch's, `--synthetic` test hosts on loopback with the
  software encoder and no screen, idle 35 s identical masked and sorted, with a test client picking the Desktop for
  12 s identical (twice; main's own second run differed from its first only in the stats line of the second the
  client left). Live on a private iPad mini (A17 Pro) simulator (iOS 27.0, deleted after) dialling such a host with
  `-SillConnect` (a plain door): with `SILL_TEST_DESKTOP_FAIL=2` the host's start and its one more try failed 0.23 s
  after the connection, the device said it would ask again in 9.5 s and did 10.2 s after its first request, and the
  stream came within 10 ms (29–57 fps after); with 1 the one more try streamed in the same pick and the device never asked
  again; with 50 (a Mac that never starts it) the device asked at +0.85, 10.99, 21.24, 31.49 and 41.49 s, 10.0 to
  10.25 s apart. Not run: the real Desktop path (`desktopCapture`, the look before it, the "display 21 → 53" line,
  the one more try with a new look), since every test host here stays off ScreenCaptureKit (`SILL_TEST_NO_SCREEN`)
  and never captures this Mac's displays; nor a device, nor main's iOS build beside this one (the model has the rule
  before: one ask, then black).
- **Untested, for Noah:** with Sill.app from this branch and the iPad on a Debug build: leave Sill.app
  with no device while the dock's displays sleep and wake (or `pmset displaysleepnow`, a key, and a look with
  `system_profiler SPDisplaysDataType` or a `CGGetActiveDisplayList` probe that their IDs changed), then connect: the
  Desktop at once over any route, and Sill.log's "Desktop: display ‹old› → ‹new› (the displays changed since the last
  look, … ago)."; picks while connected exactly as before (no such line, no delay); the Desktop with Virtual Display
  on, and a window picked first after the spell. The device's part against Sill for Mac 0.5.1 (the host's fix not in
  it), after the same spell: black for about 10 s, then the Desktop by itself (the console's `session: still nothing
  streams 10 s after …; asking for it again`); a monitor unplugged while the Desktop streams (ScreenCaptureKit stops
  the capture): the Desktop back within 10 s; VoiceOver unchanged (nothing new is drawn or said).
