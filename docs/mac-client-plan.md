# Sill Viewer: a Mac controlling another Mac

Goal (2026-10-11): a Mac app that connects to another Mac's Sill (Sill.app or `SillHost`), shows
its windows with the same low-latency HEVC stream and sends mouse, keyboard and trackpad input back;
Apple frameworks only, no servers, the iOS app's session code reused rather than copied, and the
host kept compatible with every existing device. Then, from tests between two Macs: each host
window a window of its own here (closable, minimizable, live), the remote app's menus in this Mac's
menu bar and Sill's own controls in a menu bar icon, the clipboard both ways, the sound of the
shown apps here instead of there, files dropped in and dragged out, full screen that fills the
viewer window, and the host's windows kept on hidden displays while they are shown.

## What a person sees

- **Sill Viewer** (`Sources/MacClient`, product `SillClient`, `.build/Sill Viewer.app`, bundle
  `me.saffer.sill.client`): a menu bar icon (connect, the other Mac's windows and apps, Desktop,
  gestures, Capture System Shortcuts, Share Clipboard, Play Sound, the host's quality settings,
  Disconnect). Each host window opened from it is a borderless window here at 1:1, with a small
  pill above it for this Mac's close, minimize and full screen, and a drag on the picture's top
  strip moving the window. The focused window streams at full rate; every other open window
  streams too, at 15 fps (side streams). New windows of an app already open here open by
  themselves; the windows open last time come back after a restart. The menu bar shows the remote
  app's menus (read when they open, chosen on the host). A Dock icon per remote app
  (`SillDockProxy`, an ad hoc signed copy per app, talking over distributed notifications) groups
  its windows: its icon is the remote app's with Sill Viewer's in the corner, its Dock menu lists
  the windows open here (✓ the front one, ◆ a minimized one), and kept in the Dock it opens that
  app's windows from the other Mac again when clicked (Sill Viewer opened if need be, the app
  launched there when it has none).
- **On the host** nothing new to set up: the same pairing and trust list as an iPhone (Settings ›
  Devices). While a viewer shows a window, that window lives on a hidden virtual display of its own
  ("Sill's desk"), so it is never covered, never limited by the host's own screens, and the person
  at the host keeps their desk. Windows go back where they were when the viewer closes them,
  disconnects or quits, and when Sill quits.

## The wire (all additive; StreamMessage.swift, SideStreams.swift)

| Kind | Direction | What | Sent only when |
|---|---|---|---|
| 8 (`PointerAction.middleDown/Up`) | device → host | the middle button | the host's list says `middleButton` |
| 29 `sideStreams` | device → host | `SideStreamRequest`: the other windows shown, `wholeApp`, the device's largest screen, `audio` | the list says `sideStreams` |
| 30, 31 | host → device | a side window's parameter sets and frames, prefixed by its window ID | asked by 29 |
| 32 `clipboard` | both | `Clipboard`: text and image (PNG or JPEG) | the list says `clipboard`; the host sends only to a device that asked |
| 33 `audio` | host → device | `AudioPacket`: ~10 ms of 16-bit PCM | `audio: true` in 29 and the list says `audio` |
| 34 `fileChunk` | both | `FileChunk`: a part of a file (≤ 512 KB) | the list says `fileDrop` |
| 35 `fileDrop` | device → host | `FileDrop`: drop those files at a point; or, with `offer`, the host's own files from a drag offer; `window` names the target | the list says `fileDrop` |
| 36 `dragOffer` | host → device | `DragOffer`: files an app is dragging under that device's held button | the device holds the button over the stream |
| 37 `fileRequest` | device → host | `FileRequest`: one offered file, back as kind 34; `trash` moves it to the host's Trash instead | the offer was made to that device |
| 38 `liveDrag` | device → host | `LiveDrag`: a drag of files over the host's windows, followed as it goes (`start`, `files`, `move`, `drop`, `cancel`; the window, the point, the modifier keys) | the list says `liveDrag` |

Every field added to an existing payload is optional, and a host or device from before skips the
new kinds (the compatibility floor in CLAUDE.md). The iOS app sends none of them. Checks:
`protocol` (round-trips and refusals of every new payload, 221 checks, 28 mutants), `compatibility`,
`menus` and `pointer-control` know kinds 29–38.

## Sill's desk (DeskStages, VirtualStage)

