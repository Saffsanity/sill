# A locked Mac shows its lock screen: the plan

Branch `locked-mac` from main at e4d30349. Noah's finding of 2026-10-31, a security fix: no public
issue.

## The finding

Sill.app asks whether this Mac's console is unlocked (`Sources/SillHost/SessionLock.swift`:
`CGSessionCopyCurrentDictionary`'s `kCGSSessionOnConsoleKey` and `CGSSessionScreenIsLocked`, and in
Sill.app the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications; TEST ONLY
`SILL_TEST_LOCKED=1` on a test host) for two things only: the pairing ask rule (`DoorPolicy.ask`'s
step 1) and the cable's automatic pairing. Everything else ignores the lock. With the screen locked,
or with another user selected at the login screen while Noah's session runs in the background, a
paired device (and, at a door that lets any device in, an unpaired one) can still:

- pick a window and see its content: window capture (`SCContentFilter(desktopIndependentWindow:)`)
  draws the window whatever covers it, and the virtual display's app filter
  (`SCContentFilter(display:including:)`) leaves the lock screen, which is on the main display, out;
- see every window's thumbnail (the catalog's poll takes them every 2 to 6 s while a device is
  connected), the icons of the running apps and the installed apps;
- launch apps from the Apps drawer (Noah saw these, with another user selected at the login screen),
  press a window's traffic lights, read the streamed app's menus and choose items in them (Open
  Recent lists file names), post trackpad gestures, and read and write the clipboard;
- hear the Mac's sound;
- type, an unpaired device too, which at a locked Mac types into its password field.

Expected: what Screen Sharing does. A locked Mac shows its lock screen and nothing else until it is
unlocked, and only its owner types at it: here, a paired device.

## The rule

`LockPolicy` (pure; `Sources/SillHost/LockPolicy.swift`, checked by `Tests/checks/lock-policy` with
mutants, in CI's matrix). "Locked" is SessionLock's reading: the screen locked, another user's
session on the console, or no console session at all.

While locked:

| What | Becomes |
|---|---|
| The window list (kind 2) | no windows, `locked: true` (new, optional), no `clipboard` |
| A window picked (kind 6) | refused; the Desktop picked, or nothing, as ever |
| What streams | the Desktop alone: it shows the lock screen, or the login window |
| Thumbnails (kind 3) | none taken, none sent |
| Icons and the installed apps (kinds 4, 5) | none sent; sent again at the unlock |
| An app launched (kind 7) | refused |
| A window's traffic lights (kind 15) | refused |
| The menus' subscription (kind 27 without an id) | kept, answered with an empty top level (no app) |
| A menu fetched or chosen (kind 27 with an id, 25) | refused: "The Mac is locked.", nothing read or pressed |
| A gesture (kind 28) | refused, for every session |
| The clipboard (kind 32) | paused both ways: nothing read or written, a device's text dropped, its subscription kept |
| The Mac's sound (kind 43) | not captured |
| Input (kind 8) | taken from a paired session; from any other only the up of a key or a button it holds down |
| Settings (17), the viewport (9), a keyframe (44), Pair This iPad… (21), pings, stats, the hello | as ever (the ask answers "locked" by itself) |
| The Mac's pointer (26) and cursor shape (14), kind 16, kind 18 | as ever |

Paired: the session's key, proved in its TLS handshake, is on the Mac's trust list as the status
snapshot lists it now (`sessionPaired`, PR #253's): every remote session, every session at a TLS
home door that requires pairing; never the CLI's plain door, nor an unpaired key at a door that lets
any device in (Require pairing off).

Unlocked, everything is as it was: no field in the window list, no line, no request treated
otherwise. A host from before this change sends no `locked`; a device from before it shows an empty
list.

### The transition

- **The lock** (`LockPolicy.State.read`): one line, "Locked: this Mac's screen is locked; devices
  see the lock screen until it is unlocked.", then at once the window list without windows (with
  `locked`), the menus without an app, no sound, the clipboard's look stopped, a held key's repeat
  stopped, a launch asked for before the lock forgotten. A window that streams is sent home
  (WindowRestore's way in regular mode, the stage's on the virtual display, which goes) and the
  stream switches to the Desktop; the window is remembered.
- **While locked** any select of a window becomes the Desktop (`LockPolicy.State.select`): a
  restart of the window that streamed (a settings change, a resize, the encoder's fallback), a
  launched app's first window, a switch that was under way as the lock came; each is remembered as
  the window to come back. A device's own pick of a window is refused before that and remembered
  by nothing.
- **The unlock**: one line, "Unlocked: this Mac's screen is unlocked; devices see its windows
  again.", the clipboard's look again (what was copied while locked is never sent: the count is
  taken as seen), the menus' app and the sound as the source says, the catalog looked at afresh,
  then the installed apps, the icons and the window list, every thumbnail sent again, and the
  remembered window picked again (`afterUnlock`) if it is still listed, the Desktop still streams
  and a device is still connected. A pick made after the unlock forgets it, and so does the last
  device leaving.
- **Reading the lock**: once a second while a device is connected (the poll; nothing while none
  is), at a device's connection before its catalog goes, and afresh before each of the rare
  requests above (a pick, a launch, a window's buttons, a menu, a gesture, the clipboard's text) and
  each select; in Sill.app also at once on the lock and unlock notifications and on a fast user
  switch (NSWorkspace's session notifications), while a device is connected. Input uses the last
  reading, so the CLI may take an unpaired device's input for up to a second after a lock (Sill.app
  hears the lock at once), and drop it for up to a second after an unlock.
- **Refusals**: one line per kind a minute at most (`RefusalSummary`): "Locked: refused a window
  pick; devices see only the lock screen until this Mac is unlocked.", with the count when there
  were more ("… refused 3 window picks …"). Stats: `lock.refused`, and `in.locked` for input.

### TEST ONLY

`SILL_TEST_LOCKED_FILE=<path>`, honoured only by a test host (one that does not advertise and is not
Sill.app's own code, as `SILL_TEST_LOCKED`; TestHooks lists it, and anywhere else it is ignored with
one line): read at each reading, "1" says locked; "0", another text or no file says nothing, and the
session's own witness decides. So a live test flips it mid-stream. A test host that has it set says
so at start ("Test lock: …"). `SILL_TEST_LOCKED=1` stays as it was: locked for the run.

## Device

`WindowList.locked` true (`StreamClient.macLocked`, cleared with the session): one line where the
windows would be, `LockedMac.line(mac:)` (StreamProtocol, beside `WindowList`, checked with the
host's rule): "‹Mac› is locked. Unlock it to see its windows.", in the Apps drawer (in place of its
search field and both lists) and in the Settings panel's header (under the readout). VoiceOver reads
it where it is. A refused pick is quiet: the list is empty anyway. Nothing else changes on the
device; with no `clipboard` in the list it offers no Paste (as with Share clipboard off on the Mac),
and with an empty top level no Menus button. DEBUG `-SillMacLocked 1` draws the mock locked.

## Open questions, with the default taken

1. **The Desktop while locked.** It streams: it shows the lock screen (or, with another user
   selected, the login window), which is what Screen Sharing shows, and it is where the owner types
   the password. Default taken.
2. **Who types at a locked Mac.** A paired session only, so the owner can unlock it and a stranger at
   an open door cannot try passwords; an unpaired device's key or button already down still comes
   up. The CLI's plain door has no pairing at all, so nobody types at a locked Mac through it.
   Default taken.
3. **Gestures from a paired device while locked.** Refused (Mission Control and the Spaces at a lock
   screen help nobody). Default taken.
4. **The installed apps and the icons while locked.** Withheld (they say what is installed and what
   runs) and sent again at the unlock. Default taken.
5. **The clipboard's word in the list while locked.** No `clipboard` while locked, as when Share
   clipboard with devices is off on the Mac: a device then offers no Paste, whose receipt would
   otherwise say "Sent to ‹Mac›’s clipboard" for a text the locked Mac dropped. The Mac keeps the
   subscriptions; at the unlock each device subscribes again, which the Mac already has (no line).
   Default taken.
6. **The menus while locked.** No app (an empty top level: no Menus button on the device); a fetch
   or a choice answered "The Mac is locked." Default taken.
7. **The window at the unlock.** Picked again as a restart is (nothing comes forward on the Mac): the
   lock leaves the windows' order alone, and the person may have unlocked the Mac at the Mac. A
   device's next click raises it, as ever. The alternative, bringing it forward as a pick does, is
   one argument. Default taken.
8. **A pick between the unlock and the window's return.** The pick wins, and the window that
   streamed at the lock does not come back. Default taken.
9. **The bar's thumbnail strip while locked.** Empty, with no line of its own (the drawer and the
   panel have it). Default taken.
