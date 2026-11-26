# Privacy mode: this Mac's screen dark while a device uses it, and locked when it leaves — the plan

2026-11-18, written read-only from main at 4e00c805 (Sill 0.6.2) and pull request #184 at 22f0673d; the assessment
beside this file has the survey, the defects and the sources. Issues #133 (canonical), #323, #275 and Noah's own
#283; #141 closed into #133. Noah's assignment of 2026-11-18: "Privacy mode options (blank local display when remote
access is being used)". Branch `privacy-mode` in Saffsanity/sill, made from #184's head with addhumal's commits
merged in as they are (as #355 carried #173), so #184 shows as merged when it lands. Sill for Mac only: no wire
change, nothing on the device.

In two pull requests (open decision 16): **part 1**, the lock when the last device leaves (#283, #275), is branch
`privacy-lock`, built on #184's head as this plan says (merged as #402); **part 2**, darkening the screen, is branch
`privacy-darken` (#400), built for real once Noah ran G0 on 2026-11-23 (G0's results, under Tests). Progress at the
end.

## What it is, in a user's words

"I use my Mac from my iPad at a café. At home my Mac's screen stays black the whole time, so nobody walking past
sees my mail or what I'm typing, and if someone touches its keyboard it locks. When I close Sill on the iPad, my Mac
locks itself half a minute later and its screen goes to sleep, but if my Wi-Fi blinks and Sill reconnects by itself,
nothing happens. When I get home and sit down at the Mac while the iPad is still connected, I press a key, unlock it
with Touch ID, and it's mine again."

Three switches in Sill for Mac's Settings › Devices, all off until turned on:

- **Darken this Mac's screen**, only while a device is away from home (the default when turned on) or whenever a
  device is connected. Every display of the Mac turns black; the devices see the Mac as before.
- **A key or click on this Mac locks it** (on, under the first): someone at the dark Mac who touches it locks it;
  the owner's password or Touch ID brings it back, and an unlock at the Mac itself keeps the screen lit from then on.
- **Lock this Mac when the last device leaves**: 30 seconds after the last session ends, unless one comes back, the
  Mac locks and its display sleeps.

## Decisions already made, and by whom

- Noah, 2026-11-18: privacy mode options are part of this round of work ("blank local display when remote access is
  being used").
- Noah, #323, 2026-11-10: "as a toggle"; #283, 2026-11-02: "It would be a switch in Settings". So switches, off by
  default (also the project's rule for new features).
- Noah, #133 and #141, 2026-10-19: "blanking the Mac's screen while a remote session runs and locking it when the
  connection closes".
- Noah, #283: lock, not log out ("Locking keeps everything running, and a paired device can unlock it again"); "A
  short wait first, so a connection that drops and comes back by itself (Wi-Fi blinking) doesn't lock the Mac while
  I'm still using it"; "Devices or General? … this isn't only about remote access" (asked; this plan answers
  Devices, open decision 1).
- Noah, #271, 2026-10-31: a locked Mac shows only its lock screen, and (docs/locked-mac-plan.md, question 1) the
  lock screen itself streams. Unchanged here: privacy mode never widens what a device sees or does.
- Noah, 2026-10-27: Virtual Display on by default in Sill.app, so a picked window already streams from a display
  with no panel.
- Noah, closing #229 on 2026-11-09: declaring the remote user-activity type "doesn't change whether the display
  wakes"; DisplayWake keeps declaring local activity.
- CLAUDE.md: Apple frameworks only; no servers or running costs; rules as pure types with mutants; host logic in
  `SillHostCore` with `package` access, never `MainActor.assumeIsolated` there; the CLI's stdout byte for byte;
  additive-only wire.
- addhumal, #184 and his replies on #275 and #283: Sill's own black windows, physical screens only, and the lock via
  login.framework. Kept.
- Everything else here is this plan's proposal, taken unless Noah says otherwise (Open decisions at the end).

## How the screen goes dark (the choice, from the assessment's §10)

**Sill's own black windows, one per screen**, as #184 has them. It is the only way that is public, works on every
Mac and every kind of display (built-in, external, Sidecar, AirPlay, DisplayLink), keeps black black whatever HDR,
Night Shift or True Tone do, never reaches a device (every capture of Sill already leaves Sill's own windows out), and
undoes itself when Sill crashes or is force-quit (a dead process's windows go with it).

Not chosen: gamma tables set to zero (silently ignored on M5 Pro, M5 Max and MacBook Neo through macOS 27.2.1 while
reporting success, so privacy would fail with no way to tell; other tools and Night Shift overwrite them; their reset
has left screens black until a monitor was reconnected); brightness (persists after a crash, not black on many
panels, private on Apple silicon); display sleep (a sleeping display streams black and DisplayWake wakes it at every
connect; a later option only when every stream comes from Sill's own display, see risk 2); turning displays off or
mirroring them (private or disruptive, and only with the Virtual Desktop as the source); Apple Remote Desktop's
curtain (Apple's own, no interface).

Two costs of the windows, each handled below: the windows they cover (macOS stops repainting fully covered windows,
and browsers, Electron apps and video stop drawing; measured first, in G0, together with a non-opaque window that may
not count as covering), and a hung Sill (the windows stay; a watchdog ends Sill, rule 12).

## The protocol

None. No kind number, no field, no capability flag in the hello or the window list. Every device, older and newer,
behaves exactly as today, and so does every Mac without this. (A device's switch or line would be optional fields in
kinds 16 and 17, sent only to a Mac that says it takes them: open decision 11, not in this version.)

## The rule (`PrivacyPolicy`, pure, `Sources/SillHost/PrivacyPolicy.swift`, `Tests/checks/privacy`)

Foundation and CoreGraphics only, compiled on its own with swiftc. A value type the main actor owns (inside
`PrivacyScreen`); events in, actions out (`raise`, `lift`, `hint(until:)`, `lock(why)`, `sleepDisplays`, `line`,
`quit`), the clock the caller's (`ContinuousClock`'s seconds, which keep counting while the Mac sleeps). Its own
`MacReading` (unlocked, screen locked, off console; established or not) is filled from LockPolicy's reading by the
glue.

1. **Off unless turned on.** `darken` (`.off`, `.away`, `.any`), `keysLock` (Bool), `lockAfterSession` (Bool):
   `HostConfig`'s, below. With all off the rule does nothing and says nothing.
2. **Which sessions darken (`counts`).** With `.away`, a session while it is away (`AwayPolicy.isAway`: the remote
   door from a VPN, the internet or a relay on this Mac; the remote door "by address" and every home-door session
   are at home); with `.any`, every registered session. A move keeps the count (its new connection registers before
   the old one leaves); a move home turns an away session into a home one.
3. **Dark (`dark`).** The windows are up while all hold: `darken` is not `.off`; there is a screen to cover (rule 13);
   Sill is not quitting; the Mac has not been taken back (rule 8); and a session that counts is connected, or the
   last one left less than `grace` ago, or a lock asked by rule 6 or 7 waits for its confirmation.
4. **Under the lock screen (`staysUnderLockScreen`, decided by G0).** The windows sit at a level under macOS's lock
   screen and stay up whatever the lock reading: a lock shows the lock screen above them, an unlock (by anyone)
   reveals black, never the desktop. If G0 shows no level that is above everything else and under the lock screen,
   the constant flips: the windows come down at the first witness that says locked (the person at the Mac must see
   the lock screen, R0) and go up again at the first witness that says unlocked (the raw witness, not the 2 s
   settle), staying up only if rule 8 then calls the unlock the device's. The room may then see the desktop for the
   tenth of a second between an unlock and the windows, and the owner who unlocks at the Mac sees black for the 2 s
   of the settle.
5. **Up before the panel lights (`raiseFirst`).** At a counting session's connect the coordinator gives the rule the
   join and orders the windows in, synchronously, before it declares user activity for the connect (DisplayWake's
   `.connect`, StreamCoordinator.swift:571). A sleeping panel therefore lights up black.
6. **The session's end (`grace` 30 s, `lockConfirm` 3 s).** Two waits of `grace`, each cancelled, with one line, by
   a session that comes back within it:
   - *the dark's*: when the last counting session leaves, the windows stay up `grace`, then `lift`, unless a lock
     waits (below);
   - *the lock's*: with `lockAfterSession` on, when the last session of any kind leaves. At its end, with the Mac
     reading unlocked and established, not taken back, and a display to type the password at (rule 10): `lock`; the
     windows, up or held up, wait up to `lockConfirm` for SessionLock to read the screen locked; then `lift` and
     `sleepDisplays` (#275), with the line. Not locked by then: the failure's line, `sleepDisplays`, `lift` (R0 before
     privacy).
   Usually both start together (the last session was a counting one). With `.away` and a home session still
   connected, the dark's ends with `lift` and no lock; the lock's starts when that home session leaves. With `darken`
   off, only the lock's runs, with no windows: #283 alone.
   **Changed in run 6 of PR #400 (Noah, 2026-11-24, after his first try: 30 s was too long, "could we make it
   fast?"):** the dark's wait is Settings' Stay dark after the last device leaves, 5 s by default or 30 s; with no lock
   to follow it, its hint says when the screen comes back, and a key or click at the Mac lights it at once and locks
   nothing (the lock at a key is for while a device is connected). With Lock this Mac when the last device leaves on,
   nothing changed: the black holds until the lock shows, bounded by the lock's own 30 s + `lockConfirm` + the slack,
   and a key or click in that wait locks. Whether a device left on purpose is not told apart: that needs a word on the
   wire (a device's Disconnect and its own liveness check both close the connection cleanly, and the second
   reconnects), so every departure waits the same.
7. **Someone at the Mac (`local`).** While dark and the Mac reads unlocked, an input event that Sill did not post (it
   lacks `eventTag`, below): a key down or a mouse button down with `keysLock` on asks `lock` (at most once per
   `lockConfirm`), and shows the hint; with `keysLock` off it only shows the hint (the key reaches the app, unseen).
   A mouse movement only shows the hint (`hintFor` 10 s; a bumped desk never locks the Mac). While the reading is
   locked or off console nothing counts: the lock screen takes it. The key or click itself still reaches the Mac
   (an observer cannot stop it; open decision 3). A lock not confirmed within `lockConfirm` (no symbol, or it did not
   lock) never leaves the person at the Mac without a way back: the hint switches to the keys-passing wording
   (⌃⌘Q, macOS's own lock, which an observer never stops), and the line says so.
8. **Taken back (`takenBack`).** An unlock while dark (the reading becomes unlocked after screen locked or off
   console) is the Mac's own when no device input was posted at the locked screen in the `remoteUnlockWindow`
   (10 s) before it: `lift`, and the windows stay down until no session at all is connected, or a switch changes. An
   unlock right after a paired device typed at the lock screen (LockPolicy posts only a paired session's input there)
   is the device's: the windows stay. Off console nothing is posted for anyone, so a return to the console is always
   the Mac's own. Touch ID and an Apple Watch unlock are the Mac's own: the owner is at it.
9. **A switch changed.** `darken` off: `lift` at once, its grace cancelled (`lockAfterSession`'s own timer goes on).
   Turned on with a counting session connected: `raise` at once. Any change clears `takenBack`, so the owner who took
   the Mac back darkens it again by turning the switch off and on.
10. **No display to type at (#298).** No lock under rule 6 while the Mac has no physical screen and no display of
    Sill's that would show the lock screen at the next connect (#200's headless display, once merged): the password
    could not be typed back from a device. The line says so, and Settings shows it.
11. **Quitting.** `lift` at once; nothing locked (a quit is the Mac's own user, a logout or an update's restart; an
    automatic update waits for 5 minutes with no device anyway).
12. **A hung Sill (`hangLimit` 10 s, `relaunchSpacing` 600 s).** While dark the main actor beats once a second; a
    watchdog off the main actor that misses `hangLimit` of beats prints its line, opens Sill again (once per
    `relaunchSpacing`) and ends this one at once (`_exit`, no atexit handler that could wait on the stuck thread).
    The windows go with the process. The decision (`watchdogFires(lastBeat:now:dark:)`) is pure.
13. **Screens (`screens`).** Every screen AppKit lists but Sill's own displays (vendor 0x5111) and zero-size frames
    (#184's filter). Re-synced at every display change; a new display's window ordered in before the old ones go
    (D12), from the display reconfiguration callback as early as macOS tells.
14. **A test host** (DoorPolicy.isTestHost) decides the same and acts on nothing: no window, no monitor, no lock, no
    display sleep, no exit; lines and the stats keys `priv.raise`, `priv.lift`, `priv.lockDry`, `priv.hint`,
    `priv.localDry`, `priv.watchdogDry`.

Constants: `grace` 30, `lockConfirm` 3, `remoteUnlockWindow` 10, `hintFor` 10, `hangLimit` 10,
`relaunchSpacing` 600 (seconds); `eventTag`, a 64-bit constant every event Sill posts carries
(`CGEventSource.userData`, so `kCGEventSourceUserData`), never one a person's hardware does.

Invariants the random sessions hold the rule to (I1–I9): dark whenever a counting session is connected, the switch
on, a screen to cover, not quitting, not taken back; never dark with the switch off, while quitting or with nothing
to cover; never dark longer than `grace` + `lockConfirm` once no counting session is connected (R0); a lock only at
a grace's end with no session connected, or at a person's key or click while dark, never while locked, off console,
quitting, taken back or with no display to type at, at most once per end; taken back only by an unlock with no
device input at the locked screen in the window before it, cleared when no session is connected or a switch
changes; at a counting connect `raise` before the wake (the glue's copy); Sill's own events never local input; the
screens never a Sill display or zero size; the watchdog only while dark, only past `hangLimit`.

## With the locked Mac and with a display that sleeps

- **LockPolicy is unchanged and stays the authority** for what a device sees and does. The lock this plan adds is
  macOS's own lock screen, which LockPolicy already handles: the lock screen streams, a paired device types the
  password, nothing else of the Mac leaves it until the unlock. Rule 6 asks for "unlocked and established", the gate's
  settled reading; rule 8 uses the reading's change to unlocked (settled, 2 s after the unlock, so the owner who
  unlocks at the Mac sees black for those 2 s; open decision 8 has the raw witness instead).
- **Off console** (another user, the login window): this session's windows are not on the screen at all; the rule
  keeps its state, and a return to the console is the Mac's own unlock (rule 8).
- **DisplayWake is unchanged** but for the order (rule 5): a connect and a person's input still declare user activity,
  so the panel is lit (showing black) while the Desktop of a physical display streams, which is what keeps that
  picture live (#134). A window on Sill's own display may not need the panel lit, but declaring remote activity
  instead is no way to keep it off: Noah closed #229 on 2026-11-09, "going by Apple's published powerd source,
  declaring the remote user-activity type doesn't change whether the display wakes compared with what Sill already
  declares". Letting the panels sleep while dark would mean declaring nothing for such sessions, and only if Sill's
  display keeps compositing meanwhile (risk 2).
- **The waking click** (PR #228) reads `CGDisplayIsAsleep`, which the windows do not change.
- **The off-console view** (#316) is about another user on the console; nothing here touches it.

## Beside the related work

- **#200** (addhumal, open: Sill's own display for a headless Mac): rule 10's "display to type at"; its display
  (vendor 0x5111) is never covered. Either can land first.
- **#352** (the Virtual Desktop plan, draft): its open question 15 already names this work ("with a privacy mode
  (#133, #184) it could come later"); its phase 2 is risk 1's way out (the Desktop from Sill's display while dark),
  and its §8 open item on display sleep is risk 2.
- **#156** (dr-apple): a curtain at the shielding level with a label ("This Mac is in use on a device."), clicks
  absorbed, over displays that do not stream, after gathering every window onto its own display; and the Mac's
  output muted (open decision 13). Not taken: the gathering and the main-display switch are #352's.
- **#344** (Spectra3609's fork, a report): mirrors the Mac's displays and blacks them out with `.forAppOnly`, a 30 s
  grace and an optional lock on disconnect: the same grace as rule 6.
- **#134's work** (#151, #228 and #230 merged; #229 closed): unchanged but for rule 5's order.
- **The other workstreams of 2026-11-18** (microphone, camera, files, recording): independent. A recording made on
  the device (#284, #303) records what the device receives, which the black windows never reach.

## Files

Mac (`SillHostCore` unless said):

- **New `PrivacyPolicy.swift`**: the rule above, `Words` (every sentence below), `screens(_:)`, `watchdogFires`.
- **New `PrivacyScreen.swift`** (main actor, AppKit): owns the state; the windows (#184's recipe moved here: borderless,
  black, no shadow, `ignoresMouseEvents`, `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`;
  the level and opacity G0 picks), the hint view (two centred lines, 15 pt, 35 % white on black, faded out after
  `hintFor`); the screens' re-sync (`didChangeScreenParametersNotification` and
  `CGDisplayRegisterReconfigurationCallback`); the observers of the Mac's own input (`NSEvent`'s global monitor, and
  a local one for events sent to Sill itself: key down, mouse buttons down, mouse moved; each tells the rule only the
  kind of event and whether it carries `eventTag`, never a key code or a character, never logged); the heartbeat; the
  lines. Dry on a test host.
- **New `ScreenLocker.swift`**: `dlopen` of `/System/Library/PrivateFrameworks/login.framework/login` and `dlsym` of
  `SACLockScreenImmediate` (declared `@convention(c) () -> Void`, as #184 and the one published write-up found
  declare it; exported on macOS 27.2.1, never called here) and `SACScreenLockEnabled` (optional, for Settings'
  warning only), once, nil when missing, said once (as SymbolicHotKeys does); the call and the display sleep
  (`/usr/bin/pmset displaysleepnow`) on its own queue; the confirmation is SessionLock's reading within
  `lockConfirm`.
- **New `PrivacyWatchdog.swift`**: its queue and timer, the heartbeat behind a lock, the line written and the log
  flushed synchronously before `_exit(70)`, the relaunch (`/usr/bin/open -n -g` on Sill.app's bundle, never the bare
  binary) and its spacing remembered in a file written and synced before the exit.
- **`StreamCoordinator.swift`**: owns a `PrivacyScreen`; joins in `onClientConnected` before `deviceActive(.connect)`
  (:571) with the session's away flag; leaves in `onClientDisconnected`; away flags in `routesChanged`; the reading in
  `lockChanged`; a paired session's input posted at a locked screen (`deviceInputAtLockedScreen`, where
  `LockPolicy.takesInput` lets it through); the switches in `setTarget`; `lift` in `shutdownForExit`; the status's
  `privacyDark`, which AppModel's App Nap hold reads (the card shows nothing new).
- **`InputInjector.swift`**: `source.userData = PrivacyPolicy.eventTag` (:41), so every key, click, scroll, repeat
  and gesture chord Sill posts carries it.
- **`HostConfig.swift`**: `darkenScreen` (`.off` in `standard` and `app`), `darkenKeysLock` (true), `lockAfterSession`
  (false); the Mac's alone, like Share clipboard and the off-console view: absent from `StreamSettings`,
  `HostSettingsChange`, `DeviceSettings.accepted`, `applying` and `restartNeeded`, so no device changes them;
  applied at once by `setTarget`, never by a restart.
- **`HostStatus.swift`**: `privacyDark` (Bool).
- **`TestHooks.swift`**: the TEST ONLY hooks below, ignored with a line anywhere but a test host.
- **`Sources/SillHostCLI/main.swift`**: `--darken=away|any`, `--darken-keys=lock|pass`, `--lock-after-session`, taken
  only with `--synthetic` (a dry run); anywhere else one line says they are Sill.app's (the CLI shows no window under
  `dispatchMain`). Without them, stdout byte for byte as today.
- **`Sources/SillMenuBar/HostSettings.swift`**: keys `darkenScreen` (Bool, false), `darkenScreenScope` ("away" or
  "any", "away"), `darkenKeysLock` (Bool, true), `lockAfterSession` (Bool, false) in me.saffer.sill.mac; the switch
  and the scope kept apart so the scope is remembered while off. #184's `privacyMode` and `lockOnDisconnect` go (they
  never shipped).
- **`DevicesPane.swift`**: the section "While a Device Uses This Mac" after the off-console view's, before Paired
  Devices; `LiveDevicesPane`'s bindings; the warnings.
- **`RemoteAccessPane.swift`**, **`AppModel.swift`**, **`AppDelegate.swift`**: #184's section, controller and calls
  removed; `holdAppNapOff` also holds while `privacyDark` (the grace's timer must not be coalesced).
- **`DebugHooks.swift`**: `-SillSetAfter` keys `darkenScreen=off|away|any`, `darkenKeysLock=0|1`,
  `lockAfterSession=0|1`; previews `pane-devices-privacy-{off,away,any,keyspass,lock,noaccessibility,nodisplay,
  covered}-{light,dark}.png` and `privacy-hint-{lock,pass}.png` (views rendered offscreen, never a window on screen).
- **Removed**: `Sources/SillMenuBar/PrivacyModePolicy.swift` and `Tests/checks/privacy-mode/` (replaced).
- **New `Tests/checks/privacy/`**: README.md (its **Checks:** and **Compiles:**), main.swift, run.sh, mutants.py;
  compiles PrivacyPolicy.swift alone.
- **New `Scripts/privacy-probe/`** (TEST ONLY, G0) and **`Scripts/privacy-check/live.py`** (G4).

Device: nothing. No usage string, background mode, privacy manifest entry, pbxproj entry or harness case.

## Threading

- **Main actor**: the rule's state, the windows, the hint, the screens' re-sync, the input observers (NSEvent calls
  both monitors' handlers on the main thread), the coordinator's calls. The reconfiguration callback arrives on the
  main thread under the AppKit loop and hops with `Task { @MainActor }`.
- **`sill.privacy.lock`**: the lock call and the display sleep (each an IPC that may block: never the main thread).
  Its result goes back with `Task { @MainActor }`; the confirmation reads `SessionLock.shared.gate`, which any thread
  may read.
- **`sill.privacy.watchdog`**: a 1 s timer reading the heartbeat (an `OSAllocatedUnfairLock`'d time a main-queue
  timer sets while dark); it never touches main-actor state. HostLog takes lines from any thread; the watchdog flushes
  it synchronously before `_exit`.
- The order of rule 5 needs no lock: the coordinator's connect handler calls `PrivacyScreen` and then `deviceActive`
  in one main-actor turn; DisplayActivity's queue starts only after.

## Settings: names, places, defaults

| Setting | Where | Saved as | Default | CLI (test hosts only) | Bare binary |
|---|---|---|---|---|---|
| Darken this Mac's screen | Settings › Devices | `darkenScreen` | off | `--darken=away\|any` | `-SillSetAfter 'S darkenScreen=off\|away\|any'` |
| When (picker under it) | Settings › Devices | `darkenScreenScope` | Only while a device is away from home | (in `--darken`) | (in `darkenScreen`) |
| A key or click on this Mac locks it | Settings › Devices, under the first, while it is on | `darkenKeysLock` | on | `--darken-keys=lock\|pass` | `darkenKeysLock=0\|1` |
| Lock this Mac when the last device leaves | Settings › Devices | `lockAfterSession` | off | `--lock-after-session` | `lockAfterSession=0\|1` |
| Turn off its display too | Settings › Devices, under the lock, while it is on | `lockSleepsDisplay` | on | `--lock-after-session=nosleep` | `lockSleepsDisplay=0\|1` |
| Only after a device away from home | Settings › Devices, under the lock, while it is on | `lockOnlyAfterAway` | off | `--lock-after-session=away` | `lockOnlyAfterAway=0\|1` |

The lock's two switches came with the review of #402 (Noah's "a toggle wherever sensible", 2026-11-18): open decisions
5 and 6 as switches, at their recommendations. Only Sill.app itself locks or sleeps a display; the CLI and the bare
binary make the dry run whatever the switch says (`PrivacyPolicy.locksForReal`).

No device sets them. They let nobody in, so UserDefaults is enough (Require pairing, which would, lives in the
keychain). A launch argument overrides one for one run, as for every key (`-darkenScreen 1`). No menu item (open
decision 12).

## Every sentence shown to a person

All in `PrivacyPolicy.Words`, checked. On the device: nothing.

Settings › Devices, section header **While a Device Uses This Mac**:

- Toggle: "Darken this Mac’s screen". Picker under it: "Only while a device is away from home", "Whenever a device is
  connected". Toggle under it: "A key or click on this Mac locks it". Toggle: "Lock this Mac when the last device
  leaves".
- Footnote, all off: "For a Mac you use from afar: keep its screen dark while you use it, and lock it when you’re
  done."
- Footnote, darkening on, keys locking: "This Mac’s displays turn black while it’s in use from your iPhone or iPad, so
  people near it see nothing. A key or click on this Mac locks it; your password or Touch ID brings it back and keeps
  its screen lit."
- Footnote, darkening on, keys passing: "This Mac’s displays turn black while it’s in use from your iPhone or iPad.
  Keys and clicks on this Mac still reach its apps, unseen. To use it here, press Control-Command-Q and unlock it."
- Footnote, the lock on: "It locks 30 seconds after the last device leaves, so a connection that drops and comes back
  doesn’t lock it, and then its display goes to sleep."
- Warning, no Accessibility: "Sill needs Accessibility to notice a key pressed on this Mac. Allow it in Settings ›
  Permissions."
- Warning, no display to type at (rule 10): "This Mac has no display to show its lock screen on, so Sill won’t lock it:
  you couldn’t type its password from a device."
- Warning, the last lock failed: "Sill couldn’t lock this Mac the last time: ‹why›."
- Note, only if G0 shows covered apps stop drawing: "While the screen is dark, some apps stop drawing what it covers:
  the Desktop, and windows streamed with Virtual Display off, can stop updating on your device. Windows on Sill’s own
  display keep updating."

On each dark display (the hint, two lines, for 10 s after it goes dark and after the Mac's own mouse or keys are
used): "This Mac is in use from another device." and "Press any key to lock it." (keys locking) or "To use it here,
press Control-Command-Q, then unlock it." (keys passing).

Sill.log ("Privacy:" lines, one per change):
- "Privacy: this Mac’s screen is dark while a device away from home is connected (1 display)." / "… while a device is
  connected (2 displays)."
- "Privacy: the last device left; this Mac’s screen stays dark for 30 s in case it comes back." / "Privacy: a device
  came back within 30 s; nothing changes." / "Privacy: this Mac’s screen is lit again."
- "Privacy: locking this Mac: the last device left 30 s ago." / "Privacy: locking this Mac: someone pressed a key or
  clicked on it." / "Privacy: this Mac is locked; its display sleeps."
- At a session's end: "Privacy: couldn’t lock this Mac (macOS has no SACLockScreenImmediate); its display sleeps
  instead." / "… (it still read unlocked 3 s later) …". At a key or click on the Mac: "Privacy: couldn’t lock this Mac
  (‹why›); its screen now says to press Control-Command-Q." (no display sleep: a session still streams).
- "Privacy: not locking this Mac: it has no display to type its password at (issue #298)."
- "Privacy: unlocked on this Mac itself; its screen stays lit until every device has left." / "Privacy: unlocked from
  iPad (iPad14,1); this Mac’s screen stays dark."
- "Privacy: Sill’s main thread hasn’t answered for 10 s while this Mac’s screen was dark; Sill quits so the screen
  isn’t left black, and opens again." / at the next launch: "Privacy: Sill opened again after it quit with this Mac’s
  screen dark (its main thread had stopped answering)."
- Anything but Sill.app itself (a test host, the CLI, the bare binary): "Privacy (dry run): would darken 1 display;
  nothing is drawn." and the same "would lock", "would sleep the display", "would quit Sill" forms (part 1's lock says
  "Privacy (dry run): would lock this Mac now; nothing is locked." since the review of #402).

The menu's card: nothing new (it is covered while dark; open decision 12).

## Security

- **Who can turn it on or off:** the Mac's own Settings only (UserDefaults; a local process of this user could flip
  them, but it can already see the screen; nothing here lets anyone in, so the keychain is not needed, unlike Require
  pairing). No device, no kind 17. The bare binary's hooks never in Sill.app (`-Sill…After` and TEST ONLY hooks are
  ignored there with a line).
- **What a device can make happen:** darken the Mac by connecting (with `.any`, any session; with `.away`, one at the
  remote door from away, which takes only paired keys), and lock it by leaving. An unpaired device at a door with
  Require pairing off can do both: a nuisance for the person at the Mac, never a leak (darkening hides; Sill's lock
  never unlocks). A removed device cannot connect; one cut off mid-session counts as leaving.
- **What a device sees and does:** LockPolicy's, unchanged. A paired device still unlocks the Mac by typing its
  password at the lock screen (#271), which this plan turns into "the device's unlock" so the screen stays dark.
- **The person at the Mac** always has a way back that needs the password: a key (or ⌃⌘Q), then the password or Touch
  ID. Nothing the rule does ever shows the session to someone who has not unlocked the Mac, except the room-visible
  flash of rule 4's fallback and a newly attached display's first moments (risk 5).
- **The Mac's own input:** observed only while dark, only for its kind and Sill's tag; key codes and characters are
  never read, kept, logged or sent. A secure text field (a password) withholds its keys from observers anyway.
  privacy.html says so.
- **Private interface:** `SACLockScreenImmediate` can only lock. Missing or failing, the rule says so; at a
  session's end the display sleeps instead, at a key on the Mac the hint points to ⌃⌘Q, macOS's own lock.
- **The watchdog** can end Sill (ending every session) only while dark and only after 10 s without a main-thread
  answer; it reopens Sill at most once in 10 minutes, so it is no loop.
- **Small leaks, named in the docs:** the pointer still shows and moves on the black screen (until run 6 of PR #400:
  hidden since, open decision 14 below); the Mac's speakers keep
  playing the session's sound (open decision 13); a Touch Bar keeps showing the front app's controls; with keys
  passing, VoiceOver started at the Mac can read the covered windows aloud (with keys locking, its shortcut locks the
  Mac first).

## Tests

**G0, the probe (Noah, first, ~15 minutes; it darkens this Mac's screens in spells of at most 10 s).**
`Scripts/privacy-probe/run.sh` builds `probe.swift` (AppKit and ScreenCaptureKit, as restore-probe is built) and runs
each step under a hard 12 s kill from the shell, so the screen always comes back. It needs Screen Recording and
Accessibility for the terminal that runs it, an unlocked screen, and no device streaming (it never uses the encoder,
but it darkens the screen). It reports, per step:
1. Its own test window (redrawn 60 times a second by a timer, plus a display-link-driven layer): its occlusion state
   and redraws, and ScreenCaptureKit frames from a capture of that window and from a display capture leaving the
   probe's black windows out, uncovered and then under each candidate: S1 opaque at `.screenSaver` (#184's), S2
   non-opaque (black content, `isOpaque` false) at `.screenSaver`, S3 opaque at the shielding level, S4 opaque at
   1500. The same for a Safari window Noah leaves playing a video, and a VS Code (or any Electron) window. **This
   decides whether the windows freeze what they cover, and whether S2 avoids it.**
2. The window server's list (owner, layer) every second while dark, with prompts for Noah: ⌃⌘Q (is the lock screen
   above, can he type and Touch ID?), a notification (`osascript -e 'display notification "test"'`), the volume keys,
   ⌘Space, F3 (Mission Control), ⌥⌘⎋ (is Force Quit above?), the pointer. **This picks the level and settles rule 4.**
3. `kill -9` of the probe while dark, and a stopped probe (`kill -STOP`, then the shell's kill): the screen back at
   once after each.
4. A tagged posted event and an untagged one: the global monitor tells them apart (needs Accessibility).
5. An external monitor and Sidecar if present, an HDR video under the window on an XDR panel, Night Shift and True
   Tone on: black stays black.

**G0's results (Noah's Mac14,9, macOS 27.2.1, 2026-11-23 15:19; the report in sill-handoff's
next/privacy-darken/probe-report.txt).** 1: under S1 to S4 the test window, a Safari video and an Electron app's window
drew at 99 to 101 % of their uncovered rate and the captures held 57 to 58 frames a second: nothing freezes, so risk 1
did not happen and no note is needed. 2 (all at 1000): the lock screen came in front (loginwindow, layers 2001 and 2004)
and Noah locked and unlocked over the black, which stayed until the spell ended; a notification (layer 23), the volume
indicator (101), Spotlight (23), Mission Control (2 to 20) and Force Quit (996) stayed behind it; the pointer showed;
another app's window at 1000 was listed in front of the black for a whole spell. 3: a killed probe's black went in 14
and 16 ms, a stopped one's stayed. 4: NSEvent's global monitor kept the tag; posted events named their poster's process,
Noah's pointer move process 0 (no key of his reached the report). 5: two screens, Night Shift, True Tone and an HDR
video: pure black. Chosen from it: level 1501 (above the screen saver's 1000 and the assistive 1500, under the lock
screen's 2001), opaque, `staysUnderLockScreen` true, Sill's own input by its tag or its process, a click named in the
hint, and the watchdog built (docs/steps/2026-11-18-privacy-darken.md, run 4).

**G1, the check** (`Tests/checks/privacy`): each rule's cases (both scopes, a move home, the grace and a return
within it, the lock with and without confirmation, the missing symbol, no display, local keys and movement with keys
locking and passing, locked and off console, the Mac's own unlock and the device's, the switches mid-session,
quitting, two screens and Sill's display, the watchdog, a test host), the words (each sentence, and that every log
line names what it says), 20,000 seeded random sessions against I1–I9, and a copy of the coordinator's glue for the
order at a connect. Mutants for every rule, each pattern applying once, all caught; the unchanged check passes first.
`Tests/checks/run-all.sh`, `repo-rules`.

**G2, builds:** `swift build -c release` from a clean `git archive`; the iOS app untouched (`git diff --stat` shows no
iOSClient file), so its build is CI's.

**G3, H2:** the CLI against main, idle 45 s and with a test client on the Desktop 20 s, masked and sorted: identical
without the new flags.

**G4, live on loopback** (`Scripts/privacy-check/live.py OUT [order|scope|grace|local|takeback|quit|watchdog|all]`,
each host under 60 s: `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1
SillHost --synthetic --darken=… [--remote --pairing]`, with `SILL_TEST_LOCK_IGNORE_MAC=1`):
- *order*: at each test client's connect the host's "would darken" line comes before its `disp.wakeDry` (both stamped
  by `SILL_TEST_PRIVACY_LOG=1`);
- *scope*: at the remote door with `SILL_TEST_REMOTE_ORIGIN=vpn` the host darkens under `--darken=away`, with `lan` it
  does not, under `--darken=any` both;
- *grace*: with `SILL_TEST_PRIVACY_GRACE=5`, a client that leaves and one back after 3 s: no lock; gone for 5 s: "would
  lock", then the confirmation from `SILL_TEST_LOCKED_FILE` written 1 (lift, "would sleep the display") or left alone
  (the failure's line, lift);
- *local*: `SILL_TEST_PRIVACY_INPUT=<file>` (a test host reads `move`, `key` or `click` once from it, as the Mac's own
  input): the hint, then "would lock" for a key with keys locking and none with keys passing; nothing while the file
  for the lock reads 1;
- *takeback*: locked by the file, unlocked with no device input: "unlocked on this Mac itself", lift; locked again,
  a paired client's tap posted (dry) at the locked screen (lock-check's `paired` setup: `--pairing`, Require pairing
  off for the run, `SILL_TEST_POINTER_PATH` so the tap lands), then unlocked: "unlocked from …", dark;
- *quit*: SIGTERM while dark: the lift line before the exit;
- *watchdog*: `SILL_TEST_PRIVACY_STALL=12` (a test host's main actor blocked once for 12 s while dark): "would quit
  Sill" after 10 s, and the host goes on.
New TEST ONLY hooks, honoured only by a test host and listed in TestHooks: `SILL_TEST_PRIVACY_LOG`,
`SILL_TEST_PRIVACY_GRACE`, `SILL_TEST_PRIVACY_INPUT`, `SILL_TEST_PRIVACY_STALL`.

**G5, previews** from the bare binary (`-SillRenderPreviews`): the section in each state, light and dark, at 520 pt
on one line per toggle; the hint in both wordings. Identical to main's otherwise.

**G6, an independent read-only review** of the branch before the first build, as the PiP and update plans had.

**Harness photos:** none (nothing on the device).

**Noah's devices (N list), after G0, with Sill.app built from the branch (release-signed with the profile, never the
installed copy replaced without his word) and Sill for iPhone or iPad 0.6.2 from the App Store (nothing changes on
it):**
1. G0 above.
2. Darkening on, "only away". `pmset displaysleepnow`, connect the iPhone through Tailscale: the Mac's panel lights
   black with the hint, never the desktop, even for a moment; the iPhone's picture is live. Sill.log: "Privacy: this
   Mac’s screen is dark while a device away from home is connected (1 display)."
3. The same at home on Wi-Fi: the screen stays as it is. Switch to "whenever": black at once.
4. A window with Virtual Display on (Safari playing a video): live on the iPhone. The Desktop: live or frozen (compare
   with G0). Virtual Display off, a window: the same.
5. A key at the Mac: it locks; the iPhone shows the lock screen; type the password on the iPhone: the Mac's screen
   stays black. A key at the Mac again: locks; Touch ID at the Mac: the screen comes back and stays while the iPhone
   is connected. "Privacy: unlocked on this Mac itself …".
6. Mission Control and Spotlight from the iPhone, a notification (message yourself), the volume keys at the Mac:
   nothing of the session shows on the Mac's screen (or note what does, and at which level).
7. The built-in panel, an external monitor and (if at hand) Sidecar: all black. Plug a monitor in while dark: how long
   its picture shows before it goes black.
8. Close Sill on the iPhone: 30 s later the Mac locks and its display sleeps. Again, and reopen Sill within 20 s: no
   lock, the screen stays black. Turn the iPhone's Wi-Fi off for 10 s: no lock.
9. Darkening off, the lock on (#283 alone): close Sill on the iPad at home: 30 s later the Mac locks.
10. Quit Sill while dark (`osascript -e 'quit app "Sill"'` from an SSH session, since the menu is covered): the
    screen comes back at once. `kill -9` Sill while dark: back at once.
11. HDR video, Night Shift and True Tone on, a mini-LED panel at night: black stays black; note the backlight on an LCD
    monitor.
12. A fast user switch while dark, and back with the password at the Mac: the screen lit (the Mac's own unlock).
13. The lid closed with a monitor; a Mac with no display (with #200 if merged): darken and lock as expected; without
    #200, Settings' warning and no lock.
14. Settings › Devices: the words, the picker, the warnings (Accessibility off), VoiceOver reading the section; the
    hint's two lines on a dark screen.
15. Keys passing: a key at the Mac reaches the front app; ⌃⌘Q locks; the password at the Mac lights the screen.
16. A long stream (an hour) dark: the hint never stays on, the panel sleeps by its own setting between inputs, no
    "Privacy" line beyond the expected ones.

## Docs, site and App Store words (for the release that ships it, Sill for Mac's next minor version)

- `docs/privacy-mode-plan.md` (this plan, in the repository), `docs/steps/<date>-privacy-mode.md` (`Scripts/steps.sh
  new`), CLAUDE.md's layout (PrivacyPolicy, PrivacyScreen, ScreenLocker, PrivacyWatchdog, the check, the probe, the
  live gates) and its Build and run lines (the CLI flags for test hosts, the hooks).
- DEVELOPMENT.md: "This Mac's screen dark while a device uses it": the settings and keys, what the person at the Mac
  sees and does, the lock, the watchdog, the test hooks, G0, why gamma is not used.
- site/support.html (inside markers, for a republish before the release as the display-wake paragraph has):
  "Keep your Mac’s screen dark while you use it from afar. In Sill on the Mac, Settings › Devices: turn on Darken this
  Mac’s screen. While your iPhone or iPad uses the Mac from away (or whenever one is connected, if you choose), every
  display of the Mac is black, and a key or click on the Mac locks it. Lock this Mac when the last device leaves locks
  it 30 seconds after you’re done." And under troubleshooting: "If your Mac’s screen stays black: press any key; the
  Mac locks, and your password or Touch ID brings it back. If Sill has stopped answering, it quits by itself within
  about 10 seconds and opens again."
- site/privacy.html, beside the Accessibility paragraph: "While Darken this Mac’s screen is on and the screen is dark,
  Sill for Mac notices whether a key is pressed or the mouse is used on the Mac itself, only to lock it. It reads no
  key and keeps or sends nothing of it."
- README's Tips: one line. Release notes and the Mac's What's New: "Privacy: keep your Mac’s screen dark while you use
  it from afar, lock it when someone touches it, and lock it by itself when you disconnect (Settings › Devices)."
- The App Store's description of Sill for iPhone and iPad, once that Mac release is out: "Your Mac’s own screen can
  stay dark while you use it from afar." No iOS build is needed for it.
- Replies on #133, #323, #275 and #283 drafted for Noah, posted only on his word.

## Order of commits

1. The branch from #184's head; main merged in (the four conflicts resolved keeping both sides, `SessionLock.unlocked`,
   the check's README.md, no static matrix or table row), so it builds as #184 behaves; the step file and this plan.
2. `Scripts/privacy-probe/` (G0). Noah runs it; its results go into the plan and pick the level, the opacity and rule
   4's constant.
3. `PrivacyPolicy.swift` and `Tests/checks/privacy` with mutants (replacing PrivacyModePolicy and its check).
4. `HostConfig`, `HostSettings`, the CLI flags, `DebugHooks` keys, `TestHooks`.
5. `ScreenLocker` and the lock after a session (rule 6 with `darken` off, rules 10 and 11): **#283 and #275 alone,
   shippable before darkening.**
6. `PrivacyScreen`, `PrivacyWatchdog`, the coordinator's hooks (the order at a connect, routes, readings, the
   locked-screen input), `InputInjector`'s tag.
7. Settings › Devices' section and the previews; #184's Remote Access section and app-side controller removed.
8. `Scripts/privacy-check/live.py` (G4) and its results; H2.
9. Docs, site, privacy page, CLAUDE.md.
10. G6's review and fixes; main merged again; CI; Noah's N list; the merge on his word, with every known defect named
    (the covered windows if G0 shows them).

## Risks

1. **Covered windows stop drawing** (D4). If G0 shows it and S2 does not avoid it, the Desktop and Virtual-Display-off
   windows can freeze on the device while dark: a known defect for Noah's merge decision (open decision 10). The way
   out is to stream the Desktop from Sill's own display while dark, the Virtual Desktop of #352's phase 2.
2. **Sill's display while the panels sleep.** Nobody knows whether a CGVirtualDisplay keeps compositing while every
   panel sleeps (docs/virtual-desktop-plan.md §8). If it does, a dark Mac whose every stream comes from Sill's display
   could let its panels sleep (DisplayWake declaring nothing for those sessions; the remote activity type does not
   help, per Noah on #229). Not relied on here.
3. **The level.** Too low, and notifications, Mission Control or a HUD show the session to the room; too high, and the
   lock screen is covered (R0). G0 picks it; rule 4's fallback exists for the second case.
4. **The private lock** can vanish or change in a macOS update: the rule confirms every lock through SessionLock and
   falls back to sleeping the display, and says so.
5. **A display attached while dark** shows its picture until its window is ordered in (a fraction of a second,
   measured in N7).
6. **The watchdog** ends sessions on a long but legitimate main-thread stall: 10 s is far above any stall seen
   (Accessibility calls are bounded at 1 to 1.5 s), and it runs only while dark.
7. **The observer of the Mac's own input** looks like a keylogger to a cautious reader: it reads no key, the privacy
   page and the code say so, and it exists only while dark.
8. **#298 and headless Macs**: the lock is refused without a display to type at until #200 is in.
9. **Two people at once** (the owner at the Mac and a remote user both typing): the Mac locks at the first local key;
   whoever has the password wins. Documented, not prevented.
10. **An active event tap** (open decision 3's alternative) has a known system-wide input hang when Accessibility is
    revoked while it is active (Apple forums 844416, FB24619068, macOS 15 to 27): the default here is an observer,
    which is not affected.

## Open decisions for Noah

The recommendation is what the work proceeds with if he says nothing.

1. **Where do the switches go?** Settings › Devices (beside Require pairing and the off-console view) / General /
   Remote Access (#184's place). **Recommend Devices**: it is about devices using the Mac, and #283 says "this isn't
   only about remote access".
2. **Darken while what, by default once turned on?** Only while a device is away from home / whenever any device is
   connected. **Recommend away** (the assignment's "when remote access is being used"; a device at home is often on
   the desk beside the Mac); the other is one tap away.
3. **A key or click at the dark Mac?** It locks the Mac, the key or click itself still reaching the app (an observer,
   no new permission) / blocked entirely and locks (an active event tap: nothing reaches the apps, but the
   input-hang risk and possibly Input Monitoring) / passes through unseen (#184). **Recommend lock with an
   observer.**
4. **The wait before locking after the last device leaves?** 30 s / 10 s / 2 minutes / none (#184). **Recommend 30 s**
   (a device's reconnect after a drop takes a few seconds; iOS suspends Sill some seconds after it leaves the screen).
5. **Lock after which sessions?** Any (#283's words) / only one that had a device away from home. **Recommend any**.
   Since the review of #402 a switch under the lock, Only after a device away from home, off by default.
6. **Sleep the display after the lock?** Yes (#275, #184) / leave the lock screen lit. **Recommend yes.** Since the
   review of #402 a switch under the lock, Turn off its display too, on by default; a lock that fails still sleeps
   the display either way.
7. **What the person at the Mac sees?** Black with the two-line hint for 10 s after it darkens and after they touch it
   / pure black, as Apple's High Performance screen sharing (reported to look like a broken Mac) / the hint always
   (an OLED burn-in risk). **Recommend the 10 s hint.** And the device's name in it? **Recommend no.**
8. **Taking the Mac back.** An unlock at the Mac keeps its screen lit until every device has left / until the device
   connected then leaves / never (dark again at once). **Recommend until every device has left.** And decide at the
   settled unlock (2 s of black after Touch ID) / at the raw witness (about 0.1 s, a second code path). **Recommend the
   settled unlock** for now.
9. **A hung Sill while dark.** Quit after 10 s and open again once in 10 minutes / quit without reopening (a remote
   user loses the Mac until someone opens Sill) / a separate helper process holds the windows and drops them when
   Sill's heartbeat stops (no quit, but a second executable, its own signing and its windows to leave out of every
   capture). **Recommend quit and reopen.**
10. **If G0 shows covered windows stop drawing.** Ship with the note in Settings and name it at the merge / hold
    darkening until the Virtual Desktop (#352 phase 2) streams the Desktop from Sill's display while dark / while dark,
    stage picked windows on Sill's display even with Virtual Display off. **Recommend ship with the note, the lock
    after a session first, and the Desktop on Sill's display once the Virtual Desktop lands.**
11. **The device.** Nothing in this version / a line in the device's Settings panel ("‹Mac›’s screen is dark while you
    use it") and a switch there, through optional fields of kinds 16 and 17. **Recommend nothing now.**
12. **Sill's menu.** No item / "Darken This Mac’s Screen" while a device is connected and the Mac was taken back.
    **Recommend no item** (turning the switch off and on does it).
13. **The Mac's own speakers while dark.** Unchanged / muted while a device plays the Mac's sound (#156's idea;
    macOS 14.2's Core Audio process taps can take an app's sound muted, with their own permission; whether the mute
    ends with Sill's process, as R0's spirit asks, is unchecked). **Recommend unchanged in this version**, a
    follow-up issue.
14. **The pointer on the dark screen.** Shown / hidden (needs a private window-server property to hide it while Sill
    is in the background). **Recommend shown.** **Decided, hidden** (Noah, 2026-11-24, after his first try: "The
    cursor is still shown when darkened"): rule 15 in DarkenPolicy, Settings' Hide the pointer too (on), run 6 of
    PR #400.
15. **How #184 lands.** A branch in Saffsanity/sill from its head, so it shows as merged (#355's way) / pushed onto
    addhumal's fork with maintainer edits / redone, crediting him. **Recommend #355's way.**
16. **One pull request or two.** The lock after a session (#283, #275) first, darkening after G0 / together.
    **Recommend the lock first**: it needs no measurement and is half the asks.
17. **The CLI.** Dry runs on test hosts only / a real `--darken` that runs the AppKit loop. **Recommend dry runs
    only.**

## What could not be verified by reading

- Whether a window of another app at level 1000 (or any level) makes the windows under it stop drawing, and whether a
  non-opaque one does not: G0.
- Which windows (the lock screen, notifications, Mission Control, Force Quit, HUDs, Spotlight) sit above which level
  on macOS 27, and so rule 4's constant: G0.
- That the window server removes a killed process's windows at once (universal behaviour, never checked here), and
  what a stopped one leaves: G0.
- `SACLockScreenImmediate`'s signature and behaviour on macOS 27 (exported, measured; never called here), and what
  `SACScreenLockEnabled` means.
- Whether NSEvent's global monitor keeps a posted event's `kCGEventSourceUserData`, so Sill's own events are told
  apart: G0 step 4.
- Whether macOS 27 asks for Input Monitoring for a key monitor (Apple documents Accessibility for it).
- Jump Desktop's mechanism (its article would not load); Apple's High Performance screen sharing's (private).
- Everything about the panel's behaviour under the windows (backlight, HDR, Night Shift) beyond black being black.

## Progress

- 2026-11-18, part 1 (branch `privacy-lock`): #184's head merged in as it is (main's four conflicts resolved, its
  check's README.md); then the lock alone, as rule 6 with `darken` off, rules 10, 11 and 14 (docs/steps/
  2026-11-18-privacy-lock.md has what was built, proven and left for Noah). Draft pull request #402. Its review: only
  Sill.app itself locks (the bare binary had the real locker), open decisions 5 and 6 as switches under the lock, the
  gate's reading moved into the rule.

