# Files and photos between the iPhone or iPad and the Mac: the plan

2026-11-18. Noah, assigning the next features: "share files and photos between iOS and Mac", read as both ways
(the session's notes: "Files and photos go both ways between the device and the Mac (#189 only sends to the
Mac)"). The same night: "Anything that it would make sense to add a toggle to you should add a toggle", and the
Settings panel becomes a whole-screen pane ("Whole screen everywhere", branch `settings-pane`, in flight).
Issue #188, pull request #189 (addhumal, device to Mac only; built on and mostly replaced: its defects D1 to D16
are listed in `docs/steps/2026-11-18-files.md`). Branch `files` from #189's head 02cf1800 with origin/main merged
in; the branch's notes are in that step file. Status: the first part (device to Mac) is being built; "Progress" at the end says
what is done. Kind numbers follow the allocation of 2026-11-18: 34 for a file's bytes, 49 for the rest (48 is the
microphone's).

## 1. What it is, in a person's words

- **From the iPhone or iPad to the Mac.** In Sill's Settings, This iPad: **Send Files to ‹Mac›…** opens the
  Files picker and **Send Photos to ‹Mac›…** the Photos picker. The files go to the Mac, into **Downloads › Sill**,
  with a progress chip over the stream that says when they are there. On an iPad beside Files or Photos (Split
  View, Slide Over, Stage Manager), drag a file onto the picture and let go over a Mac window: it goes into that
  app as a drop would on the Mac itself (a Mail message attaches it, a Finder folder takes it, a browser's upload
  area takes it). In Files, and in other apps that share a file, Share › **Sill** sends it to the Mac Sill is
  connected to.
- **From the Mac to the iPhone or iPad.** On the device, **Get Files from ‹Mac›…** shows the Mac's own Open panel
  in the stream; the files chosen there come to the device. At the Mac, Sill's menu has **Send Files to ‹device›…**,
  and files dragged onto Sill's menu bar icon go too. They land in the Files app, **On My iPad › Sill › From ‹Mac›**;
  a photo or a video has **Save to Photos** beside it, and a switch saves them to Photos by themselves.
- **What never happens.** Nothing moves between devices that are not paired, nothing while the Mac is locked or
  another user is on its screen, nothing without a person's action on one end, and nothing passes through any
  server. Every file from a device is marked on the Mac as downloaded, so macOS checks it before it opens. Sill
  never opens a file by itself, on either end.
- **The picture first.** A transfer shares the session's connection with the picture and the person's input; it
  uses what they leave, a little at a time, so a tap still lands at once and the picture keeps its rate.

## 2. Decisions and who made them

- **Both ways, and photos** (Noah, 2026-11-18, the assignment).
- **A switch wherever one makes sense** (Noah, 2026-11-18): the Mac's Share files with devices; on the device
  Drop Files Into Apps, Ask Before Receiving Files and Save Photos and Videos to Photos (§9).
- **The device's rows live in the whole-screen Settings pane** (Noah, 2026-11-18): this branch places them in
  that pane's This ‹device› section once `settings-pane` lands (§14 orders it).
