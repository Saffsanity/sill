# duorig — TEST ONLY

Folds and turns an iPhone Duo in the iOS Simulator from the command line, the way Xcode 27.1's Device
Hub does with its hinge slider and orientation picker, so the Duo's six poses can be driven and
photographed with no hand on Device Hub. `xcrun simctl` has no hinge or orientation command, and
`xcrun devicectl device orientation set` answers but changes nothing on a Duo simulator (its
orientation follows CoreMotion, below). docs/iphone-duo-plan.md, Facts, has what each pose looks like
to an app.

**Private interfaces, simulator only.** `duorig.m` uses HID.framework's `HIDVirtualEventService` and
IOKit's `IOHIDEvent` calls through `dlopen`/`dlsym`, and posts into the HID event system of the
simulator it runs in (the simulated backboardd's `com.apple.iohideventsystem`). It is never part of
Sill, never built for a device, and refuses to run outside a simulator. Nothing reaches the Mac's own
HID system: it runs inside the simulator through `xcrun simctl spawn`, a binary for the simulator
platform that macOS's dyld will not start on its own ("DYLD_ROOT_PATH not set for simulator
program").

```
Tests/duorig/run.sh build                     # .build/duorig/duorig (clang for the simulator)
Tests/duorig/run.sh UDID pose book            # closed-upright | closed-side | flat-portrait | flat-landscape | laptop | book
Tests/duorig/run.sh UDID shot book out.png    # the display that pose shows: the cover when closed, else the inner
Tests/duorig/run.sh UDID hinge 90             # 0 closed, 90 half-folded, 180 flat
Tests/duorig/run.sh UDID orient landscape-left    # portrait | pud | landscape-left | landscape-right | faceup | facedown
Tests/duorig/run.sh UDID services             # read-only: the simulator's HID services
Tests/duorig/run.sh UDID watch 10             # read-only: every HID event for 10 s (the hinge shows as type 44)
```

`run.sh` takes only a booted simulator of the iPhone Duo device type, by UDID (never a device, never
another simulator), and runs duorig from that simulator's own `data/tmp` (a process in the simulator
cannot open a file under `~/Downloads`, where this repository lives: the open blocks in dyld).

| pose | hinge | orientation | what an app gets |
|---|---|---|---|
| closed-upright | 0 | portrait | the cover display, 466×678 pt, compact/regular |
| closed-side | 0 | landscape-left | the cover display, 678×466 pt, compact/compact |
| flat-portrait | 180 | landscape-left | the inner display, 669×951 pt, regular/regular, the fold inactive |
| flat-landscape | 180 | portrait | the inner display, 951×669 pt, regular/regular, the fold inactive |
| laptop | 90 | landscape-left | the inner display, 669×951 pt, the fold active across it at y 455.5–495.5 |
| book | 90 | portrait | the inner display, 951×669 pt, the fold active down it at x 455.5–495.5 |

## What it sends

Read from Xcode 27.1 (27A9275)'s `SharedFrameworks/DeviceKit.framework/…/CoreDevicePopDeviceKitExtension`
(Device Hub's device view): one vendor-defined HID event,
`HIDVendorDefined.send(usagePage: 0xFF61, usage: 0x5B, version: 0, data:)` (CoreDevice), the data
`IOCFSerialize(dictionary, kIOCFSerializeToBinary)` of

- hinge: `provider` "com.apple.Virtualization.VirtualMachines", `source` "hinge-slider-control",
  `type` "range", `value` the angle in degrees as a Double, clamped to 0…180;
- orientation: the same `provider`, `source` "orientation-picker-control", `type` "enum", `value`
  "portrait", "pud", "landscape-left", "landscape-right", "faceup" or "facedown".

CoreDevice hands it to the simulator's `dtuhidd`, which dispatches it from a virtual HID service.
duorig makes its own virtual service with the same usage pair (0xFF61/0x5B) and dispatches the same
event from it; the simulator's CoreMotion (its `CoreMotion_DeviceStateRelay_*` services) turns the
hinge into a HingeAngle event (IOHIDEvent type 44: angle, mechanical angle, state Open or Closed)
and the orientation into a MagicPose, and SpringBoard moves the app between the displays and rotates
it. The simulator keeps the last angle and orientation after duorig exits.

Entitlements: the simulator reads a process's entitlements from its `__TEXT,__entitlements` section
(`duorig.entitlements`, linked in with `-sectcreate`); the code signature is ad hoc and carries none
(launchd_sim refuses to spawn an ad hoc binary whose signature claims private entitlements: "Security
policy issue").

## Gotchas

- Jump, don't creep: from closed, a jump to 90 or 180 opens the device, but a jump to 30 stays
  closed, and steps of 5–15° every few seconds stayed "closed" up to about 165°. Closing from open
  goes "closed" at about 14° and below.
- Close only with an app in front. Closing over the Home Screen puts the simulated device to sleep:
  the cover display goes dark and screenshots repeat its last frame. Opening (hinge 90 or 180) wakes it.
- The angle the app reads is quantised (90 reads 90.0, 120 reads 118.3, 150 reads 146.7, 179 reads
  174.1), and `onHingeChange` repeats the same value several times as it settles.
- Screenshots follow the interface orientation: the inner display is 2853×2007 px sideways and
  2007×2853 upright, the cover 1398×2034 upright and 2034×1398 on its side (App Store Connect's
  iPhone Duo sizes).
