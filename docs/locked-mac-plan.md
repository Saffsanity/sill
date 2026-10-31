# A locked Mac shows nothing of itself: the plan

Branch `locked-mac` from main at e4d30349. Noah's finding of 2026-10-31, a security fix: no public
issue. Noah's rule, the same morning: "When the user is locked, it should only show the lock screen, no
virtual desktop, no desktop, no apps, nothing other than the login screen." And: "make sure this fixes
it for good!"

## The finding

Sill asked whether this Mac's console was unlocked (`SessionLock`) for two things only: the pairing
ask rule (`DoorPolicy.ask`'s step 1) and the cable's automatic pairing. Everything else ignored the
lock. With the screen locked, or with another user selected at the login screen while Noah's session
ran in the background, a paired device (and, at a door that lets any device in, an unpaired one) could
still:

- pick a window and see its content: window capture (`SCContentFilter(desktopIndependentWindow:)`)
  draws the window whatever covers it, and the virtual display's app filter
  (`SCContentFilter(display:including:)`) leaves the lock screen out;
- stream the Desktop, which off console is this session's own desktop, not the login window (main's
  build streamed it on 2026-10-30 and 31, below);
- see every window's thumbnail, the running apps' icons and the installed apps;
- launch apps (Noah saw it, another user selected at the login screen), press a window's traffic
  lights, read and choose the streamed app's menus, post trackpad gestures, read and write the
  clipboard, hear the Mac's sound, see the Mac's pointer and cursor shape;
- type and click: off console into another session's world, at a locked screen into its password
  field, an unpaired device too;
- wake the console's display (DisplayWake's activity), and make a virtual display that joins the
  console's display set.

### Noah's test of 2026-10-31, read again

The Sill.app that ran through Noah's fast user switch (04:25:36 to 04:26:57 local) was main's, 0.5.5
(1232), running since 2026-10-30 01:47 (1232 is `git rev-list --count e4d30349`). This branch's first
build, 1245 (b1404215), started at 04:27:23, 26 s after his unlock, and has seen no lock or switch since
(loginwindow's notifications, checked to 05:11). So what he saw ("I could see a desktop when I switched
users", "could still launch apps") was main's behaviour, and the missing "Locked:" lines say nothing of
this branch: it was not running. The diagnosis given the review that morning, a main actor blocked in
WindowServer calls, was wrong: build 1232's main actor printed all through the switched-out minutes
(the catalog, "Desktop: display 147 → 151", "Selecting window 12882 Calculator", the virtual display's
fallback, clicks, "Window 12882 close: done", "Capture started"). No main-actor heartbeat gate was
built. The second login screen Noah saw is macOS's own: this Mac locks itself 1 to 1.6 s after every
return to the console (loginwindow: sessionDidMoveOnConsole, then screenIsLocked; also on 2026-10-28
and 29 with no device connected), and Sill posted no input then. **Noah's next test is the first one of
this fix.**

What build 1232 showed off console, from its log and the system's: ScreenCaptureKit's display and
window captures deliver frames (40, 41, 20, 18 and 52 complete frames a second of this session's own
display, while the login window drew the same panel as display 0x9a); CGVirtualDisplay never comes
online and is added to the console's display set; Accessibility actions work (a window's close);
NSWorkspace launches work; posted clicks reach nothing visible; the whole Mac's sound is captured (50
buffers a second); DisplayWake's declaration turned the console's display on.

## The rule