- **Received files on the device go in Sill's own folder in the Files app, no iCloud container**: Noah's shape for
  recordings (#284), taken here so one folder and one Info.plist change serve both.
- **Kept from the project's rules** (CLAUDE.md): Apple frameworks only, no server and no running cost; latency
  beats quality; the compatibility floor (additive, a kind never reused, a device sends a kind only to a host
  that says it takes it and the reverse); rules as pure types checked with swiftc and mutants; explicit
  threading; the modal-loop rule; never `MainActor.assumeIsolated` in core code; the CLI's stdout byte for byte.
- **Kept from the workflow's brief**: only paired sessions; never while the Mac is locked; an unpaired or removed
  device can do nothing.
- **Everything else in this plan is a recommendation**, taken unless Noah says otherwise: §17 lists each with its
  options.

## 3. What Apple documents, and what it does not (read 2026-11-18)

Documented:
- `NSDownloadsFolderUsageDescription`: "if your app creates a new file in the Downloads folder, the app can
  access that file without user consent", and a file the person selects "in an Open or Save panel, dragging it
  onto your app, or opening it in Finder" can be accessed "right away and any time in the future". So a folder
  Sill makes in Downloads, and a file in Downloads chosen in an Open panel or dropped on Sill's icon, need no
  prompt. (That page is the Downloads folder's; the Desktop's and Documents' keys were not read, so the same for
  a file chosen there is expected, not checked: P-test 7.)
- `URLResourceKey.quarantinePropertiesKey` (macOS 10.10+): a file's quarantine properties, set through
  `URLResourceValues` with LaunchServices' `kLSQuarantine…` keys. `LSFileQuarantineEnabled` would mark every
  file Sill.app writes, update staging included, so it is not used.
- `FileHandle.write(_:)` "raises NSFileHandleOperationException … if there isn't any free space on the file
  system" (deprecated in 27.3); `write(contentsOf:)` throws instead. Only the throwing calls are used.
- `NSItemProvider.loadFileRepresentation`: the copy is deleted "when the completion handler returns", so it is
  moved or cloned inside the handler.
- `PHPickerViewController` (iOS 14): system-rendered; gives the app what the person picks, Live Photos
  "without library access". `PHAccessLevel.addOnly` and `NSPhotoLibraryAddUsageDescription` ("required if your
  app uses APIs that have write access to the user's photo library").
- `UIFileSharingEnabled` ("place the files in a Documents folder") and `LSSupportsOpeningDocumentsInPlace` ("may
  open the original document from a file provider, rather than a copy"): with both, Sill's Documents shows in
  the Files app as On My iPad › Sill.
- Services: with `NSRequiredContext` present (even empty) a service is presented in the Services menu by itself;
  `NSSendFileTypes` takes UTIs and the service reads file URLs from its pasteboard (the archived Services
  guide).

Not documented, so each is a spike or a device test (§16): whether a folder Sill made in Downloads at an earlier
launch still needs no prompt; whether probing names there asks; which process owns a non-sandboxed app's
NSOpenPanel window, whether ScreenCaptureKit captures it, and whether browsing ~/Documents in it asks; whether
a Services invocation counts as consent; whether `loadFileRepresentation` serves `public.item` for a provider
that registered only `public.heic`; whether the share sheet of the Photos app lists an app by its document
types (likely not; the Files app's does); the wording of Apple's disk-space reason codes.

## 4. The design on one page

- **Wire.** Kind 34 (`FileChunk`, #66's binary layout, unchanged) carries the bytes both ways. A new kind 49
  (`FileTransfer`, JSON, both ways) carries everything else: the offer (names and sizes before any byte), the
  answer, the acknowledgements that pace the sender, each file's SHA-256, the result and the cancel, and a
  device's request for the Mac's Open panel. The window list says what the Mac takes (`files`); the hello says
  what the device takes (`Hello.files`); kind 16's existing `sessionPaired` says whether this session may.
- **Rules.** Pure types in StreamProtocol (`FilePolicy`, `FileNames`, `FileFlow`, `FileTransferState`, the
  shared words) and in SillHost (`FileDropPolicy`), checked by `Tests/checks/files` with random models and
  mutants.
- **Mac.** `FileHub` on a queue of its own (`sill.files`): admission, staging in a hidden folder, hashing,
  quarantine, the final rename, cleanup, the outbox. The server routes kinds 34 and 49 to it from its network
  queue and gives the Mac's chunks a send path of their own beside the sound's. The main actor only decides
  what needs it: the drop, the Open panel, the status menu.
- **Device.** `DeviceFiles` on a queue of its own: files read and written in 64 KiB pieces, never whole, hashed
  as they go. The pickers, the drop on the picture (on InputOverlay's own mapping), the share sheet, the chip,
  the rows; Photos with add-only access.
- **The window.** A sender keeps at most a window of bytes beyond the receiver's last acknowledgement: 512 KiB at
  home while the person is idle, 128 KiB while they use the stream or away, 64 KiB away and active or while the
  link is behind. A tap waits behind at most that much; the picture never waits behind a file's backlog.
- **No resume.** A session's own moves wait while a transfer runs; a lost connection ends it, and both ends
  delete what was partial.

## 5. The protocol

### 5.1 Kinds and capabilities

| What | Where | Meaning |
|---|---|---|
| Kind 34 `fileChunk` | both ways | `FileChunk` (#66's layout): part of one file of an accepted transfer |
| Kind 49 `fileTransfer` | both ways | `FileTransfer` JSON: offer, answer, ack, end, done, cancel, pick |
| `WindowList.files: Int?` | host → device | 0: this Mac has files but Share files with devices is off; 1: it takes files from a device; 2: and gives files to a device (the Open panel, the menu). Left out by hosts before, by a host without an identity (the CLI's plain door, which no device can pair with), and while the Mac is locked or off console (LockPolicy.list, as `clipboard`) |
| `Hello.files: Int?` | device → host | 1: this device takes kind 34 and 49 from the Mac. Nil from every device before: a host sends it neither |
| `HostSettingsState.sessionPaired` | host → device (exists) | the device offers only while its session's key is on the Mac's trust list |

- A device sends kind 49 and 34 only to a host whose list says `files` 1 or more, on a session whose kind 16 says
  `sessionPaired` true, while the list does not say `locked`; it sends `pick` only to a host that says 2.
- A host sends kind 49 and 34 only to a connection whose hello said `files` 1 or more, and only answers on it.
- Numbers: 34 is #66's number with #66's exact layout, as the clipboard took #66's 32, so #66 can still rebase;
  35 to 42 stay #66's (#66's `FileDrop` cannot refuse, answer or pace, so it is not used here); 49 is files' in the allocation of
  2026-11-18 (45 the pen, 46 the camera, 47 main's, 48 the microphone, 50 #175's cursor kind, 60 and 61 #195's),
  which gave the six workstreams of this assignment their numbers once, before any branch wrote one.

### 5.2 `FileTransfer` (kind 49, `Sources/StreamProtocol/Files.swift`)

One JSON shape for every message, `op` a String (never a Swift enum an older peer would fail on: an op this
build does not know is ignored, one TEST ONLY line), every other field optional and left out when nil. At most
`FileTransfer.maxPayload` (512 KiB) of JSON, under the host's 1 MiB cap for a device's message and the device's
4 MiB for a host's.

| Field | Type | In | Meaning |
|---|---|---|---|
| `op` | String | all | `offer`, `answer`, `ack`, `end`, `done`, `cancel`, `pick` |
| `transfer` | UInt32 | all | random, chosen by whoever offers (for a pick, by the device, and the Mac's offer answers with it) |
| `files` | [{`id` UInt32, `name` String, `size` UInt64, `type` String?}] | offer | each file's id (random, unique on the connection: kind 34's id), its name as the sender has it, its exact size, its UTI (informational only) |
| `drop` | {`x`, `y` Double} | offer, device → Mac | where the finger let go, as fractions of the picture (as a tap's); absent: save, never drop |
| `asked` | Bool | offer, Mac → device | these answer this device's own `pick`: taken without asking |
| `accept` | Bool | answer | true: send; false: with `reason` |
| `file`, `offset` | UInt32, UInt64 | ack | the receiver has written everything of `file` before `offset` |
| `sha256` | String | end | base64url of the file's SHA-256; the sender's last word for `file` |
| `kept` | [String] | done | each file's name as kept, in offer order |
| `place` | String | done | where they are, in the receiver's words ("Downloads › Sill", "Files › Sill › From Mac mini") |
| `droppedInto` | String | done, Mac → device | the app that took the drop |
| `dropRefused` | String | done, Mac → device | why the files were saved but not dropped (`FileDropPolicy`'s reason) |
| `reason` | String | answer, cancel | `off`, `notPaired`, `locked`, `busy`, `tooMany`, `tooBig`, `noRoom`, `rate`, `declined`, `noAnswer`, `stalled`, `damaged`, `lost`, `cantSave`, `cantRead`, `nothingChosen`, `background`; a reason the reader does not know is shown with `message`, else generic words |
| `message` | String | answer, cancel | the sender's words, shown as they are once cleaned (`SafeText`), as kind 22's `message` |

### 5.3 `FileChunk` (kind 34)

\#66's layout, byte for byte: the file's id (UInt32 BE), the name's length (UInt16 BE) and UTF-8, the whole size and
this part's offset (UInt64 BE each), then the bytes. This protocol sends the name empty (the offer named the file);
a reader takes a name it is given and ignores it. A sender sends at most `FilePolicy.chunkBytes` (64 KiB) a part;
a receiver takes up to #66's 512 KiB. `FileChunk` moves from `Clipboard.swift` to `Files.swift`; #189's `safeName`
and `chunks` go (§6.2 replaces one; the other loaded whole files).

### 5.4 A transfer, step by step

Device to Mac:
1. The device: `offer` {transfer, files, drop?} once its outbox holds every file (picked, dropped or shared).
2. The Mac (`FilePolicy.answer`, on `sill.files`): `answer` {accept true}, or {accept false, reason}. No byte has
   moved yet.
3. The device: kind 34 parts in order, file after file, while its window allows (§6.3); `end` {file, sha256}
   after each file's last part.
4. The Mac: writes each part into the staging folder, `ack` {file, offset} as each is written; at each `end` it
   checks the size and the hash, marks the file (quarantine, where from) and renames it into place.
5. Every file kept: if the offer had `drop` and `FileDropPolicy` allows, the Mac drops them (§7.4). Then `done`
   {kept, place, droppedInto or dropRefused}.
6. Either end may `cancel` {reason} at any moment; the receiver deletes what is partial (files already kept
   stay, and `done` never comes). No progress for `stallLimit` (30 s): the sender cancels `stalled`.

Mac to device:
1. The device's **Get Files from ‹Mac›…**: `pick` {transfer}. The Mac shows its Open panel to the device (§7.5);
   chosen files come as `offer` {transfer, files, asked true}; Cancel in the panel, or 3 minutes, gives `cancel`
   {nothingChosen}.
2. Or the Mac's person starts it (the menu, the icon): `offer` without `asked`.
3. The device answers by its rules (§6.1): at once for `asked`, after its person's Accept with Ask Before
   Receiving Files on (60 s, else the Mac cancels `noAnswer`), at once with it off.
4. Then as above, the Mac sending and the device acknowledging, with the Mac's sends on their own path (§7.2).

### 5.5 For the compatibility floor (CLAUDE.md, once a public build ships it)

Kind 34 as #66's `FileChunk`; kind 49 and `FileTransfer`'s fields and known ops and reasons; `files` and its
values; `Hello.files`; a device sends kinds 34 and 49 only to a host that says `files` 1 or more (and `pick` only
at 2), a host only to a device whose hello says `files`; an unknown `op` is ignored, an unknown `reason` shown by
its `message`; a later generation of files (folders, resume) says 3 or adds a field and goes only to a peer that
says so. The floor's "29 to 31 and 33 to 42 stay free" becomes "29 to 31, 33 and 35 to 42".

## 6. The rules (pure)

### 6.1 `FilePolicy` (`Sources/StreamProtocol/FilePolicy.swift`): who, when, how much

- **The device offers** (`deviceOffers`): connected; the Mac's `files` ≥ 1; kind 16's `sessionPaired` true; the
  list not `locked`; no other outgoing transfer on this session. Why not, for the rows: `older` (no `files` from a
  Mac whose list carries a version), `off` (0), `notPaired`, `locked`, `busy`.
- **The Mac answers an offer** (`answer`), first failing wins: Share files with devices off (`off`); the session's
  key not on the trust list now (`notPaired`, `StreamCoordinator.sessionPaired`'s judgement); the lock, at the
  reading the offer arrived at and at the reading now, the stricter (`locked`; off console too, the off-console
  view included); another transfer from this device already running (`busy`), or four on the Mac in all; more than
  `maxFiles` (500) files (`tooMany`); more than `maxBytes` (100 GB) (`tooBig`); the destination's free space less
  than the total plus `keepFree` (2 GB) (`noRoom`); more than `offerRate` (2) offers a second from this connection
  (`rate`, never counting a cancel). A name is never a reason: it is cleaned (§6.2).
- **The device answers the Mac's offer** (`deviceAnswers`): `asked` → accept; another incoming transfer
  running → `busy`; over `maxFiles` or `maxBytes` → `tooMany`, `tooBig`; Ask Before Receiving Files on → wait
  for the person (Accept, Decline → `declined`); else accept.
- **The Mac offers to a device** (`macOffers`): its hello said `files`; paired; unlocked; Share files with devices
  on; no other outgoing transfer to it. **A pick** (`takesPick`): the same, and no Open panel already up for any
  device, and none closed by this device within `pickSpacing` (5 s).
- **Timers**: `answerWait` 60 s, `stallLimit` 30 s, `panelLimit` 180 s.
- **What a cancel takes**: always taken, locked or not, rated never (as the clipboard's `stop`).

### 6.2 `FileNames`: a name from the other end

`clean(_:)`: NFC; every control character (C0, C1, DEL), line and paragraph separator, bidi control (U+202A–U+202E,
U+2066–U+2069, U+200E, U+200F, U+061C) and zero-width character (U+200B–U+200D, U+FEFF) removed; `/`, `:` and NUL
become `-`; spaces and dots trimmed at both ends; a name that starts with a dot gets "File" in front (never a hidden
file); empty becomes "File"; cut to `maxBytes` (200) UTF-8 bytes on a character boundary, keeping the extension
(≤ 16 bytes) whole, so " 99" and the staging suffix stay under APFS's 255. `unique(_:taken:)`: "name 2.ext",
"name 3.ext"… against what the folder holds, case-insensitively (APFS's default). `isPhotoOrVideo(_:)`: by the
cleaned name's extension conforming to `public.image` or `public.movie`; the sender's `type` is never trusted.
`logLabel(_:)`: never a name; logs carry counts and sizes (§11).

### 6.3 `FileFlow`: the window, the picture and the person first

- `chunkBytes` 64 KiB.
- `window(away:active:linkBehind:)`: home and idle 512 KiB; home and active 128 KiB; away and idle 128 KiB; away
  and active, or the link behind or stalled, 64 KiB. "Active": input from this device in the last second. At 5 ms
  round trips the home window carries about 100 MB/s; away at 80 ms, 64 KiB still carries 6.5 Mbit/s.
- The sender sends while `sent − acked + chunk ≤ window`; nothing waits in memory beyond the part being sent.
- **The Mac's sends** also wait (`hostMaySend`) until the connection has taken all but `idleBytes` (64 KiB) of what
  it holds (`Client.pendingBytes`), and while the device waits for a keyframe or one is still crossing to it
  (`needsKeyframe`, `keyframesInFlight`): a frame never queues behind more than one part of a file in Sill's own
  queue, and a keyframe never waits for one.
- What a tap waits for behind an upload: at most a window at the uplink's rate (128 KiB at 100 Mbit/s: 10 ms; 64 KiB
  at 5 Mbit/s: 105 ms). Gate H8 holds the numbers.

### 6.4 `FileTransferState`: both ends

Two small machines, sender and receiver, pure, driven by events (offered, answered, part sent, acked, ended,
hash checked, kept, dropped, cancelled, connection ended, timer) and returning what to do (send this, write that,
delete these, tell the person). Their invariants, which the check's random model holds 5,000 runs a direction:
never a part beyond the window; never a byte written for a transfer not accepted, cancelled or from another
connection; a part out of order, of the wrong total or past the size ends the transfer `damaged`; never a file
kept whose size or hash differs; every partial deleted at a cancel, a connection's end, a cut-off, a lock, a quit
and the next launch; every offer answered or timed out; never accepted while locked or unpaired; `done` only after
every file is kept.

### 6.5 `FileDropPolicy` (`Sources/SillHost/FileDropPolicy.swift`, pure)

`decide` → `.drop(at:)` or `.save(reason)`. A drop only when all hold: the offer had `drop`; every file was kept;
something streams (`active` not `.none`); the point lands inside the source (`InputLanding.point`); the window
on top at that point, every layer counted (`CGWindowListCopyWindowInfo`, on screen only), is the streamed window
itself for a window source, or for the Desktop an app's ordinary window (layer 0, as `CatalogWindows` lists one)
or Finder's desktop, never the Dock, the menu bar, Control Center or Notification Center; the device holds no
mouse button down; the Mac unlocked at both readings; Accessibility granted; not a synthetic host (it logs the
drop it would make: `.save(.dryRun)`). Reasons: `noPoint`, `notAllKept`, `nothingStreams`, `outside`, `covered`,
`systemUI`, `buttonHeld`, `locked`, `noAccessibility`, `dryRun`.

### 6.6 The words: `FilesCopy`

The reasons' words for both ends live in StreamProtocol (`FilesCopy.reasonLine(_:mac:device:name:)`), so the Mac's
menu and the device say the same thing and the check reads every one; the device's own words (rows, footnotes,
chips) in `iOSClient/FilesCopy+Device.swift`, the Mac's in `StatusText` and `SettingsPanes`. §10 has them all.

## 7. The Mac

### 7.1 Files

New:
- `Sources/StreamProtocol/Files.swift`: `FileChunk` (moved), `FileTransfer`.
- `Sources/StreamProtocol/FilePolicy.swift`: §6.1–6.4 and `FilesCopy`'s shared lines.
- `Sources/SillHost/FileStore.swift` (Foundation only): the destination and its hidden staging folder
  (`‹destination›/.Sill Incoming`), parts written with `open(O_CREAT | O_EXCL | O_NOFOLLOW, 0600)` and
  `write(contentsOf:)`, the running SHA-256 (CryptoKit), the size check, quarantine
  (`kLSQuarantineAgentNameKey` "Sill", `kLSQuarantineAgentBundleIdentifierKey` the app's, `kLSQuarantineTypeKey`
  `kLSQuarantineTypeOtherDownload`) and Where From (`com.apple.metadata:kMDItemWhereFroms`: "‹device›, through
  Sill", the device's paired name), mode 0644, no hidden extension, the final move with
  `renamex_np(RENAME_EXCL)` under `FileNames.unique`, the leftovers' cleanup; and for the outbox, reading a file in
  parts. Checked on its own (`Tests/checks/file-store`).
- `Sources/SillHost/FileHub.swift`: the transfers by connection on `sill.files`; `FilePolicy` and
  `FileTransferState` applied; acks and the outbox's sends through the server; the context the coordinator pushes
  (the switch, the trust list, each connection's route, hello and pairing, the destination); callbacks to the
  main actor (a drop to make, a pick to show, the status).
- `Sources/SillHost/FileDropPolicy.swift` (pure) and `Sources/SillHost/FileDrop.swift` (AppKit, §7.4).
- `Sources/SillHost/FilePick.swift` (AppKit, the app only, §7.5).
- `Tests/checks/files/` and `Tests/checks/file-store/` (§12.1).

Changed:
- `StreamMessage.swift` (kinds 34 and 49), `Switcher.swift` (`files`), `Compatibility.swift` (`Hello.files`).
- `StreamServer.swift`: kinds 34 and 49 handed to `onFileMessage` on the network queue with the gate's reading at
  arrival (never `onMessage`, so no main-actor hop per part); a revoked client's file kinds dropped as every other
  kind is; `Client.takesFiles` from the hello; `sendFile(_:to:)`, a send path of its own like `sendAudio`: never in
  `inflight`, `inflightFrames` or the drain eviction, counted in `pendingBytes` and, once taken, in
  `takenThisSecond`, so each device's LinkJudge sees the link carry it; the gate withholds kinds 34 and 49 while
  locked.
- `LockPolicy.swift`: `Request.files(cancels:)` (refused locked unless a cancel; refused in the off-console
  view), `Refusal.files` with its line, `withheld` adds 34 and 49, `list` leaves `files` out.
- `StreamCoordinator.swift`: the context pushed to FileHub at each change; `files` in `listMessage`; a lock, a
  cut-off (`onCutOff`), a leave and a quit cancel that connection's transfers; the drop and the pick on the main
  actor; a device's offer or pick, which FileHub reports since file kinds never reach `handle`, passed to
  DisplayWake (`deviceActive`); the status. #189's cases and `FileDrops` go (out of `HostClipboard.swift`).
- `DisplayWake.swift`: a device's `offer` and `pick` are a person at the device (the display wakes); parts,
  acks and ends are not.
- `InputInjector.swift`: posts the drop's events, noted as Sill's own motion for PointerControl, with the device's
  further input held until the drop ends (2 s at most) and then delivered in order.
- `CatalogWindows.swift`: the one exception to "never Sill's own window": the pick's Open panel, while a pick
  has it up.
- `HostConfig.swift` (`shareFiles`, on in `standard` and `app`; `filesFolder`, nil for ~/Downloads/Sill),
  `DeviceSettings` (neither is a device's to set), `HostStatus.swift` (each device's transfer for the menu),
  `HostShutdown.swift` (partials deleted at quit), `TestHooks.swift` (§7.6).
- `Sources/SillHostCLI/main.swift`: `--no-files`.
- `Sources/SillMenuBar/`: `HostSettings.swift` (keys `shareFiles`, `filesFolder` as bookmark data),
  `SettingsPanes.swift` (`FilesSection` under `ClipboardSection` in General), `StatusItemController.swift` and
  `StatusText.swift` (Send Files to ‹device›…, the card's line, Show in Finder; drops on the icon), `AppModel.swift`
  (`holdAppNapOff`: while a transfer runs the activity is `.userInitiated`, which keeps the Mac from idle sleep, at
  home too), `DebugHooks.swift` (`-SillSetAfter 'shareFiles=0'`, previews of the section).
- `Packaging/Info.plist`: `NSDownloadsFolderUsageDescription` (in case macOS asks after all, §16).

### 7.2 Threading

- **Network queue** (StreamServer): reads; hands kinds 34 and 49 to `FileHub.received` with the reading at arrival;
  sends FileHub's messages, parts through `sendFile`.
- **`sill.files`** (FileHub, FileStore): every decision of §6.1 but the drop's, every write, hash, rename and read
  of a file, the timers. One queue, so a transfer's events are in order without locks; the lock's reading comes
  from `LockGate` (already read from any queue), the rest from the context the main actor pushes.
- **Main actor** (StreamCoordinator, FilePick, FileDrop, the app): the context, the drop, the Open panel, the
  status. Never a file's bytes.

### 7.3 Where files land

- **Downloads › Sill** by default: a folder Sill makes, so no prompt (Apple's rule above) and every name check
  happens in Sill's own folder; one level from Downloads, which Finder's sidebar and the Dock's stack show. The
  Mac's person can choose another folder in Settings (an Open panel: its choice is granted).
- Parts go to `.Sill Incoming` inside the destination (hidden, same volume, so the final rename is atomic); a
  file appears under its name only once whole, checked and marked. Leftovers go at quit and at the next launch.
- The menu's device card says "Received ‹name›" with Show in Finder for ten minutes; Sill never opens or reveals
  anything by itself.

### 7.4 The drop

When `FileDropPolicy` says drop: the main actor holds the device's further input; an 8×8 non-activating panel of
Sill's own goes under the point (#66's and #189's way, kept); InputInjector posts a move, a press, three drags and
a release there (#66's timings), noted as Sill's own motion; the panel's view starts an NSDraggingSession of the
kept files with `.copy`, `.move` and `.generic` (no `.link`, no alias); `draggingSession(_:endedAt:operation:)` says
whether the target took them; the panel goes; the held input goes on in order; `done` says `droppedInto` the app
that owns the window under the point, or that it was not taken (the files stay in the folder). Otherwise
`done` says `dropRefused`. Never onto the Dock, the menu bar, or a window covering the streamed one.

### 7.5 Mac to device: the device's pick, the menu, the icon

- **The device's pick.** The Mac shows an NSOpenPanel (files, several, no folders; title "Send Files to
  ‹device›", prompt "Send") with `begin`, never `runModal` (the modal-loop rule), activating Sill so it is in front.
  The device must see it, and Sill's own windows never reach a device today (the Desktop's filter leaves Sill out;
  the catalog never lists it). So, while the panel is up: the catalog lists that one window (an exception in
  `CatalogWindows`, which the check holds to the pick's window), the host picks it as the source (never staged on
  Sill's display; captured as a desktop-independent window), so every device sees it and the device's taps land on
  it, and when the panel closes the source goes back to what streamed. The panel closes, `cancel`
  {nothingChosen}, when its 3 minutes run out, when the device leaves, when the Mac locks, or when any device picks
  another source. **Spike S0 first** (the bare app, no Screen Recording asked): which process owns the panel's
  window (`CGWindowListCopyWindowInfo`'s owner pid, which needs no grant); if it is not Sill's (an out-of-process
  panel), the Desktop's filter already shows it and the pick streams the Desktop of the panel's display instead.
- **The menu.** Sill's status menu: Send Files to ‹device›… for each connected device that takes files (a submenu
  with two or more); an Open panel at the Mac; the device then asks its person (Ask Before Receiving Files).
- **The icon.** Files dragged onto Sill's menu bar icon go to the one device that takes files, or, with several,
  open the Send Files To submenu at the icon (from a run-loop Timer, as the modal-loop rule allows). The drop is
  documented consent. The icon takes drags through a clear view over the status item's button (P-test 10).
- **Later** (§17, Q4): Finder's Services item "Send to iPhone or iPad with Sill" (`NSServices`, `NSSendFileTypes`
  public.item, `NSRequiredContext` empty), for a right-click in the stream; and Copy in Finder, then Get Copied
  Files on the device, through the clipboard's look and `MacAccess`.

### 7.6 The CLI, test hosts and hooks

- The CLI takes files only with an identity (`--pairing` or `--remote`), `files` 1 (no Open panel, no menu);
  `--no-files` turns it off for the run.
- A synthetic host takes files into a folder of its own, never ~/Downloads, and drops nothing (it logs the drop it
  would make). TEST ONLY, honoured only by a test host (`DoorPolicy.isTestHost`; anywhere else TestHooks prints one
  "ignored" line): `SILL_TEST_FILES_DIR=<dir>` (else `$TMPDIR/sill-test-files-<pid>`), `SILL_TEST_FILES_LOG=1` (each
  decision with sizes, never a name or a byte), `SILL_TEST_FILES_FREE=<bytes>` (the free space the rule reads),
  `SILL_TEST_FILES_PICK=<path>[:<path>…]` (a pick answered with these, no panel), `SILL_TEST_FILES_OFFER='<s>
  <path>'` (at s seconds, the host offers that file to each device that takes files, as the menu would),
  `SILL_TEST_FILES_TOPMOST=<owner>:<layer>` (the window the dry drop finds on top).

## 8. The iPhone and iPad

### 8.1 Files (pbxproj pairs A188–A18E and F188–F18E, checked against open pull requests when added)

New:
- `iOSClient/DeviceFiles.swift` (Foundation, Network, CryptoKit; checked with swiftc against a stand-in host on
  loopback, `Tests/checks/device-files`): the outbox and the inbox on `sill.files`, `FileTransferState` applied,
  parts read and written 64 KiB at a time, hashes, the window.
- `iOSClient/StreamClient+Files.swift`: the session's glue (hello, list, kind 16, kinds 34 and 49 from
  MessageReader, `tearDown`), the published state the chip and the rows read, the share sheet's files waiting
  for a session.
- `iOSClient/FilePickers.swift`: the Files picker (`UIDocumentPickerViewController(forOpeningContentTypes:
  [.item], asCopy: false)`, several), the Photos picker (`PHPickerViewController`, `.current` representation so
  originals come as they are, HEIC and HEVC included), Quick Look for Show.
- `iOSClient/PictureDrop.swift`: a `UIDropInteraction` on `InputOverlayView`.
- `iOSClient/FileChip.swift`: the chip (sending, receiving, an offer to accept, the result).
- `iOSClient/PhotoSaver.swift`: add-only access, `PHAssetCreationRequest` from a file.
- `iOSClient/FilesCopy+Device.swift`: the device's words and where the rows show (pure, in `Tests/checks/files`).

Changed: `StreamClient.swift` (hello `files: 1`), `HostSettingsPanel.swift` or the whole-screen pane (the rows,
§9), `StreamScreen.swift` and `PortraitStreamScreen.swift` (the chip in the clipboard chip's corner; the clipboard's
chip waits while a file's shows), `InputOverlay.swift` (the drop's mapping through `normalized`), `SillApp.swift`
(`onOpenURL` for file URLs beside `sill://`), `DeviceIdlePolicy.swift` (a transfer holds the device's auto-lock off),
`DiscoveryPolicy.swift` (`pathPlan` waits while a transfer runs), `MockCatalog.swift` (the harness's cases),
`Info.plist` and `Info-Debug.plist` (§8.3, §8.4), `ClipboardChip.swift`, `StreamClient+Clipboard.swift` and
`StreamScreen.swift` lose #189's code.

### 8.2 Threading and memory

- The connection's queue (MessageReader) hands kinds 34 and 49 to `sill.files`; `link.send` is thread-safe
  (SessionLink's lock). The main thread only shows state.
- Nothing is ever whole in memory: a file is read and written 64 KiB at a time, and no more than a window waits
  anywhere. During a move's fence or hold no ack comes, so the sender stops at its window and SessionLink keeps at
  most that.

### 8.3 Sending

- **Files**: security-scoped URLs read in place under `NSFileCoordinator` (an iCloud file downloads first), never
  copied; folders are not offered in this version.
- **Photos**: each picked item's file representation, moved (an APFS clone) into `tmp/SillOutbox/‹transfer›`
  inside the handler; a Live Photo sends its still; deleted once sent or cancelled, and at launch.
- **The drop on the picture** (iPad, and an iPhone's own drag between apps): offered only while the device may
  offer (§6.1); the point mapped by InputOverlay's `normalized(point, clamped: false)` (the zoom and the letterbox
  counted), so a drop on the black bars is a save, not a drop; each item loaded as its own first registered type
  that conforms to `public.data` (not by asking every provider for `public.item`), its name `suggestedName` plus
  that type's extension; `drop` sent only with Drop Files Into Apps on. VoiceOver: the picture names its drop
  point ("Drop into ‹window›").
- **The share sheet**: `CFBundleDocumentTypes` with one type, `public.item`, rank Alternate, and
  `LSSupportsOpeningDocumentsInPlace`, so Sill shows in the share sheet's apps for a file; a file opened in Sill
  asks "Send ‹name› to ‹Mac›?" while a session takes files, else "Connect to a Mac to send ‹name›." and waits 10
  minutes for one. An Inbox copy iOS makes is moved to the outbox and deleted after.

### 8.4 Receiving

- Into `Documents/From ‹Mac›/` (`UIFileSharingEnabled`, so On My iPad › Sill shows in the Files app: the same
  change #284's recordings need), staged in `Library/Application Support/Sill/Incoming` (same volume), complete file
  protection once kept, as the tiles' pictures have.
- The chip: "‹name› from ‹Mac› is in Files › Sill." with Show (Quick Look, which carries the system's Share) and,
  for a photo or a video, Save to Photos. With Save Photos and Videos to Photos on, those go to Photos (add-only
  access asked when the switch goes on) and leave Files once Photos has them.
- No disk-space query: a full device ends the transfer with "There isn’t enough room on this ‹iPad› for
  ‹name›." (the write's ENOSPC), so the privacy manifest gains nothing (§17, Q12).

### 8.5 The session around a transfer

- A session's own moves (to the cable, to Wi-Fi, home: `pathPlan`) wait until no transfer runs; a lost path, a hold
  that becomes a new connection, Disconnect or the Mac's goodbye ends the transfer (`lost`), both ends deleting
  what was partial.
- Sill leaving the screen: a background task while a transfer runs; when iOS ends it, the transfer is cancelled
  (`background`) and the chip says so when Sill comes back. With Picture in Picture showing, the app runs and the
  transfer goes on.
- The device's auto-lock stays off while a transfer runs (DeviceIdlePolicy's new input), as while a window streams
  and the person uses it.

## 9. Settings: names, places, defaults

| Where | Name | Key | Default | Notes |
|---|---|---|---|---|
| Mac, Settings › General, under Share clipboard | Share files with devices | `shareFiles` | on | the Mac's alone, like the clipboard's; off: `files` 0, every offer and pick refused `off`, running transfers cancelled |
| Mac, same section | Save files from devices in | `filesFolder` (bookmark) | Downloads › Sill | Other Folder…, Show in Finder |
| CLI | `--no-files` | | on with an identity | |
| Device, Settings › This ‹device›, the Files rows | Drop Files Into Apps | `Sill.dropIntoApps` | on | off: a drop on the picture saves only |
| Device, same | Ask Before Receiving Files | `Sill.askBeforeReceiving` | on | never for files the device asked for |
| Device, same | Save Photos and Videos to Photos | `Sill.photosAutoSave` | off | turning it on asks for add-only access |

The device's rows, in This ‹device› after the clipboard's (in the whole-screen pane once it lands): Send Files
to ‹Mac›…, Send Photos to ‹Mac›…, Get Files from ‹Mac›… (only at `files` 2), the three switches (the last two only
at `files` 2), the footnote. Shown while the Mac says `files` (0, 1 or 2), or as one footnote for an older Mac;
disabled with their reason when the Mac's switch is off (0), the session is unpaired or a transfer runs; hidden
while locked (the panel's header already says why).

## 10. Every sentence shown to a person

**Device rows and footnotes**
- "Send Files to ‹Mac›…" · "Send Photos to ‹Mac›…" · "Get Files from ‹Mac›…"
- "Drop Files Into Apps" · "Ask Before Receiving Files" · "Save Photos and Videos to Photos"
- Footnote: "Files you send go to Downloads › Sill on ‹Mac›. Drag a file onto the picture to drop it into the app
  under your finger. Files from ‹Mac› are in the Files app, in On My ‹iPad› › Sill."
- With Drop Files Into Apps off, its middle sentence: "Drag a file onto the picture to send it too."
- With Ask Before Receiving Files on: "Sill asks before saving files ‹Mac› sends you. Files you get with Get Files
  come at once."
- With Save Photos and Videos to Photos on: "Photos and videos from ‹Mac› go to your Photos library."
- Unpaired: "Files go only between paired devices. Pair this ‹iPad› with ‹Mac› to send files."
- Off: "‹Mac› doesn’t share files. Turn on Share files with devices in Sill’s Settings on ‹Mac›."
- An older Mac: "To send files, update Sill on ‹Mac›."

**The chip**
- "Sending ‹name› to ‹Mac›" · "Sending ‹n› files to ‹Mac›" with "42%" and Cancel (VoiceOver: "Cancel sending")
- "Saved in Downloads › Sill on ‹Mac›."
- "Dropped into ‹App› on ‹Mac›."
- "‹App› didn’t take it, so it’s in Downloads › Sill on ‹Mac›."
- "Saved in Downloads › Sill on ‹Mac›. It wasn’t dropped: ‹why›." (`dropRefused`: "the Dock was there", "another
  window covers that spot", "it landed outside the window", "‹Mac› can’t click for Sill yet")
- "‹Mac› wants to send you ‹name› (‹size›)." with Accept and Decline · "‹n› files (‹size›)"
- "Receiving ‹name› from ‹Mac›" with "42%" and Cancel
- "‹name› from ‹Mac› is in Files › Sill." with Show, and Save to Photos for a photo or video · "Saved to Photos."
- "Send ‹name› to ‹Mac›?" with Send and Cancel · "Connect to a Mac to send ‹name›."
- Announced to VoiceOver: the start, the end, a failure; the chip's value is the percentage.

**Reasons** (`FilesCopy.reasonLine`, both ends)
- `locked`: "‹Mac› is locked. Unlock it to send files."
- `notPaired`: "Files go only between paired devices."
- `off`: "‹Mac› doesn’t take files now."
- `busy`: "Another transfer with ‹Mac› is still going. Try again when it’s done."
- `tooMany`: "That’s more than 500 files. Send fewer at a time."
- `tooBig`: "That’s more than 100 GB. Send less at a time."
- `noRoom`: "There isn’t enough room on ‹Mac› for these files."
- `rate`: "Too many at once. Try again in a moment."
- `declined`: "‹device› declined the files." · `noAnswer`: "Nobody answered on ‹device›."
- `stalled`: "The transfer stopped moving. Send it again."
- `damaged`: "‹name› didn’t arrive whole. Send it again."
- `lost`: "The connection to ‹Mac› ended. Send it again."
- `cantSave`: "‹Mac› couldn’t save ‹name›." · `cantRead`: "Sill couldn’t read ‹name› on this ‹iPad›."
- `background`: "Sending stopped when Sill left the screen. Send it again."
- The device full: "There isn’t enough room on this ‹iPad› for ‹name›."
- Photos denied: "Sill can’t add to Photos. Allow it in Settings › Privacy & Security › Photos."
- Unknown: the `message`, else "‹Mac› couldn’t take the files."

**Mac**
- Settings: "Share files with devices"; footnote: "A paired iPhone or iPad can send files to this Mac and get files
  you choose. Files from devices are marked as downloaded, so macOS checks them before they open. Never while this
  Mac is locked."; "Save files from devices in", "Downloads › Sill", "Other Folder…", "Show in Finder".
- Menu: "Send Files to ‹device›…" · "Send Files To" · the card: "Sending ‹name› · 42%", "Receiving ‹n› files · 42%",
  "Received ‹name›", "Show in Finder", "Stop Transfer" (while one runs: a `cancel` to the device), and the reasons'
  lines.
- Open panel: title "Send Files to ‹device›"; message for a pick: "‹device› asked for files from this Mac. Choose
  what to send."; prompt "Send".
- Info.plist: "Sill saves the files your iPhone or iPad sends you in Downloads."
- Log (counts and sizes, never names): "Files: saved 2 files (12.3 MB) from ‹device› in Downloads/Sill in 4.1 s.",
  "Files: dropped 1 file from ‹device› into Mail.", "Files: sent 1 file (2.0 MB) to ‹device› in 0.4 s.",
  "Files: ‹device› cancelled (the connection ended).", and one refusal line a minute (RefusalSummary): "Files:
  refused 3 offers from devices: not paired (2), locked (1)."

**Device's Info.plist**: `NSPhotoLibraryAddUsageDescription` "Sill saves photos and videos from your Mac to your
library."; the document type's name "File".

## 11. Security

- **Who.** Only a session whose key is on the Mac's trust list now: `sessionPaired`, judged at each offer and
  pick, not once. An unpaired session (Require pairing off, the CLI's plain door) is refused `notPaired`, and its
  rows say so. A removed device does nothing: the server passes it only key and button ups, the coordinator
  drops the rest, and the cut-off cancels its transfers and deletes their partials.
- **A locked Mac.** No offer, part or pick acts: LockPolicy refuses them at the reading they arrived at and at the
  reading now (so nothing sent while locked acts after an unlock), the list leaves `files` out, the gate withholds
  the Mac's kinds 34 and 49, and a lock cancels every transfer and closes the Open panel. Off console and in the
  off-console view, the same.
- **The Mac's person decides.** Share files with devices, and the folder. They see each transfer in the status
  menu's card; the Open panel of a pick is on their screen.
- **Names and paths.** `FileNames.clean` (§6.2); one component, always; parts created `O_EXCL | O_NOFOLLOW` in Sill's
  own hidden folder; the final move `RENAME_EXCL` into the destination; a chosen destination that is a link or that
  Sill cannot write is refused in Settings.
- **Executables.** Every received file carries `com.apple.quarantine` with Sill as the agent (Gatekeeper treats an
  app inside a zip, a .pkg, a .dmg or a script as downloaded), mode 0644, no hidden extension. Nothing is opened
  by Sill; a drop goes only into a window, never onto the Dock or the menu bar; Finder is never brought forward.
  If quarantine cannot be set, the file is deleted and the transfer fails `cantSave`. No type is refused.
- **Limits.** 500 files, 100 GB and the free space less 2 GB per transfer; one transfer a direction per device,
  four on the Mac; 2 offers a second; 60 s to answer, 30 s without progress, 3 minutes for a pick; a part out of
  order, of another total, past the size or over 512 KiB ends the transfer. Open files: one per running transfer.
- **Integrity.** TLS on every door a paired session uses; a SHA-256 per file against our own mistakes.
- **Away from home.** Allowed: the remote door admits only paired keys; the window is smaller there.
- **The device's side.** It reads only what the person picks, drops or shares; Photos only through the system's
  picker; add-only access, never read access; received files stay in Sill's container with complete protection;
  Quick Look previews them out of process; a Mac's files never open by themselves.
- **Logs.** Counts and sizes; never a name or a byte (as the clipboard never logs its text).

## 12. Tests

### 12.1 Pure checks (CI and mutants)

- **C1 `Tests/checks/files`** (StreamProtocol's sources as a module, with `Sources/SillHost/FileDropPolicy.swift`
  and `iOSClient/FilesCopy+Device.swift`): kind 49's JSON both ways, an op and a reason not known, the caps; each
  of `FilePolicy`'s conditions at its edge, in order; `FileNames` on a table of hostile names (`../x`, `a/b`, `a:b`,
  NUL, newlines, U+202E, zero-width, 300-byte Japanese, emoji at the cut, `.hidden`, `..`, spaces only, NFD and NFC
  twins, an extension longer than 16 bytes) and 20,000 random strings against its properties (one component, ≤ 200
  bytes, never hidden, never empty, idempotent, unique within a folder); `FileFlow`'s windows and `hostMaySend`;
  both state machines against a model, 5,000 random transfers a direction with acks, cancels, locks, losses,
  cut-offs, quits and timers (§6.4's invariants); `FileDropPolicy` over every combination; every word. About 40
  mutants, each of the rules' conditions and numbers, every one caught.
- **C2 `Tests/checks/file-store`**: FileStore on a scratch folder: parts, hashes, a wrong hash, a short file, a
  collision with a file and with a link, quarantine and Where From read back (`getxattr`), leftovers cleaned,
  mode 0644.
- **C3 `Tests/checks/device-files`**: DeviceFiles against a stand-in Mac on loopback (as `fence` and
  `message-reader` are): 1,000 parts of each size arrive whole, never more than the window unacknowledged, a cancel
  stops at once, a part out of order ends the transfer, memory flat.
- **C4** `protocol`, `compatibility` (34, 49, `files`, `Hello.files`, an older WindowList and Hello reading them),
  `pointer-control` (the kind table), `display-wake` (49's offer and pick a person, 34 not), `lock-policy` (the
  new request, the gate, the list), `device-idle`, `home-device` (`pathPlan`) and `repo-rules`.

### 12.2 Headless gates

Loopback synthetic hosts only: `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1
SILL_TEST_NO_SCREEN=1`, `--pairing` with `SILL_TEST_REMOTE_DIR`, and `SILL_TEST_FILES_DIR`, so no test touches the
hardware encoder, the router, ScreenCaptureKit or this Mac's Downloads. `Scripts/sillclient.py` gains `--send-file=PATH[,X,Y]@T`, `--cancel-files@T`, `--accept-files=DIR`,
`--decline-files`, `--pick-files@T`, `--raw49=JSON@T`, `--raw34=ID,TOTAL,OFFSET,HEX@T` and `--expect-files=…`, and
prints each kind 49 on a line.
- **H1** `swift build -c release`; the iOS app Debug and Release for the simulator, Debug for a device: only the
  known warnings.
- **H2** The CLI's stdout: main's and the branch's (`git archive`), idle 35 s and with a client picking the Desktop
  15 s that sends no file, masked and sorted: identical.
- **H3** Device to Mac: 0 B, 1 B, 64 KiB, 64 KiB + 1, 100 MB, 500 files of 1 KB, 501 (`tooMany`); every kept file
  byte for byte and hash for hash the source; quarantine and Where From present; nothing left in `.Sill Incoming`;
  `lsof` shows at most one open file per transfer.
- **H4** Refusals: an unpaired session (`SILL_TEST_REQUIRE_PAIRING=0`, an unpaired identity, `--pin=none`):
  `notPaired`; `--no-files`: `files` 0, `off`; locked before (`SILL_TEST_LOCKED_FILE`): no `files`, `locked`; locked
  mid-transfer: cancelled, partials gone, nothing acts after the unlock; `SILL_TEST_FILES_FREE`: `noRoom`; ten offers
  at once: two taken, one line.
- **H5** Hostile peer: parts with no offer (dropped, counted), another total, a gap, a part over 512 KiB, an op not
  known, every name of C1's table, 10,000 offers a minute, an offer and silence (30 s, `stalled`), a disconnect
  mid-file: no file outside the folder, no part left, the host's open files bounded.
- **H6** Mac to device: `SILL_TEST_FILES_OFFER` and `SILL_TEST_FILES_PICK` to `--accept-files`: whole and hashed;
  `--decline-files`; no answer (60 s, `noAnswer`); the device's cancel mid-file.
- **H7** The drop's dry run with `SILL_TEST_POINTER_PATH` and `SILL_TEST_FILES_TOPMOST`: "Test drop: would drop 1
  file at 756,474 onto window 42 (Finder, layer 0)"; the Dock's layer, a covering window, the letterbox and a
  locked Mac each save, with their reason.
- **H8** `Scripts/pacing/` cases `files-up` and `files-down` (the harness's host links FileHub; `device.py
  --upload`, `--download`) at 5 and 50 Mbit/s through `bottleneck.py`, each against the same case without a
  transfer: frame age p95 within 50 ms of it, the pongs (a tap's stand-in) within the window's time plus 50 ms, no
  LinkJudge "behind" from a transfer alone at 50 Mbit/s, no frame withheld at home.

### 12.3 Harness photos, the touch rig, the app's previews

- **S1** `Scripts/harness-photos.sh` on the agents' simulators: the Files rows (`-SillSettings 1 -SillSettingsScroll
  files -SillSettingsCase files|filesUnpaired|filesOff|filesOld|filesLocked`) and the chip in each state (`-SillFiles
  sending|saved|dropped|notTaken|refused|offer|receiving|received|photos`) on the Duo's four sizes, an iPad's two and
  an iPhone's, at the default text size and accessibility extra large; main's screens that should not change, pixel
  for pixel.
- **S2** `Tests/touchrig` `compare.py --all` with the drop interaction on the picture: every stroke main's.
- **S3** The bare app's `-SillRenderPreviews`: Settings › General's files section (on, off, another folder), the menu
  with a device sending and with one receiving.
- Live runs of the app against a loopback host (the pickers by `-SillFilesScript '<t> send PATH | drop X,Y PATH |
  get | accept | decline | cancel'`, loopback and test hosts only, as `-SillInputScript`) where the simulator rules of
  the day allow them; otherwise they move to the P list.

### 12.4 What only Noah can try

Sill.app from the branch, release-signed with the embedded profile so its grants hold; the device's Debug build;
Xcode's console's `files:` lines and `tail -F ~/Library/Logs/Sill/Sill.log`.

1. Settings › This iPad shows the Files rows and footnote; Sill's Settings › General shows Share files with devices
   on and Downloads › Sill.
2. Send Files: a PDF from Files: the chip runs and says "Saved in Downloads › Sill on ‹Mac›."; the file is there;
   Get Info shows where it came from; the menu's card says Received with Show in Finder; macOS asked nothing.
3. Send Photos: a HEIC photo and a one-minute 4K video: both arrive as originals; while the video goes, tap and
   scroll on the stream: no lag you notice.
4. The iPad beside Files: drag a file onto a Mail message being written: attached ("Dropped into Mail"); onto a
   Finder window: it moves there; onto the black bars: saved only; with Drop Files Into Apps off: saved only.
5. The Desktop streaming: drop onto an app's window (dropped), onto the Dock (saved, "the Dock was there").
6. In Files, Share › Sill: "Send ‹name› to ‹Mac›?", Send: saved. In Photos' share sheet, note whether Sill is there.
7. Get Files from ‹Mac›…: the Open panel is the picture; choose two files in Documents; they arrive in Files › On My
   iPad › Sill › From ‹Mac›; the picture goes back; macOS asked nothing (say if it asked about Documents).
8. Save to Photos on a received photo: the add-only question, then "Saved to Photos."; the switch for automatic.
9. Sill's menu › Send Files to ‹device›…: the device asks; Accept: arrives; Decline: the card says declined.
10. Drag a file from Finder onto Sill's menu bar icon: the device asks, then receives.
11. Lock the Mac during a transfer: it stops on both ends with the words; the rows hide; after the unlock nothing
    resumes by itself.
12. A second iPad, not paired, with Require pairing off: its rows are disabled with the pairing words.
13. Away from home through Tailscale: a 200 MB video both ways; the picture stays usable; note the times.
14. Swipe home mid-transfer: it stops after about 30 s with "Sending stopped…"; with Picture in Picture on, it
    finishes.
15. Plug the cable in during a transfer: the session moves only after it ends.
16. A 90-character Japanese name, an emoji name, a name with "/": the Mac's names, readable and whole.
17. A USB stick as the folder, nearly full: `noRoom` before any byte moves.
18. Quit Sill on the Mac mid-transfer, open it again: nothing partial is left anywhere.
19. VoiceOver: the rows, the chip, Accept and Decline, the drop's description on the picture.
20. The iPhone upright: Send Photos, the chip's place, Get Files.
21. Two devices sending at once, then receiving at once.
22. Sill's Accessibility switched off in System Settings for a moment: a drop saves with "‹Mac› can’t click for
    Sill yet" (then switch it on again).

## 13. Docs, site and App Store words (for the release that ships it: 0.7.0 unless Noah names another)

- `docs/files-plan.md` (this plan, with Results and Progress as the work goes); `docs/steps/2026-11-18-files.md`;
  CLAUDE.md's Layout (the new files) and floor (§5.5); `docs/DEVELOPMENT.md`'s "Files" section (the hooks, the
  client's flags, the gates).
- `site/support.html` "Files and photos" (how to send, drop, share, get; where they land on each; the Mac's switch
  and folder; quarantine; why a locked Mac refuses), `site/privacy.html` (files go directly between your device and
  your Mac, encrypted, never through a server; Sill reads only what you pick, drop or share; add-only Photos access;
  names never logged), `site/index.html`'s feature line, the README's features, each between `<!-- Files` markers
  until the release.
- App Store: What's New and a description line; App Privacy stays Data Not Collected; the review notes say why
  Sill opens any file type and asks to add to Photos.

## 14. The order of commits

1. Merge origin/main into #189's branch (nine files conflict; main's code kept, #189's list key left out so its path
   is unreachable). Then delete #189's host and device code in one commit that says so.
2. Spike S0 (the Open panel's owner; no Screen Recording asked) and the kind numbers of the allocation (34 and 49).
3. StreamProtocol: `Files.swift`, `FilePolicy.swift`, the fields; C1 and C4.
4. The Mac's receiving: FileStore (C2), FileHub, the server's routes and gate, LockPolicy, the coordinator, the
   switch and folder, `--no-files`, the hooks, the App Nap hold; H2–H5.
5. The device's sending: DeviceFiles (C3), the rows (after `settings-pane` lands, or placed in today's panel and
   moved with it), the pickers, the chip, the share sheet; S1.
6. The drop: FileDropPolicy, FileDrop, InputInjector's hold; PictureDrop; H7, S2.
7. The Mac's sending: the send path, the pick (FilePick, the catalog's exception), the menu, the icon; the device's
   receiving and Photos; H6, S3.
8. H8 and the windows tuned by it; docs, site and CLAUDE.md.
9. An adversarial review and a security review, each finding reproduced, then fixed one commit a theme; Noah's P
   list; the merge on his word.

Two pull requests if Noah prefers smaller ones: 1–6 (device to Mac) and 7–9 (Mac to device).

## 15. Risks

- **A tap behind an upload, a frame behind a download**: bounded by the window (§6.3), not removed; H8 measures it.
  If it is not good enough away from home, a transfer could pause while the person's input flows (one more input to
  `FileFlow`).
- **The kernel's send buffer** absorbs what Sill hands it; only the receiver's acknowledgements bound what sits ahead
  of a frame, which is why both directions use them.
- **The Open panel in the stream** rests on spike S0; the fallback (the Desktop of its display) changes what every
  connected device sees while it is up.
- **The synthetic drag** is #66's and #189's technique, not an API: an app that ignores a posted drag, a full-screen
  Space, Stage Manager or Sill's own display may not take it. The fallback is always a saved file, said as such.
- **TCC** behaviours not documented (§16) could add a prompt on the Mac that a person away from it cannot answer.
- **iOS ends a transfer** when Sill leaves the screen (about 30 s), unless Picture in Picture shows.
- **App Review**: a document type for `public.item`, a Documents folder in Files, add-only Photos access.
- **Numbers and places shared with other work**: kind 49 with the five other workstreams; the Files folder and
  Info.plist with recording (#284, #303); the rows with the whole-screen pane; #66 with kind 34.
- **Size**: both directions, photos, the drop and the share sheet is the largest of the six workstreams on the
  device; the two-PR split above keeps review sizes sane.

## 16. What reading could not settle

Whether #189 compiles once its conflicts are resolved; a folder Sill made in Downloads at an earlier launch and the
name checks there; the Desktop's and Documents' folder rules (only the Downloads page was read); which process owns
a non-sandboxed NSOpenPanel's window, whether browsing ~/Documents in it asks, and whether ScreenCaptureKit captures
it as a desktop-independent window; whether a Services invocation counts as consent; `loadFileRepresentation` for a
supertype; Sill in the Photos app's share sheet; Sill.app's file-descriptor limit (D4's number); a NUL in a name
through FileManager (C1 covers the cleaned name); a posted drag on Sill's own display and in full-screen Spaces; the
exact words of Apple's disk-space reason codes (none is used, §17 Q12); how a clear view over the status item's
button takes drags on macOS 27; the numbers of §6.3's windows, which H8 sets.

## 17. Open decisions for Noah

Each recommendation is what the work proceeds with if Noah says nothing.

1. **The Mac's switch, on or off by default?** (a) On; (b) off until turned on, as the workflow's conventions put
   it for new features (Picture in Picture is off by default). *Recommendation: on.* Every transfer is a person's
   act on a paired device that can already type anything on the Mac, and off hides the feature from everyone who
   never opens the Mac's Settings; the clipboard and Send Audio are on by default too.
2. **Where files land on the Mac?** (a) Downloads › Sill; (b) Downloads itself, as AirDrop; (c) Downloads › From
   ‹device› (#189's); a chosen folder is possible with any. *Recommendation: (a)*: Sill's own folder needs no
   prompt, even for name checks, and keeps devices' files together.
3. **A drop on the picture drops into the app under the finger?** (a) Yes, with Drop Files Into Apps on by default
   and a saved file whenever the drop cannot happen; (b) never: a drop on the picture only saves; (c) always drop
   (#189's). *Recommendation: (a).*
4. **How the Mac's files reach the device in this version?** (a) The device's Get Files (the Mac's Open panel in the
   stream), the menu's Send Files to ‹device›… and drops on the menu bar icon; (b) also Finder's Services item now;
   (c) also Copy in Finder, then Get Copied Files on the device. *Recommendation: (a)*, the paths Apple documents as
   consent; (b) and (c) after a device test of their prompts.
5. **Does the device ask before taking files the Mac sends?** (a) Ask (the switch on), never for its own Get Files;
   (b) never ask; (c) always ask. *Recommendation: (a).*
6. **Photos and videos from the Mac?** (a) In Files, with Save to Photos one tap, and the automatic switch off by
   default; (b) straight to Photos. *Recommendation: (a)*: no Photos question until the person wants one.
7. **Away from home?** (a) Allowed, with the smaller window; (b) only at home; (c) a Mac switch "Also away from home".
   *Recommendation: (a)*: getting a file from home is the case Sill serves that AirDrop does not.
8. **Limits?** (a) 500 files and 100 GB a transfer, and 2 GB left free on the Mac; (b) #189's 512 MiB; (c) free space
   only. *Recommendation: (a).*
9. **Resume after a lost connection?** (a) No: the session's own moves wait, a loss ends the transfer; (b) resume
   from the last acknowledged byte on the next connection, partials kept 10 minutes. *Recommendation: (a)* for this
   version.
10. **Sill in the share sheet?** (a) Document types (Sill among the share sheet's apps for a file); (b) a Share
    Extension (a second target, an app group, its own manifest and profile); (c) neither. *Recommendation: (a).*
11. **The wire?** (a) Kind 34 as #66's `FileChunk` and a new kind (49 in the allocation); (b) two new kinds, leaving #66's
    numbers entirely alone; (c) #66's 34–37 as they are (they cannot answer, pace or cancel). *Recommendation:
    (a).*
12. **Ask the device's free space before receiving?** (a) No: the write's own failure says so, and the privacy
    manifest gains nothing; (b) yes, with the disk-space category and its reason, shared with recording if #284
    declares it. *Recommendation: (a)*, unless recording adds the category anyway.
13. **A macOS notification when files arrive?** (a) No: the menu's card and the log; (b) yes, with the notification
    permission. *Recommendation: (a).*
14. **Folders?** (a) Not in this version; (b) zipped with `ditto` as #66 does. *Recommendation: (a).*
15. **Build on #189 or redo?** (a) Build on it: addhumal's commits kept for credit and kind 34; (b) a fresh branch
    with him as co-author. *Recommendation: (a)*, as #355 did with #173.

## Progress

The first building run (2026-11-18), draft pull request #391:

- Done: §14's step 1 (main merged into #189, #189's host and device code removed, kind 34's layout kept); step 3
  (StreamProtocol: `Files.swift`, `FilePolicy.swift` with FilePolicy, FileNames, FileFlow, the two ledgers FileReceiver
  and FileSender, FilesCopy; `WindowList.files`, `Hello.files`; checks `files` and the kind tables); step 4's core
  (FileStore and its check `file-store`; FileHub on `sill.files`; StreamServer's route of kinds 34 and 49 with a
  backlog bound and `sendFileMessage`; LockPolicy's `files` request, refusal, gate and list; the coordinator's context,
  the list's `files`, the stops at a lock, a cut-off, a leave and a quit; DisplayWake's `files`; HostConfig's
  `shareFiles` and `filesFolder`; Sill.app's switch in Settings › General; the CLI's `--no-files`; the TEST ONLY
  `SILL_TEST_FILES_DIR`, `_LOG` and `_FREE`; sillclient.py's `--send-file`, `--cancel-files`, `--raw49`, `--raw34`,
  `--files-window` and `--expect-files`); Settings › General's Other Folder… with a chosen folder checked
  (`FileStore.refusal(forFolder:)`); the App Nap hold while a transfer runs (`fileTransfers` in the snapshot);
  the gates' H2 (`Scripts/files-check/live.py OUT h2 --base=MAIN_SILLHOST`).
- Taken beyond the plan: a reason `cancelled` for a person's own stop (the plan named none); a refusal or a cancel of
  kind 49 passes the lock's gate (`LockPolicy.passesLocked`), so a device hears at once why its transfer stopped; the
  Mac's answer judges the rate before `busy` and reads the free space last; the device's answer checks `busy`, the
  count and the size before `asked`; the server pauses a device's reads while more than 2 MiB of its files wait for
  the hub.
- Next: the gates H2 to H5 recorded in the step file; then step 5 (the device's sending: DeviceFiles, the uplink
  ledger in SessionLink, the rows, the pickers, the chip), step 6 (the drop), and the second pull request (Mac to
  device).
