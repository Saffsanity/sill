# Privacy mode: the assessment

2026-11-18, read-only. Main at 4e00c805 (Sill 0.6.2) in ~/Downloads/winstream; pull request #184 at 22f0673d
(`refs/remotes/pr/184` in ~/Downloads/sill); issues #133, #141, #323, #275, #283 and their neighbours (#134, #271,
#298, #156, #200, #344, #352); Apple's documentation and developer forums. Nothing was built, run or posted. The
only commands that touched the system were `sw_vers` (macOS 27.2.1, 26B131) and `dyld_info -exports` on
login.framework (read-only), which shows `SACLockScreenImmediate`, `SACScreenLockEnabled` and
`SACSwitchToLoginWindow` still exported on this macOS.

## 1. What exists today

Main has no privacy mode. Nothing darkens the Mac's own screen, nothing locks the Mac, and nothing watches the
Mac's own keyboard or mouse. What main does have, and what a privacy mode meets:

- **A display that sleeps (DisplayWake, issue #134, PR #151).** The opposite pull. A device's session connecting,
  and a person's input from it, declares user activity on the Mac (`IOPMAssertionDeclareUserActivity`,
  `kIOPMUserActiveLocal`, DisplayActivity.swift:32-50), so a sleeping panel lights up: ScreenCaptureKit gives black
  frames for a sleeping display. The connect's declaration is made in the coordinator's client-connected path
  (StreamCoordinator.swift:571) and runs on DisplayActivity's own queue at once. When #151 was shaped, its
  all-session PreventUserIdleDisplaySleep assertion was dropped partly because it kept "the panel lit all session
  long, against #133's privacy mode" (docs/steps/2026-10-19-a-sleeping-display-wakes-for-a-device.md). The TEST ONLY
  `SILL_TEST_USER_ACTIVE=remote` (`kIOPMUserActiveRemote`) was added to see whether remote activity keeps the picture
  live with the panel dark (#133); addhumal's #229 proposed declaring it away from home and on Sill's display, and
  Noah closed it on 2026-11-09: "going by Apple's published powerd source, declaring the remote user-activity type
  doesn't change whether the display wakes compared with what Sill already declares". So that is no way to keep a
  panel dark.
- **A locked Mac (LockPolicy, SessionLock, PR #271, docs/locked-mac-plan.md).** Three readings (unlocked, screen
  locked, off console); a lock counts at once, an unlock only after a 2 s settle; at a locked screen the display
  streams the lock screen (`lockScreenStreams`, Noah 2026-10-31) and only a paired session's input is posted, so the
  owner types the password from the device; off console nothing is shown or posted (unless the off-console view of
  #316 is on, and then nothing acts). Nothing in Sill ever locks the Mac.
- **Virtual Display, on by default in Sill.app since 2026-10-27.** A picked window moves to Sill's own
  CGVirtualDisplay, which has no panel, so the streamed window is already off the Mac's own screen. The Desktop, the
  other windows, the menu bar and notifications stay on the Mac's screens.
- **Sill's own windows never reach a device.** The Desktop's filter leaves Sill's app out
  (StreamCoordinator.swift:2366, `SCContentFilter(display:excludingApplications:exceptingWindows:)`; in Sill.app
  `resolveOwnApplication` runs whenever the last look missed Sill, since Sill.app always has a RemoteAccess); a
  window stream is one window (`desktopIndependentWindow`); the stage's filter includes only that window's app; the
  catalog lists no window of Sill's (CatalogWindows.swift:63-66). So a black window of Sill's over the Mac's screen
  is never in a stream. `NSWindow.sharingType = .none` plays no part in that: ScreenCaptureKit is reported to ignore
  it from macOS 15 (PairingWindowSharing.swift's own note; Apple's DTS on the forums: "there are no public APIs for
  preventing screen capture").
- **App Nap and idle sleep.** While a device is connected Sill holds a latency-critical activity, and while one is
  away a `.userInitiated` one that keeps the Mac from idle sleep (AppModel.swift:442).
- **The CLI** runs `dispatchMain()` unless `--virtual-display` is given (SillHostCLI/main.swift:211-226), so it can
  show no window.
- **Settings › Devices** already holds the Mac-only switches about devices using the Mac: Require pairing, Show the
  pairing window to screen sharing, Show this account while another user is on the screen (DevicesPane.swift:61-99).
- **On the device:** nothing.
- **Recorded facts that decide the design.** "ScreenCaptureKit delivers frames only when the window repaints, and
  macOS stops repainting fully covered windows, so a streamed window buried behind others on the Mac freezes on the
  device" (docs/steps/2026-09-22-milestone-1.md:20-23, one of CLAUDE.md's rules for all work).

## 2. The issues, and what Noah has said

| Issue | Who | Asks | State |
|---|---|---|---|
| #133 | josh-andrews-dev, 2026-10-16 | "keep the host Mac's physical screen blanked (or dark) during an active remote connection", citing Jump Desktop's Privacy Mode, which "blanks the host's physical display, blocks local keyboard/mouse input during the session, and locks the machine upon disconnect" | open, the canonical issue |
| #141 | px-lfarias, 2026-10-16 | "Block host screen when remote access are active and close connection" | closed 2026-10-19 as a duplicate of #133 |
| #323 | Joel-3000, 2026-11-07 | "the Mac screen blanked while accessing it via another device. Logging into the Mac externally leaves it usable by someone nearby." | open |
| #275 | opt1cal, 2026-11-01 | "block or turn off display immediately after end a session" | open; addhumal answered that #184 covers it |
| #283 | Saffsanity (Noah), 2026-11-02 | lock the Mac when the last device disconnects | open; addhumal answered that #184 covers it |

Noah's own words, under his login (Saffsanity). Some were drafted by his sessions and posted on his word (the
triage marks of 2026-10-19; the issue drafts filed 2026-11-02 "on Noah's go"); they are his and they bind:

- #133, 2026-10-18: "I promise I will take a look when I get back next week and see what can be done here."
- #133, 2026-10-19: "From #141, closed as a duplicate of this: blanking the Mac's screen while a remote session runs
  and locking it when the connection closes."
- #141, 2026-10-19: "Blanking or locking the Mac's own screen while a remote session runs, and locking it when the
  connection closes, is what #133 asks for".
- #323, 2026-11-10: "Definitely something I have considered for the future, as a toggle"
- #283, 2026-11-02 (the issue itself): "An option on the Mac: when the last device disconnects, the Mac locks its
  screen (or logs out) by itself. It would be a switch in Settings, under Devices or General." / "So I can unlock my
  Mac from far away, and when I'm done it stays unlocked for anyone who walks up to it. Locking it on the way out
  closes that." / "Lock or log out? Logging out also quits Sill, and Sill can't reach the login window, so nothing
  could reach the Mac again until someone logs in at it. Locking keeps everything running, and a paired device can
  unlock it again." / "A short wait first, so a connection that drops and comes back by itself (Wi-Fi blinking)
  doesn't lock the Mac while I'm still using it." / "Devices or General? #184 put its switch under Remote Access,
  but this isn't only about remote access."
- The assignment, 2026-11-18: "Privacy mode options (blank local display when remote access is being used)".
- Around it: #271, 2026-10-31: "When the user is locked, it should only show the lock screen, no virtual desktop, no
  desktop, no apps, nothing other than the login screen." The same day (docs/locked-mac-plan.md, question 1): "show
  the real lock screen's picture at all times instead of this overlay panel". #134, 2026-10-18: "Waking from sleep
  is a highly requested feature and will be supported in future versions." #229, closing it 2026-11-09: "going by
  Apple's published powerd source, declaring the remote user-activity type doesn't change whether the display wakes
  compared with what Sill already declares".

What binds any implementation:

- **R1** A switch in Settings on the Mac, off by default (#323 "as a toggle", #283 "a switch in Settings", the
  project's rule that new features are off unless turned on).
- **R2** The Mac's own screen dark while a session runs, at least while a device is away from home ("when remote
  access is being used"), and the Mac locked when the connection closes (#133, #141).
- **R3** Lock, not log out (#283's own reasoning: logging out strands Sill; a paired device can unlock a locked Mac).
- **R4** A short wait before the lock, so a dropped connection that comes back doesn't lock the Mac (#283).
- **R5** Under Devices or General, not Remote Access (#283; asked as a question).
- **R6** A locked Mac keeps showing only its lock screen (#271): a privacy mode never widens what a device sees.
- **R0** The task's first safety rule: the Mac's screen never stays black, whatever happens to Sill.

What the people asking want beyond that: Jump Desktop's three parts (dark screen, local keyboard and mouse blocked,
lock at the end; #133), nobody at the Mac able to use it meanwhile (#323), and the display off when the session ends
(#275).

## 3. Pull request #184, file by file

addhumal, "Remote Access: Privacy Mode (blank display while connected, lock on disconnect) (#133)", opened
2026-10-20, three commits (485916a7, then two merges of main, the last 2026-10-27 at main 6c5b5d24), no review, no
comment, CONFLICTING. 12 files, +573 −4:

- **Sources/SillMenuBar/PrivacyModePolicy.swift** (new, 217 lines). `PrivacyModePolicy` (pure, CoreGraphics and
  Foundation): `Screen`, `Decision`, a `State` whose `update(privacyMode:lockOnDisconnect:connectedDevices:
  consoleUnlocked:physicalScreens:shuttingDown:)` decides the shield (switch on, a device connected, a physical
  screen, not quitting) and the lock (the count went from some to none, the switch on, the console unlocked, not
  quitting) with log lines; `shieldScreens` (never a Sill display, never a zero-size frame); `Copy`, the pane's
  words. Under `#if canImport(AppKit) && canImport(SillHostCore)`, `PrivacyShieldController` (main actor): one
  borderless opaque black `NSWindow` per physical screen at `.screenSaver` level, `ignoresMouseEvents`, `sharingType
  .none`, on all Spaces; re-synced on `didChangeScreenParametersNotification`; the lock by `dlopen` of
  login.framework and `SACLockScreenImmediate`, then `pmset displaysleepnow`.
- **AppModel.swift** (+23): the controller, `updatePrivacyShield()` called from `publish` (each presentation, about
  once a second while devices report stats) with the snapshot's device count, and `tearDownPrivacyForQuit()`.
- **AppDelegate.swift** (+1): the teardown first thing in `applicationShouldTerminate`.
- **HostSettings.swift** (+22): `privacyMode` and `lockOnDisconnect` in UserDefaults, off by default, with
  `onPrivacyChange`.
- **RemoteAccessPane.swift** (+12): a "Privacy" section in Settings › Remote Access, two toggles and a footnote; the
  bindings default to `.constant(false)`, so the previews show them off.
- **DebugHooks.swift** (+11 −3): `-SillSetAfter` keys `privacyMode` and `lockOnDisconnect` (the bare binary only;
  Sill.app ignores `-Sill…After`).
- **Tests/checks/privacy-mode/** (new): `build.sh`, `run.sh`, `main.swift` (49 checks: the screen filter, launch,
  toggles, connect and leave with one and two devices, two screens, none, a locked console, quitting, the words not
  empty), `mutants.py` (12, the PR says all caught).
- **.github/workflows/ci.yml** and **Tests/checks/README.md**: the check added to the hand-kept mutants matrix and
  table.

What it gets right: off by default; Mac only, no wire change; Sill's own windows, which every capture of Sill
already leaves out; physical screens only, never Sill's display; re-synced when the screens change; no lock at
quit or at an already locked console; a pure rule with a check and mutants; lock rather than log out.

## 4. Does it merge?

No. Against main 4e00c805 (merge base 6c5b5d24, 637 commits behind), comparing each side's changes since the base:

- Textual conflicts in four files: `.github/workflows/ci.yml` (main replaced the hand-kept matrix with
  `Tests/checks/mutant-checks.py`), `Tests/checks/README.md` (main removed the table; `HISTORY.md` keeps it frozen),
  `AppDelegate.swift` (both sides insert after `terminating = true`: main's update-install wait and `quit()` split)
  and `AppModel.swift` twice (both insert after the initial `presentation`, and after `holdAppNapOff` in `publish`,
  where main added `updater.devicesChanged`). HostSettings.swift, DebugHooks.swift and RemoteAccessPane.swift merge
  by themselves.
- It would not compile after the merge: `SessionLock.shared.unlocked(testHost:)` (PrivacyModePolicy.swift:126) is
  gone; since #271 it is a property, `SessionLock.shared.unlocked` (SessionLock.swift:139).
- `Tests/checks/repo-rules` would fail: the check folder has no `README.md`, and a static mutants list in ci.yml is
  refused.
- CLAUDE.md since 2026-11-12: a branch writes its notes in its own `docs/steps/<date>-<branch>.md`; the PR has none,
  and no CLAUDE.md layout entry for its files.

## 5. Protocol

None: no kind number, no field, no capability flag in the hello or the window list; nothing on the device. Checked
against CLAUDE.md's Compatibility floor: nothing to check, every device and Mac on either side of it behaves as
today. The plan keeps it so (a device switch would be optional fields in kinds 16 and 17, Open decision 11).

## 6. Security

- **Who triggers what.** Only the Mac's own Settings turn it on (UserDefaults; a local process of the same user could
  turn it off, but that user can already see the screen, so it is no boundary; unlike Require pairing it lets no
  device in). The bare binary's `-SillSetAfter` keys are ignored by Sill.app.
- **Devices.** Any registered session counts: a paired one, an unpaired one at a door with Require pairing off, a
  session admitted and cut off at once (`stillServes`). Connecting darkens the Mac's screen; with the lock switch on,
  connecting and leaving locks it. Both are nuisances for the person at the Mac, never a leak: darkening hides,
  locking never unlocks. A removed device cannot register. A session at the pairing door (`sill-pair/1`) never
  counts.
- **A locked Mac.** The shield goes up at a locked or off-console Mac too; harmless. What devices may see and do is
  LockPolicy's, unchanged.
- **The person at the Mac** is told nothing: pure black, no words, the menu bar covered. Apple's own High
  Performance screen sharing does the same and is reported to look "like a crash, hardware failure, or cable issue"
  (a community write-up quoted in the sources below).
- **Local input** is not touched at all: keys and clicks at the Mac go to the session's apps unseen (D5).

## 7. What it needs from macOS and iOS

- macOS: no privacy prompt (windows need none); no entitlement, driver or system extension; one private interface,
  login.framework's `SACLockScreenImmediate` (exported on macOS 27.2.1, measured above), the kind of private use the
  project already accepts (CGVirtualDisplay, SkyLight's symbolic hotkeys), outside any App Store review since Sill
  for Mac ships by Developer ID; `/usr/bin/pmset displaysleepnow`, no privilege.
- iOS: nothing (no usage string, background mode, privacy manifest entry or App Review guideline at stake).

## 8. Tests and docs

The check covers the tiny rule only, not the glue (where the count comes from, the order against DisplayWake, the
windows, the lock); its words are checked only for being non-empty; no random sessions. No live gate, no previews of
the new section (the samples build the pane with the switches off), no DEVELOPMENT.md, support page, privacy page,
CLAUDE.md or step file. The PR's own results: 49 checks, 12 of 12 mutants, `swift build`, 140 previews, all on its
2026-10-27 base.

## 9. Against the project's conventions

Pure rule with mutants: yes, small. Explicit threading: main actor throughout. Apple frameworks only: yes, plus one
private framework. No servers, no running cost: yes. Off unless turned on: yes. Host logic in `SillHostCore` with
`package` access: no, it lives in the app, so the CLI and test hosts cannot run it and no headless gate can reach it.
Latency before quality: at risk (D4). The step-file and check-README rules of 2026-11-12: not met (it predates them).

## 10. How macOS can darken a display while ScreenCaptureKit keeps capturing it

| Way | Public? | Built-in panel / external monitor | HDR, Night Shift, True Tone | The capture | If Sill crashes, is force-quit or hangs |
|---|---|---|---|---|---|
| **A black window of Sill's over each screen** (#184, #156's "curtain") | Yes (AppKit) | Every screen AppKit lists: built-in, external, mirror sets (one screen), Sidecar, AirPlay, DisplayLink | Black stays black under any colour transform; on an LCD the backlight still glows at the panel's black level, on mini-LED and OLED the zones and pixels go off | Left out of Sill's Desktop by the app filter; window and stage captures unaffected. **But every window it covers is fully covered**: macOS stops repainting such windows (CLAUDE.md's rule), and apps that follow occlusion stop drawing (Apple's power guide: Photo Booth; Chromium: the renderer will "stop producing frames"; Zed and Alacritty stop drawing occluded windows, by their own commits). So the Desktop, and a window with Virtual Display off, may freeze on the device. Not yet measured with a covering window of another app at level 1000 | Crash or force-quit: the windows go with the process (the window server closes a dead process's windows: universal behaviour, to be seen in the plan's G0). Hang: the windows stay, black, as long as the process lives |
| **Gamma tables set to zero** (`CGSetDisplayTransferByTable`/`ByFormula`) | Yes (Quartz Display Services) | Built-in and external through the GPU's tables; AirPlay, Sidecar and DisplayLink are not known to honour them; "a mirror ignores its gamma" (#156's author, measured) | Night Shift, f.lux, Lunar and similar tools write the same tables and "cancel each other out" (MonitorControl); a screen saver or another app reinitialises them (Gamma Control 3.0); a display reconfiguration or wake resets them; on built-in XDR panels with EDR content and auto-brightness on, the table scales the whole range, and turning auto-brightness off can leave the screen "permanently bad" after the app quits (a developer in Apple forums 819331) | Not affected (the tables apply after composition; screenshots never show a Night Shift or f.lux tint), so no occlusion, apps keep drawing | Believed restored at the setting process's exit (Gamma Control 6.2.1: "instead of counting on macOS to do it for us"), not documented by Apple. Hang: stays black. **Silently ignored on M5 Pro, M5 Max and MacBook Neo**: "Both APIs return kCGErrorSuccess", the read-back is right, "No visual change occurs on the display" (Apple DTS, reproduced on 26.3.1 and 27.0.1; "27.2.1 still has no fix", forums 819331), and ignored on Tahoe betas while "Automatically adjust brightness" was on (795074): privacy that fails with no way to notice. `CGDisplayRestoreColorSyncSettings()` "can sometimes set all RGB Gamma tables to 0", leaving a screen black "until you disconnect and reconnect the monitor" (Gamma Dimmer): a breach of R0 |
| **Brightness to zero** | Built-in: private DisplayServices on Apple silicon; external: DDC/CI through private IOAVService; the IOKit call is deprecated | Many panels stay visible at their lowest step; monitors vary | Auto-brightness fights it | Not affected | Persists after a crash: the screen stays dark until someone finds the brightness keys (a monitor's own buttons for DDC). Breaks R0 |
| **Display sleep** (`pmset displaysleepnow`, IOKit's `IORequestIdle`) | Yes | All panels off | n/a | A sleeping display gives black frames (#134), so the Desktop and Virtual-Display-off windows go black on the device; DisplayWake wakes the panel at every connect and input; any local key or mouse movement wakes it, showing everything | Harmless: a sleeping display is the Mac's normal idle state. Usable only when every stream comes from Sill's own display **and** that display keeps compositing while the panels sleep (unknown: docs/virtual-desktop-plan.md §8) **and** DisplayWake stops waking the panels for those sessions (declaring remote activity instead does not help: Noah on #229) |
| **Turning displays off** (private `CGSConfigureDisplayEnabled` in a `.forAppOnly` configuration, as BetterDisplay does) | No | The display disappears; macOS moves every window to the remaining displays | n/a | The display is gone, so it cannot be the stream's source: only with the Virtual Desktop as the source | `.forAppOnly` is documented to revert at termination for public configuration ("After the application terminates, the display configuration settings revert"); not documented for the private flag. Apple's own High Performance screen sharing blanks "the hardware displays connected to that Mac" (Apple's Remote Desktop guide), mechanism private |
| **Mirroring onto a virtual display** (#344's fork) | Yes (`.forAppOnly` reverts at exit) | — | "a mirror ignores its gamma"; mirroring a 5K display "cost the stream its rate" (#156's author) | — | Reverts at exit; blacking the mirror still needs one of the ways above |
| **A curtain as Apple Remote Desktop's** | No: ARDAgent's (Apple Remote Management), no third-party interface | — | — | — | Apple's own; a 2013 community report has ARD's curtain staying after a dropped session until a restart. Chrome Remote Desktop's Mac curtain instead switches the console to the login window (`SACSwitchToLoginWindow`) and keeps the session off console; for Sill off console means nothing is posted and nothing shown (#271's measurements, LockPolicy), so it does not carry over |

The only way that is public, darkens every screen on every Mac, and undoes itself when Sill dies is Sill's own black
windows, #184's way. Its cost is the covered windows (D4), measured nowhere yet, and a hang (D9). Gamma would keep the
picture live but fails silently on current Macs and can leave a screen black. That decides the plan.

## 11. Defects found by reading

Line numbers are #184's head (22f0673d) unless said otherwise.

- **D1 It does not build on main.** PrivacyModePolicy.swift:126 calls `SessionLock.shared.unlocked(testHost:)`,
  removed by #271 (now the property at SessionLock.swift:139 on main). At its own base that call was a
  `CGSessionCopyCurrentDictionary` WindowServer round trip on the main actor, made at every presentation (about once
  a second with a device connected), the kind of call #271's review moved off the main actor.
- **D2 It locks the moment the count reaches zero.** PrivacyModePolicy.swift:48-49. Noah's #283 asks for "a short
  wait first". Failure: an iPhone away on a weak link stops reading for 4 s, the Mac evicts it, the iPhone reconnects
  3 s later and finds its Mac locked, its display asleep (`pmset`), and its owner types the password again.
- **D3 The dark screen goes before the lock comes, and at every drop.** PrivacyModePolicy.swift:47 drops the shield
  as the count reaches zero, and :138-145 close the windows before calling the lock in the same update. Failure: at
  every session's end with the lock on, the unlocked desktop shows to the room until loginwindow draws the lock
  screen; with the lock off, a Wi-Fi blink shows the whole session to the room for as long as the device takes to
  reconnect.
- **D4 It covers the very display it streams.** PrivacyModePolicy.swift:183 (`isOpaque = true`) and :187
  (`.screenSaver`) over every physical screen. Every window there is fully covered, and macOS stops repainting fully
  covered windows (docs/steps/2026-09-22-milestone-1.md:20-23); browsers, Electron apps, video and Metal views stop
  drawing when occluded. Failure (likely, unmeasured): the Desktop streamed with Safari playing a video, or VS Code
  with Virtual Display off, freezes on the device while privacy mode is on. Windows staged on Sill's display are
  spared (it is never covered).
- **D5 Local keys and clicks go through, unseen.** :185 `ignoresMouseEvents = true`, and nothing watches the
  keyboard. Failure: someone at the dark Mac presses ⌘Q or types into the remote user's Terminal; their mouse moves
  the pointer the device is using. #133 and #323 ask for the opposite.
- **D6 The person at the Mac cannot take it back.** Nothing lowers the shield while a device stays connected. ⌃⌘Q
  locks, the lock screen shows (if it is above level 1000, unverified), the owner unlocks, and the screen is black
  again. Failure: Noah leaves the iPad on the couch with Sill open and walks to his Mac: it stays black until he goes
  back and closes Sill on the iPad, or quits Sill blind. This breaks R0 in spirit.
- **D7 A sleeping display can light up showing the desktop.** The shield follows `publish` (AppModel.swift:375 in
  the PR), which runs a main-actor turn after the status change (`observePresentation`'s `Task` hop,
  AppModel.swift:380 on main), while the coordinator's connect declaration (StreamCoordinator.swift:571) is already
  on DisplayActivity's queue lighting the panel. Failure: `pmset displaysleepnow`, connect from away: the panel can
  come on with the session's desktop before the black windows are ordered in.
- **D8 No scope.** AppModel.swift:380 in the PR counts every session. Noah's assignment says "when remote access is
  being used". Failure: the iPad on the desk as a second screen blacks out the Mac its owner is sitting at, at every
  connect.
- **D9 A hang leaves the screen black.** The windows live as long as the process; nothing watches the main thread.
  Failure: a main actor stuck in a WindowServer or Accessibility call keeps every display black; the menu bar is
  covered; whether the Force Quit window shows above level 1000 is unknown. Breaks R0.
- **D10 A failed lock says it locked.** :203-215: a missing symbol does nothing silently, the display sleeps anyway,
  and :59 already printed "locking this Mac". Nothing checks SessionLock afterwards. Failure: on a macOS without the
  symbol the Mac is left unlocked with its display asleep (a key wakes it unlocked unless the Mac's own "require
  password" catches it), and Sill.log says it was locked.
- **D11 A headless Mac can be locked out.** The lock needs only "unlocked". On a Mac with no working display,
  #298 reports that the login screen rejects the right password typed from a device; #200 (open) fixes that by
  giving such a Mac a display. Failure: a headless Mac mini, lock on disconnect on, the session ends: nobody can
  unlock it from a device until someone attaches a monitor or restarts it.
- **D12 A new or re-numbered display shows the desktop first.** :155-167 order the old windows out before the new
  ones in, and the re-sync waits for `didChangeScreenParametersNotification` on the main run loop. Failure: a monitor
  plugged in while dark, or the displays re-numbered at wake (21 became 53 on 2026-10-28), shows the desktop until
  the notification is handled.
- **D13 The words.** :79's footnote always says it "locks the screen when the last device disconnects", the lock
  switch on or off; it says nothing of what the person at the Mac can do; the section sits in Remote Access, which
  Noah questioned in #283.
- **D14 The rule cannot be tested where it matters.** It lives in the app (not `SillHostCore`), so no test host and
  no loopback gate reaches it, and the check never sees the order against DisplayWake, the count's source or the
  lock.

Not defects, noted: the pointer (cursor) still shows and moves on the black screen; the Mac's speakers keep playing
the session's sound (Send Audio leaves the Mac's own output on); a Touch Bar keeps showing the front app's controls;
VoiceOver turned on at the Mac reads the covered windows. Each is a small leak to the room the plan names.

## 12. Verdict

**Build on it**, the way #355 was built on #173: a branch in Saffsanity/sill from #184's head with addhumal's
commits merged in as they are (so #184 shows as merged when it lands), main merged in, and our commits on top.

- Not merge as is: it does not compile on main (D1), conflicts in four files, fails `repo-rules`, breaks Noah's
  requirement of a wait before the lock (D2), shows the desktop at every drop (D3) and gives the person at the Mac no
  way back and no protection from a hang (D6, D9).
- Not redo: its mechanism is the one the survey above keeps (Sill's own black windows: public, every screen on
  every Mac, gone when Sill dies, already left out of every stream), and its window recipe, screen filter, lock call
  and settings plumbing carry over. What it lacks is the rules around them, which our commits add in `SillHostCore`
  with a full check. Most of its lines will be replaced or moved; the credit and history stay addhumal's.
- Before the windows ship, one measurement decides how much D4 costs and which window level to use (the plan's G0);
  the lock after a session needs no measurement and can ship first.

Sources: Apple, [CGSetDisplayTransferByTable](https://developer.apple.com/documentation/coregraphics/cgsetdisplaytransferbytable(_:_:_:_:_:)),
[CGDisplayRestoreColorSyncSettings](https://developer.apple.com/documentation/coregraphics/cgdisplayrestorecolorsyncsettings()),
[CGConfigureOption.forAppOnly](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forapponly),
[Using Fade Effects](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/FadeEffects.html),
[addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)),
[Use High Performance screen sharing](https://support.apple.com/guide/remote-desktop/apdf8e09f5a9/mac),
[Work when visible](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html);
Apple developer forums [795074](https://developer.apple.com/forums/thread/795074),
[819331](https://developer.apple.com/forums/thread/819331), [792152](https://developer.apple.com/forums/thread/792152),
[844416](https://developer.apple.com/forums/thread/844416); [Gamma Dimmer](https://lowtechguys.com/gammadimmer/);
[Gamma Control's history](https://michelf.ca/projects/gamma-control/version-history/);
[MonitorControl discussion 561](https://www.github.com/MonitorControl/MonitorControl/discussions/561);
[Chromium's Mac occlusion](https://www.chromium.org/developers/design-documents/mac-occlusion/);
Chromium's [curtain_mode_mac.cc](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/remoting/host/curtain_mode_mac.cc);
[Jump Desktop's Privacy Mode](https://changelog.jumpdesktop.com/privacy-mode-for-fluid-qkivS) (its
[external-display article](https://support.jumpdesktop.com/hc/en-us/articles/18219686885773-Mac-Privacy-mode-with-external-displays),
which refused to load here, is summarised by search as tying it to the number of external displays a Mac supports,
which suggests a virtual display; its mechanism is not published);
[an Apple Community write-up on High Performance screen sharing's black screens](https://discussions-jp-prz.apple.com/thread/256048806);
[9to5Mac on High Performance screen sharing](https://9to5mac.com/2026/02/05/how-to-use-macos-high-performance-screen-sharing-for-lower-latency-and-better-color-video/).