`LockPolicy` (pure; `Sources/SillHost/LockPolicy.swift`, checked by `Tests/checks/lock-policy` with
mutants, in CI's matrix), read by `SessionLock` (`Sources/SillHost/SessionLock.swift`).

### Three readings

- **unlocked**: this session is on the console and its screen is unlocked;
- **screen locked**: this session is on the console with its lock screen up;
- **off console**: another user's session, the login window, or nobody is on the console.

### The witnesses, and an unknown counts as locked

Read on SessionLock's own queue (`sill.lock`), never on the main actor; any one saying locked wins:

| Witness | How | Says |
|---|---|---|
| The console's user | SCDynamicStore's State:/Users/ConsoleUser (`SCDynamicStoreCopyConsoleUser`), watched on the queue and read at each look; the top-level user, never SessionInfo's per-session kCGSSessionOnConsoleKey (it stayed 1 for this session for a minute of a switch, 2026-10-31) | this user, or off console (another uid, loginwindow, nobody, no answer) |
| The screen's lock state | notify(3)'s `com.apple.sessionagent.screenIsLocked`, registered with `notify_register_dispatch` on the queue and read at each look (loginwindow sets it to 1 at a lock, to 0 at the unlock and when this session moves off the console) | locked (1, or no answer) or unlocked (0) |
| The session dictionary | `CGSessionCopyCurrentDictionary`, a WindowServer round trip on a queue of its own with a 0.5 s bound, read once at start whatever the others say (the first reading needs every witness), then only to confirm an unlock the others say | locked, off console, or unlocked; no dictionary, or no answer in time, counts as locked |
| Sill.app's notifications | `com.apple.screenIsLocked`, `screenIsUnlocked`, `sessionDidMoveOffConsole`, `sessionDidMoveOnConsole` (DistributedNotificationCenter, `.deliverImmediately`: none waits while Sill is not active) and NSWorkspace's `sessionDidResignActive`/`BecomeActive` | a lock or a switch away sets the reading at once, in the handler, with no other work; an unlock or a switch back never unlocks by itself |
| TEST ONLY | a test host's SILL_TEST_LOCKED or SILL_TEST_LOCKED_FILE (below) | its reading, the more restrictive winning |

A lock notification with no unlock yet holds the Mac locked, until its unlock or until notify(3) saw
the unlock; a switch-away notification until the switch back, or until the console's user is this one
again (so a lost notification never holds it locked for good once a witness saw the change). Before
every witness has been read once the reading is unknown, and the gate reads off console.

### The effective reading

`LockPolicy.Reader`: a lock, and a change between the two locked readings, at once; an unlock only once
every witness has said unlocked for 2 s (`settle`) and a session read started since confirmed it. So the
flap of every return to the console (on the console and unlocked for 1.2 s, then macOS's own lock)
never lets a window out, and no virtual display is made for it. The first reading with every witness
read is taken as it is: a host that starts on an unlocked Mac waits for nothing.

SessionLock looks at start, at each witness's change (the notify callback, the dynamic store's, a
notification), once a second while a device is connected (`devices`), and when a settle ends; the CLI
and Sill.app alike, the notifications Sill.app's alone. The reading goes to the gate (`LockGate`) the
moment it changes, from whichever thread looked, and its line is printed then; the coordinator hears of
it through `onChange` and acts on the reading as it is when it runs.

### What each reading allows (`LockPolicy.allowed`)

| | unlocked | screen locked | off console |
|---|---|---|---|
| The picture | the source | a placeholder: a black still, no capture (`lockScreenStreams`, off, would stream the display) | the placeholder |
| Windows: listed, picked, staged, sized, thumbnails, buttons, menus | yes | no | no |
| Icons, the installed apps, launches | yes | no (withheld, sent at the unlock) | no |
| Sound, clipboard, pointer (26), cursor shape (14), gestures | yes | no | no |
| Sill's virtual display | yes | none made; a staged window goes home | none |
| Input (kind 8) | every session | a paired session's (the owner types the password); any other only the up of what it holds down | nobody's, but the up of a key or a button held down |
| Display activity (DisplayWake) | as ever | a paired session's taken input only; never a session's start | never |

Paired: the session's key, proved in its TLS handshake, is on the Mac's trust list now
(`sessionPaired`). The CLI's plain door carries no key, so nobody types through it at a locked Mac.

### The server's gate (`LockGate`, `LockPolicy.withheld`)

StreamServer reads the gate on its network queue for every message it sends: from the moment the
reading is locked it sends no frame or parameter sets but the placeholder's (each frame is broadcast
with what it shows: `Picture` placeholder, display or window), no thumbnail (3), icon (4), app list
(5), cursor shape (14), pointer (26, not even read), clipboard (32) or sound (43), whatever the main
actor is doing; the captures stop right after, on the main actor. The window list, settings, the
Mac's identity, the menus' answers (none has items while locked), pongs and ticks go as ever. The
catalog, the clipboard, the menus' mirror, the input injector and the virtual stage ask the gate too
before each thumbnail, look, write, read, press, post, repeat, gesture, display or cursor warp.
An icon or the app list that the coordinator sent just before the lock and the gate then withheld (a
send that raced it) is reported (`StreamServer.onCatalogWithheld`), and the unlock sends that device
every icon and the apps, so none is missing afterwards.