- **One hidden display per window**, each with its own display identity, taken as needed (product
  0x100 + slot, a serial kept per slot in the defaults, so macOS remembers how to show each:
  "Extended Display"). Two displays with the same vendor and product ID are one monitor to macOS,
  which takes the older offline when the newer comes; that, measured with a probe, is why the first
  per-window attempt sent windows home, and why the branch went through a shared-display phase that
  is gone now. With distinct identities three displays stayed online together.
- **Sized once**, at 120 Hz, to the viewer's largest screen (`SideStreamRequest.screen`) plus room
  for the menu bar, so resizing the window or changing the rate never makes the display again (each
  new display moves the window home and back). 2× (Retina) up to 3792×2160 points; a window larger
  than that (one stretched across an ultrawide) gets a 1× display up to 7616 pixels, and goes back to
  2× when it is 5 % under the limit. macOS 27.0.1 makes no mode for 7680 pixels or more at either
  scale.
- **Capture**: the focused window is the display cropped to the window with its own app and the
  system's processes (`AppCrop.filter`), so its menus, popovers, sheets and the system's share
  pill and its menu show, and no other app's window; `SharePill` runs a 1 fps window capture beside
  it so macOS draws the pill. Background windows are captured alone.
- **Full screen**: a window that goes full screen takes only its own display. While it is full
  screen its display is resized live (`VirtualDisplay.resize`, the same display) to the viewer
  window's size, so the full-screen Space fills that window and nothing more; the change is seen
  within 0.25 s. Leaving the desk takes a window out of full screen first (a full-screen Space would
  outlive its display on another one, out of sight).
- Windows in other Spaces (another desktop, a full-screen Space) are listed too, so a device can
  reach every titled window an app has.

## Sound (AppAudio, AudioPlayer)

A CoreAudio process tap (macOS 14.2+) over every process of the apps whose windows the viewer
shows, their helpers included (browsers and web-based apps play from a helper, matched by bundle ID
prefix), `mutedWhenTapped`: silent on the host, played here. Read through a private aggregate
device, sent as AAC-ELD (about 96 kbit/s at 48 kHz stereo, some 15 ms more delay than plain PCM's
1.5 Mbit/s; `SillClient.plainAudio` asks for PCM, and a host that cannot encode sends it). The viewer buffers 40 ms before it starts and cuts back to 60 ms past 150 ms. All
CoreAudio work runs off the main actor: its calls wait on coreaudiod and on the audio recording
permission's prompt (`NSAudioCaptureUsageDescription`), which once froze the host. The tap runs only
while a tapped app makes sound.

## Files (FileDrops, DragOut; the viewer's StreamInputView, StreamWindows, FilePromises)

