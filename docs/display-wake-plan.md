# Wake the Mac's display for a device — the plan

## Status (2026-10-17)

Built on the branch `display-wake` from main at 5c323e6, for issue #134 ("Sill doesn't wake display
(Black windows)"), asked for again in the r/opensource thread and in #61 and #132. Host only; the
wire, the device and the settings are unchanged.

## The problem

With the Mac's display asleep (Energy Saver's display sleep, or the lock screen's own dimming),
ScreenCaptureKit gives the capture nothing new, so a device that connects sees black windows. Once
the display wakes some other way the picture comes back within a second, and a locked Mac's lock
screen streams and takes the password (#134, scottschram). The workaround in the issue is an iOS
Shortcut that runs `caffeinate -u -t 2` over SSH.

## The rule

`caffeinate -u` declares the user active: IOPMAssertionDeclareUserActivity, which "causes the
display to power on and postpone display sleep, up to the user's display sleep Energy Saver
settings" and needs no privilege (IOPMLib.h). Sill makes the same declaration:

- **A device connects**: declare, always. That is the wake.
- **A device's input, gesture or pick**: declare at most once every 10 s (`DisplayWakePolicy.interval`),
  so the display stays on while someone works from the device, as it would under a local user's
  keys, and sleeps by the Mac's own setting once they stop. A pointer's moves, many a second, must
  not each make the IPC call.
- **The last device leaves**: release the assertion; the next connect starts afresh.
- **A synthetic host** counts (`wake.connected`, `wake.activity` in the stats line) and declares nothing.

`kIOPMUserActiveLocal`, as `caffeinate -u` uses, not `kIOPMUserActiveRemote`: the issue's workaround
proves Local lights the panel, and whether Remote keeps the framebuffer capturable with the panel
dark is unmeasured (open question 2).

## Files

- `Sources/SillHost/DisplayWakePolicy.swift`: the rule, pure (Foundation), `Tests/checks/display-wake`.
- `Sources/SillHost/DisplayWake.swift`: the IOKit calls on a queue of their own (they may block on
  IPC), the assertion ID kept and passed back as IOPMLib.h asks; one line "Display: awake for a
  device." per connect, one if the call fails.
- `StreamCoordinator`: `note(.connected)` in `onClientConnected`, `note(.activity)` for kinds
  `input`, `gesture` and `selectSource`, `allLeft()` when the client count reaches 0.

## Results

- `Tests/checks/display-wake`: 19 checks, the last a model against 20,000 random runs; 9 of 9 mutants.
- `swift build` and `swift build -c release`.
- On this Mac (macOS 27): the call returns success and `pmset -g assertions` lists
  `UserIsActive named: "Sill: a device is using this Mac"`, the same assertion type WindowServer
  takes for a key on the built-in keyboard.

**Untested, for Noah:** with the display asleep (`pmset displaysleepnow`), connect from the iPhone or
iPad at home and through Remote Access: the display wakes and the window streams; locked, the lock
screen streams and the password typed from the device unlocks (#134's cthulu reports the password
rejected: a separate issue in the key path, not this change); idle on the device, the display sleeps
after the Mac's display-sleep time and a tap wakes it.

## Open questions (the default taken)

1. A setting to turn it off? Default: none. A paired device is already trusted to click and type;
   lighting the display is less than that. A Privacy Mode (#133) would be its own change.
2. `kIOPMUserActiveRemote` with a blanked panel (#133, #141) needs a measurement first.
3. Full system sleep is out of scope: a sleeping Mac answers no connection. Wake on LAN from the
   device (a magic packet on the home network) would be a later change.