### A device's requests (`LockPolicy.decide`)

Each is judged by the more restrictive of the reading as it arrived (the network queue's) and the
reading when the main actor handles it, so nothing sent while locked acts after the unlock, and nothing
that arrived unlocked acts after a lock:

| Request | Locked (either reading) |
|---|---|
| A window picked (6) | refused (quiet on the device: its list is empty) |
| The Desktop, or nothing, picked (6) | taken: the Desktop is the placeholder |
| An app launched (7), a window's buttons (15), a menu fetched or chosen (27 with an id, 25), a gesture (28), a device's clipboard text (32) | refused; the menus answered "The Mac is locked." |
| Input (8) | as the table above says |
| The subscriptions (27 without an id, 32 without text), settings (17), the viewport (9), a keyframe (44), Pair This iPad… (21), pings, stats, the hello | as ever (the ask answers "locked" by itself) |

A fetch or a choice that came before the lock and waited its turn reads, activates and presses nothing
(MenuMirror's own look at the gate); a launch asked for before the lock picks nothing; input held for
an activation goes as ups only; a queued gesture is refused.

### The stream

- **The lock** (`lockChanged`, `enforceLock`): the window list without windows, with `locked` and, off
  console, `offConsole`; the menus without an app, no sound, the clipboard's look stopped, no pointer
  or cursor shape, a held key's repeat stopped, a launch asked for before forgotten; a window that
  streams goes home (WindowRestore's way, or the stage's, whose display goes) and the placeholder
  streams in its place, the window remembered (`LockPolicy.Restore`). With a device connected and
  nothing streaming, the placeholder too. Its keyframe replaces every device's last picture, an older
  device's too.
- **While locked**: any select of a window becomes the Desktop, the placeholder, remembered as what
  comes back (a restart, a launched app's first window, a pick queued before the lock); a switch to a
  window that finds the gate locked after one of its awaits stages, sizes, raises and captures nothing
  (`lockedMidSwitch`, and the stage's own `Failure.locked` before a display is made); a Desktop switch
  that finds it locked starts the placeholder instead of the display.
- **The unlock** (after the settle; `afterUnlock`): the catalog looked at afresh, the withheld icons and
  apps sent (all of them to a device that connected while locked), the window list, every thumbnail
  taken again, then in place of the placeholder the remembered window if it is still listed (as a
  restart: nothing comes forward on the Mac), else the Desktop. A pick made since wins.
- **Changes that coalesce** (a lock and an unlock both before the main actor ran): `lockChanged` acts
  on the reading as it is, and also when nothing changed but what streams does not fit it
  (`LockPolicy.reconciles`: a window or the display while locked, the placeholder or a locked list
  while unlocked). The random sessions of the check found this case.
- **The lines** (SessionLock's, at the change): "Locked: this Mac's screen is locked; devices see none
  of it until it is unlocked, and only a paired device types at it.", "Locked: another user, or the
  login window, is on this Mac's screen; devices see none of this session, and nothing they send is
  posted, until it is back.", "Unlocked: this Mac's screen is unlocked; devices see its windows
  again." None for the first reading when it is unlocked. At most one line a minute per refused kind.
  Stats: `lock.withheld` (the gate), `lock.refused`, `in.locked`, `cap.placeholder`.

Unlocked, nothing is changed: no field in the window list, no line, no request treated otherwise.

## Device

`WindowList.locked` and `offConsole` (`StreamClient.lockWhy`, `LockedMac.why`): at a list that says
locked the client removes the picture at once, on its network queue before any later frame
(`HEVCDisplayView.blank`), and covers the stream (`LockedMacShade`, `StreamClient.lockShade`) worded
for the two cases (`LockedMac`, StreamProtocol, checked with the host's rule):

- locked: "‹Mac› is locked", and "To unlock it from here, type its password and press Return. Its
  windows come back once it is unlocked." for a paired session, "Its windows come back once it is
  unlocked." for any other;
- switched to another user: "‹Mac› is switched to another user", "Its windows come back when you switch
  back to your account on the Mac. Nothing typed here reaches it meanwhile.";
- after the unlock, "Unlocking…" until the first keyframe after it, 4 s at most.

The Apps drawer and the Settings panel's header show the one line ("‹Mac› is locked. Unlock it to see
its windows." or "‹Mac› is switched to another user. Its windows come back when you switch back on the
Mac."). VoiceOver reads the cover as one element. The cover takes no touch: a paired device's keys and
taps still go to a locked screen, where the Mac takes them. DEBUG `-SillMacLocked 1|2|unlocking`.

## TEST ONLY

Honoured only by a test host (one that does not advertise and is not Sill.app's own code; TestHooks
lists them, and anywhere else each is ignored with one line):

- `SILL_TEST_LOCKED=1`: this session's screen locked for the run.
- `SILL_TEST_LOCKED_FILE=<path>`: read at each look (once a second while a device is connected): `1`
  the screen locked, `2` off console, anything else nothing (the real witnesses decide).
- `SILL_TEST_LOCK_NOTIFY=<name>`: the screen's lock state from a notify(3) name of the test's own
  (under `me.saffer.sill.test.`), which the test sets (`notify_set_state`, `notify_post`): the CLI's
  immediate path, end to end. Never a name another process listens to.
- `SILL_TEST_LOCK_NOTE='<s> <name>[; <s> <name>]'`: each named notification delivered to SessionLock's
  handler s seconds after it starts, as that notification would be: the handler's path without a real
  lock and without posting anything another app hears.
- `SILL_TEST_LOCK_LOG=1`: each look's witnesses and reading.

`Scripts/lock-check/` runs the whole host through locks and unlocks with test clients reading frames:
`live.py OUT [poll|start|notify|paired|all]` (each host on loopback, under 60 s), `sillclient.py --dump=DIR`
(what arrived when, the parameter sets and keyframes), `frames.swift` (the keyframes decoded on
VideoToolbox's software decoder: their size and luma). `sillclient.py` also prints `offConsole=1`.

## The review (2026-10-31) and what was done

1. **Off console the Desktop streamed this session's own desktop** (must fix): three readings; off
   console and at a locked screen the placeholder, no capture at all (`lockScreenStreams` the one switch
   for a locked screen's display, off). Proven on a test host: the pattern's frames stop at the gate,
   the placeholder's keyframe decodes to black.
2. **Off console a paired device's input was posted** (must fix): off console nobody's input but the up of
   what is held; a paired session's only at a locked screen; the injector's own last word. Proven: a
   paired session's taps posted at a locked screen, none off console, its held key's up let go.
3. **The device kept its last frame, no placeholder** (must fix): the client removes the picture at the
   list that says locked and covers the stream, worded for both cases, "Unlocking…" until the first
   keyframe after; the host's black keyframe replaces an older device's last picture too. Proven: the
   keyframe; the cover's words and states in the check; the cover drawn in the harness.
4. **The check required the Desktop to stream while locked; one state for two** (must fix): the check
   rewritten for the three readings from the real file: every witness combination, the notifications,
   the settle, the gate, each request at each reading, S13 inverted (the Desktop asked for off console
   streams the placeholder, never the display), and the random sessions found the coalesced case
   (`reconciles`).
5. **Noah's result came from main's build, and the blocked main actor was wrong** (should fix): said
   here, in the PR and in CLAUDE.md; no heartbeat gate.
6. **Notifications only prompted a WindowServer read; the CLI waited for its poll** (should fix): the
   notifications set the reading; notify(3) and the dynamic store are dispatch-queue witnesses the CLI
   has too. Proven: notify's lock 0.3 ms after the post, a delivered notification's at once.
7. **Lock notifications could be held while Sill.app was inactive** (should fix): `.deliverImmediately`;
   notify(3) as the screen's authority (it clears a lock notification whose unlock was lost). Only read:
   Sill.app's own registration needs Noah's test (step 4).
8. **A WindowServer round trip on the main actor per request** (should fix): no witness is read on the
   main actor; requests read the gate (a lock); the dictionary off main, bounded, only to confirm.
9. **The pointer and the cursor shape went on while locked** (should fix): withheld at the server, the
   pointer not read, the cursor watcher stopped. Proven: none of either while locked.
10. **The public words promised typing the password, and the lock screen off console** (should fix):
    support.html, the What's New and SECURITY.md say what is verified on a test host; the password waits
    for Noah's test. The support page's display-wake paragraph no longer says a locked Mac shows its lock
    screen, and the release checklist's line for the Locked Mac block says what the release shows.
11. **The compatibility floor froze host policy and misstated older devices** (should fix): its line says
    the fields, that a device says why, and that a host sends no picture of the Mac while locked (a
    placeholder frame at most).
12. **The unlock's re-pick should wait out macOS's own lock** (nit): the 2 s settle; no virtual display
    off console or locked. Proven: the flap never unlocked.
13. **DisplayWake declared activity off console** (nit): never off console; at a locked screen only a
    paired session's taken input.
14. **No hook showed a reading; one value for two states** (nit): SILL_TEST_LOCK_LOG, the file's 1 and 2,
    SILL_TEST_LOCK_NOTE (the review asked for a bare-binary hook; it is a variable of the core instead, so
    the CLI test host runs it: Noah's rules allow test hosts only as `SillHost --synthetic`), and
    SILL_TEST_LOCK_NOTIFY.

## Open questions, with the default taken

1. **A locked screen's picture.** The placeholder (`lockScreenStreams` false): nobody has seen what a
   display capture of a locked screen holds (build 1232 delivered 32 to 39 frames a second at 04:26:54,
   screen locked, content unknown). If Noah's test shows it is the lock screen alone, one constant
   streams it. Default taken.
2. **Typing the password from a device.** A paired session's input is posted at a locked screen; whether
   macOS's password field takes events Sill posts (it turns on secure input) was never tried. The
   device's cover says so to a paired session; the public words wait. Default taken: post it.
3. **Who types at a locked screen.** A paired session only; nobody off console. Default taken.
4. **The settle.** 2 s of every witness saying unlocked, and a session read since. Default taken.
5. **An unknown reading.** Off console (the most restrictive) until every witness has been read; a
   witness that cannot be read counts as locked for good, so a Mac whose dynamic store or notify(3) fail
   streams nothing. Default taken.
6. **A spurious lock notification** (another app posting `com.apple.screenIsLocked`): it holds the Mac
   locked until an unlock notification or notify(3) sees a full lock; a local denial of service, never a
   leak. Default taken.
7. **Gestures from a paired device while locked.** Refused. Default taken.
8. **The installed apps and the icons while locked.** Withheld, sent at the unlock. Default taken.
9. **The window at the unlock.** Picked again as a restart is (nothing comes forward). Default taken.
10. **A key held at a locked screen.** Not repeated. Default taken.
11. **Sill.app's own menu.** Shows nothing new (its card shows the stream as "Locked"). Default taken.

## Results

Proven on test hosts (`SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1
SILL_TEST_NO_SCREEN=1 .build/release/SillHost --synthetic`, the hooks above; never a real lock, never a
notification another app hears, never this Mac's screen, encoder or clipboard) and by the check:
- **The check** (`Tests/checks/lock-policy`, compiling LockPolicy.swift with StreamProtocol): 531 checks;
  137 of 137 mutants caught. The three readings and all 1,920 combinations of the witnesses, what
  each notification sets, the settle (the flap of a return to the console, 4,000 random witness sequences),
  when SessionLock reads, what each reading allows, what the gate withholds by kind and picture, each
  request at each reading paired and not, the list and its JSON both ways, the placeholder's size,
  `reconciles`, `Restore`, the hooks' words, the lines, `LockGate`, the device's words and cover (2,000
  random sessions of lists and frames), and a copy of the coordinator's glue through 15 directed scenarios
  and 5,000 random sessions: no window or display starts while the gate reads locked, a locked Mac settles
  on the placeholder, the remembered window comes back (202 came back, 3,155 sessions settled locked, 48,041
  steps after a refused pick).
- **Live** (`Scripts/lock-check/live.py OUT all`, on the final code: 58 of 58 verdicts):
  - *poll* (`SILL_TEST_LOCKED_FILE`, the plain door, two clients): each lock's line at the next look,
    0.16 to 0.19 s after the write (the screen locked, off console, locked again); the unlock 2.20 s after
    its write and the last one 2.19 s (the settle); the flap (off console, unlocked 1.2 s, locked again)
    never unlocked. The test pattern's frames stopped at the lock: 42 in the 3 s before its line, the last
    25 ms before the line was read, none large after it until the unlock (4 frames in all, 1,530 bytes: the
    placeholder's), 41 in the 3 s after the last unlock. Every keyframe while locked decoded to 1280×800 with
    a luma mean of 0.0 and a maximum of 0 (the pattern's: a mean of 105). The list said locked at once, off
    console `offConsole`, back on the console locked without it, after the unlock neither; no list while
    locked had a window. While locked the first client got no thumbnail, icon, app list, cursor shape,
    pointer, clipboard or sound (before the lock it had 393 sound messages and 40 pointer reports; after it,
    698 sound messages). A second client that connected off console got the black keyframe, a first list
    saying off console, nothing of the Mac until the unlock, then its icons and apps (123 messages). Refused
    while locked, each with its line: a window pick, an app launch, a gesture, a device's clipboard text, the
    plain door's input (nothing posted); after the unlock its tap posted, its text written, a gesture taken.
    The server's gate withheld 2 messages in all: at each of the two locks that found the pattern streaming,
    the one frame of it encoded after the gate locked and before the main actor switched to the placeholder.
  - *start* (a host started with the file holding 1): its first line "Locked: this Mac's screen is locked"
    0.04 s after start, the first list locked (not another user), the unlock 2.07 s after the write, black
    keyframes before it and the pattern after.
  - *notify* (`SILL_TEST_LOCK_NOTIFY`, `SILL_TEST_LOCK_NOTE`): the lock 0.4 ms after notify_post (no poll),
    its unlock 2.006 s after; a delivered sessionDidResignActive off console at once (0.015 ms after its
    line), sessionDidBecomeActive's unlock 2.06 s after; the pattern's last frame 44 and 38 ms before each
    line, no large frame in the 2 s after either.
  - *paired* (`--pairing`, Require pairing off for the run, a paired and an unpaired client): at a locked
    screen the paired session's taps posted (4 button events); its key held down across the switch away let
    go off console (the down posted, the up let go); off console none of its taps posted, after the unlock
    again; the unpaired session's taps dropped; kind 16's `sessionPaired` 1 and 0.
- **H2**, the CLI against main (e4d30349, built from `git archive`), this head built clean the same way, one
  synthetic host at a time on loopback: idle 35 s, identical masked and sorted in the first round (8 lines);
  in the second identical but for the idle heartbeat's second line, which its 5 s leeway put inside this
  build's 35 s and just after main's; idle 45 s (both heartbeat lines inside), identical (9 lines). With a
  test client on the Desktop for 20 s (subscribed to the menus and the clipboard): identical masked and sorted
  in the first round (36 lines); in the second identical but one `[1s]` line in which main's encoder dropped
  nothing (`enc.mailboxDrop` absent); the clients' outputs identical masked but the order in which the kinds
  first arrived.
- **Builds**: `swift build -c release` from a clean `git archive` of d569359f: only the CaptureProbe
  warning. The iOS app from the same copy, each with fresh derived data (Xcode 27.1, unsigned, arm64): Debug and
  Release for the simulator and Debug for a device, only the known `StreamClient` capture warning
  (StreamClient.swift:4257). `Tests/checks/run-all.sh`: all 63 passed.
- **Photos** on a private iPad mini simulator (created and deleted): the cover live against a test host
  switched to another user, then locked, then settling and unlocked, and the harness's mock in both readings,
  "Unlocking…", the drawer's and the Settings panel's line (sill-handoff's `locked-mac/`, INDEX.md).

Only read, not run: Sill.app's notification observers (`watchNotifications`, `.deliverImmediately`) and
their delivery while it is inactive; SCDynamicStore's and notify(3)'s values through a real lock and a
real fast user switch (the review's logs give them); a display capture of a locked screen (not made by
default); macOS's password field taking posted keys; the device's cover on a device; the icons that raced
the lock sent at the unlock (`onCatalogWithheld`: that race was not staged live).

## Untested, for Noah

With Sill.app built from this branch (release-signed with the profile, as every test build) and this
iPad build; Sill.log has a "Locked:" line at each lock or switch, "Unlocked:" about 2 s after each
unlock:

1. **The lock with a window streaming** (Virtual Display on, then off): lock the Mac (⌃⌘Q). The iPad
   shows "‹Mac› is locked" over a black picture at once, the thumbnails and the Apps list go; with
   Virtual Display on, the window is back on the Mac's display and no "Sill" display remains.
2. **The password from the iPad** (a paired iPad): with the cover up, type the Mac's password on the
   Magic Keyboard or the on-screen keyboard and press Return. If the Mac unlocks: "Unlocked:", then
   "Unlocking…" briefly and the window back by itself. If nothing types, note it (and which keyboard):
   macOS's secure input may refuse posted keys, and the cover's words change then.
3. **Another user at the login screen** (fast user switching): "‹Mac› is switched to another user" on the
   iPad, a black picture, nothing of your session, no app opens from the Apps button (there is no list),
   taps and keys do nothing; Sill.log "Locked: another user…". Switch back and log in: macOS locks again
   about a second later (its own), and the cover stays "locked" until you unlock; then your windows.
4. **Inactive Sill.app**: open Sill's Settings, click another app, lock, unlock: "Locked:" and
   "Unlocked:" at once (the notifications are delivered while Sill is not active).
5. **An unpaired device at a locked Mac** (Require pairing off in Settings › Devices): it sees the cover,
   its taps and keys do nothing ("Locked: dropped …"). Turn Require pairing back on.
6. **The rest while locked**: no Menus button, a three-finger swipe does nothing, no Paste offered, no
   sound, the Mac's pointer not drawn; all back after the unlock.
7. **Mixed builds**: the App Store iPad (0.5.x) against this Sill.app while locked: a black picture (the
   placeholder), an empty bar and drawer, no words; this iPad against Sill for Mac 0.5.1: as before.