- **Followed live** (kind 38, `LiveDrags` and `LiveDrop`): a drag over any Sill window is a real
  drag on the host as it goes, so the app under the pointer highlights where it would land (a
  folder, a page's drop zone, the address bar) and this Mac's ⌘ ⌥ ⇧ ⌃ are pressed there as held
  (Finder moves, ⌥ copies, ⌥⌘ makes an alias). Older hosts get kind 35 at the drop instead.
- **In**: files dragged from this Mac over a Sill window are sent at once, saved on the host in
  `~/Downloads/From <device>/`, and the host starts its own drag of them under the pointer: a panel
  of Sill's own takes a posted press, a drag session starts from it with the files, and the device's
  moves follow it until it is let go. Dragged away (0.35 s over no Sill window), the drag is given up
  and the copies removed. An app that only refers to a file (a chat attachment) keeps the copy's path.
- **Out**: while a device holds the button over the stream, the host watches its drag pasteboard;
  an app dragging files (Finder, a mail app) makes an offer (kind 36) to that device. When the drag
  leaves the window (the window under the pointer is another), the viewer presses Esc on the host
  (cancelling its drag), lets the button up, and drags `NSFilePromiseProvider`s here; a drop fetches
  each file (kind 37). Dropped on this Mac's Trash, the files go to the host's Trash instead.
  With the live drag, the host's own drag is never cancelled while the drag is over a Sill window:
  its button stays held and its pointer follows onto whichever window the drag is over (each on its
  own display), so a drop there is the host's own, nothing copied; only a drag that ends elsewhere
  gives it up.
- Folders go as one zip (`FolderZip`: Finder's own `ditto` archive, resource forks, attributes and
  links kept) and are unpacked where they land, a drop on the Trash included.
- Offers are scoped to the device they were made to; parts are taken only from the device that
  started the file; both are forgotten when that device leaves.

## Security notes

Everything is inside the paired, TLS session; nothing new listens. A device can already see and
control the host; what is new is that it can write files into `~/Downloads/From <device>/` (names
cleaned of `/` and `:`, 512 MB a drop), read files an app on the host is dragging under its own
pointer, and hear the apps it shows. `SillDockProxy` talks to the viewer over distributed
notifications, which any local process as the same user can post: at worst it focuses or closes a
proxy icon.

## Build and run

```
Scripts/make-client-app.sh [--debug] [--open] [--notarize]   # .build/Sill Viewer.app
```

Release builds are Developer ID signed and, with `--notarize`, notarized (profile `sill-notary`);
the viewer's device key stays in the login keychain across rebuilds. DEBUG launch arguments: from the
shared client `-SillConnect host:port`, `-SillHomeDoor paired|plain`, `-SillPairURL`; the viewer's
own `-SillInputTest 1` (synthetic events to a test host only), `-SillMenuTest 1|press`,
`-SillOpenWindows N`, `-SillFlipTest 1` (focus between open windows every 3 s),
`-SillResizeTest 1` (four window shapes, picture fit checked), `-SillDropTest <path>` (that file
dropped on the focused window), `-SillKeyLog 1`. The iPhone build from Xcode 27.0 takes
`OTHER_SWIFT_FLAGS=-D SILL_NO_DUO_SDK` (the 27.1 hinge API left out).

## Shared code

`Sources/MacClient/Shared/` symlinks iOSClient's session code (StreamClient and its extensions,
DiscoveryPolicy, SessionLink, MessageReader, RemoteConnector, RemoteDialPolicy, SavedMacs,
DeviceIdentity, GoodbyePolicy, HostSettingsLedger, KeyChords, PointerPresence, MacMenuState,
TrackpadGestures, TourPolicy, PhonePortraitLayout, DuoPosture, AwayCopy, SillLinks, DiagnosticsHUD):
one source of truth, compiled by SwiftPM for macOS and by Xcode for iOS, the pure checks' paths
unchanged. Two files are new and shared by both apps: `ClientPlatform.swift` (the few platform calls
the session makes) and `HEVCSampleFeed.swift` (the decoding half of the old HEVCDisplayView). The
iOS-only DEBUG hooks are behind `#if canImport(UIKit)`. Verified: an iPhone 16 Pro Max session (53–57
fps, rtt 7–8 ms) with the shared code; the iOS app's only build errors on Xcode 27.0 are main's, in
the 27.1-only DuoPostureReader.

## Verified (2026-10-12; host this Mac, viewer a MacBook Pro over the LAN)

- Pairing, a pinned reconnect, every input kind as the right host event (`-SillInputTest`, the
  host's input log), real hands: clicks, right and middle clicks, drags, hover, scrolling, typing,
  ⌘W, ⌘Tab through Capture System Shortcuts, ⌃⌥⌘⎋.
- Several windows live at once; switching between three windows on their own displays in about
  0.25 s with no display made again (`-SillFlipTest`); picture fit at four window shapes
  (`-SillResizeTest`); 2× and 1× by window size, by hand.
- Sound: coreaudiod's log "muted by Sill … for all devices" for a browser, a chat app and its helper;
  ~100 packets a second, none dropped; played on the laptop ("sounds great").
- Files: a drop from the laptop arrived whole and was dropped into the app under it; a drag out to
  the laptop's Trash moved the host's file to its Trash, by hand. The live drag (16:50–16:51): five
  drags of the host's own files between Sill windows each landed where let go, the target
  highlighting as for a drag on the host, the file referenced at its own path; one carried out to the
  laptop was given up on the host and sent across; two of the laptop's files dropped on the remote
  chat app's window arrived and were taken. Two Finder windows of one size keep their own pictures.
- Both apps notarized ("Notarized Developer ID"). `Tests/checks/run-all.sh`, all passing.

## Open (by hand, or not done)

- The desk takes windows while their displays fit in a quarter of the host's memory (each display a
  framebuffer of its own, up to about 130 MB); side streams stay at 6 live windows beside the focused
  one.
- The stuck right button: the viewer now sends an up its stream view would miss (the view moved to
  another window under a held button, the likeliest path) and the host lets go of a button still
  held at a new press; not seen since, not reproduced on purpose.
- A full-screen window stranded in a Space of its own after a restart is reached by bringing its app
  forward: by hand.
- The remote Dock menu flashes in the host's Dock for about half a second each time it is read.
- Away from home over Tailscale: needs Remote Access on in Sill.app and the device to know the
  Mac's addresses (a session at home with Remote Access on, or Add a Mac with the code).
- Spaces gestures were not re-run.