10. **The sound while locked.** Not captured, the Desktop's either (it is the whole Mac's). Default
    taken.
11. **No console session** (a host run over SSH, with nobody at the Mac, or the login window after a
    log out) reads as locked: the Desktop shows the login window or nothing. SillHost does not
    capture from outside a GUI session anyway. Default taken.
12. **Refused messages and the display.** A message the lock refuses wakes nothing (DisplayWake never
    hears of it), so a stranger's dropped input does not keep a locked Mac's display awake; a
    session's start still wakes it, so the device sees the lock screen. Default taken.
13. **Sill.app's own menu.** Shows nothing new: nobody reads it at a locked Mac. Default taken.

## Test plan

- `Tests/checks/lock-policy`: the table both ways, each request locked and unlocked, paired and
  not; the list (windows, `clipboard`, `locked`) and its JSON (left out unlocked, true locked, an
  older reader skips it); `shown`; the test file's words; the State's transitions; the lines; the
  device's line; a model of the coordinator's glue (the select gate, the switch to the Desktop and
  the return, races with a switch under way, picks between the unlock and the return, devices
  leaving), random sessions against the invariants (no window streams while locked once settled; the
  window that streamed at the lock returns after an unlock unless something else was picked or
  nobody is left; a pick made while locked never streams); mutants, every one caught.
- `Tests/checks/run-all.sh`, `swift build -c release`, the iOS app Debug and Release for the
  simulator and Debug for a device.
- H2: the CLI's output idle 35 s against origin/main's, both from `git archive`, masked and sorted:
  identical (nothing new prints while unlocked); and with a test client on the Desktop.
- Live on loopback synthetic hosts (software encoder, no router, no screen): `SILL_TEST_LOCKED=1`:
  the list empty and locked, a window picked refused, the menus answered empty and a fetch refused,
  a copy dropped, a gesture refused, input dropped at the plain door and taken from a paired
  session at `--pairing`'s door; `SILL_TEST_LOCKED_FILE` flipped mid-stream: the lines, the list
  going and coming back, the stream staying on the Desktop.
- A private iPad simulator against a locked test host: the drawer's and the panel's line.

## Results

(Filled in as it was verified.)

## Untested, for Noah

(Filled in at the end.)
