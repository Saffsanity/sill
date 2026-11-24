**A home device that reads slower than the stream no longer builds an endless backlog in Sill for Mac (2026-11-24, branch `home-backlog` from main at 644f03b, issue #359).** Noah, 2026-11-24, on the analysis of a reporter's log: "Post 359, fix the backlog".

## What a reporter's log (issue #359) showed

The iPad app running on a Mac held five connections to Sill for Mac at once (1710×1106 Desktop, 60 fps, 15 Mbit/s, at
home), each on a link that carried about 4 to 9 Mbit/s. For 1 h 49 min Sill for Mac queued video for each: the one
connection that reported stats fell 0.42 s further behind every second, to 45 minutes; `net.sent == net.dropped` in
every [1s] line (770,570 each over 107 minutes, five times the 310,008 frames encoded); when the connections stalled,
LinkJudge said 2,516.1, 3,524.6, 2,625.7 and 3,502.2 MB were waiting, and Activity Monitor showed Sill at 17.64 GB on a
16 GB Mac; then 258 "Client not draining … dropping" lines in 4 s. The analysis is
`sill-handoff/next/triage-1124/gh-359-analysis.md`; each line of it was checked against the code here, and it holds.

## Why (StreamServer.swift at main, unchanged since 0.6.2)

- At home a delta was dropped once more than two messages waited, and every such drop asked the encoder for a keyframe
  at once, with no spacing. The keyframe that came was always sent, whatever waited (only deltas were ever dropped at
  home), and so were its parameter sets. On a link slower than the stream that loop never ends: every other frame is a
  forced keyframe, sent to every device, while every delta is dropped (sent == dropped, exactly the log), and the
  keyframes pile up in Network.framework's own queue, in Sill's memory.
- The encoder is shared: one slow connection's requests made the stream keyframes for every device.
- The drain backstop (no frame taken for 4 s) restarted its clock at every frame taken ("Progress: a slow but live
  peer…"), so a connection that took a frame now and then was never dropped, however much waited. It ran only as a
  frame was sent, and printed its line and cancelled again at every frame until the cancel was through.
- Away from home all of this was bounded since PR #34 (`paceRemote`: a byte budget, keyframes withheld over it,
  requests made once the queue drained and spaced 2 s). Home was left without it on purpose then: a cable or good
  Wi-Fi was assumed, where a drop is a passing jam and asking at once costs three frames.

## The rule (FramePacing, pure; StreamServer does what it says)

Both routes are read from one file, `Sources/SillHost/FramePacing.swift`; its header says what they share and where they
differ. In short:
- **(a) At home a keyframe is withheld while the queue is over a budget, and asked for again once it has drained.** The
  home budget is time, not bytes: a frame that has waited longer than `homeLate` (1 s) in its connection is late, and so
  is every frame behind it. The keyframe a device waits for goes with its parameter sets while not late (its first
  since it was admitted or the stream changed goes at once, as before); a late one is withheld, and one is asked for
  again once 16 KB or less waits (`idleBytes`), so that it leads the queue.
- **(b) Requests caused by a device's backlog are spaced.** A loss at home after 2 s without one (`homeCalmAfter`) is a
  one-off and asks at once, as it always did. Any other request waits for the drain and for the spacing: 2 s after the
  last such request for every home device together, and beside a device at home that is not losing frames 4 s after
  it and after the last keyframe of any kind (the encoder's own interval). Away keeps its own clock, unchanged. The
  sweep asks on the same terms once a second, for a window that went still after a loss.
- **(c) A hard ceiling for any device.** A device whose connection holds more than 64 MiB (at any time), or whose oldest
  frame not taken has waited more than 10 s at home or 30 s away (after the 8 s and 15 s graces), is dropped: once, one
  line ("Client too far behind (… MB queued for it, its oldest frame waiting … s), dropping: …"), its connection
  cancelled, nothing more queued for it. The drain backstop stays as it was (4 s / 15 s), now looked at before every
  frame and at the sweep, and also once. What the device sees is the old drop: the connection closes and it
  reconnects as it always did; no new state, nothing on the wire.
- **(d) The late frame is dropped, not queued.** At home a frame that comes while the queue is late is dropped, keyframe
  or not (the device then waits for a keyframe); a delta is still dropped while more than two messages wait.

Away is `paceRemote` moved word for word (its doc comment too); the check compares it with the old one on 300,000
random steps and on the model's links, and the harness's away gates ran again.

## The numbers, with their reasons (for Noah to confirm)

| Number | Value | Why |
|---|---|---|
| `homeLate` | 1 s | A link that carries the stream takes each message within milliseconds; Wi-Fi's dozes and AWDL's off-channel spells hold one for 0.1–0.3 s (2026-09-22's trackpad stutter). A frame a second late is a link that cannot carry the stream. |
| `homeCalmAfter` | 2 s | A loss after 2 s without one is a one-off (asked for at once, as before); sooner, the link cannot carry the stream. The same 2 s as the spacing. |
| Spacing at home | 2 s; 4 s beside a calm device at home and since the last keyframe | The away rule's numbers (PR #34): a slow link gives a device that keeps up no more keyframes than the encoder's own interval (4 s). |
| `idleBytes` | 16 KB | Away's `remoteIdleBytes`, now shared: only control messages wait, so the keyframe asked for leads the queue. |
| `ceilingBytes` | 64 MiB, any device | Twice the largest frame a device takes (`StreamMessage.maxFramePayload`, 32 MiB); the rules keep a queue to a few MB. |
| `ceilingWait` | 10 s at home, 30 s away | Home: ten times `homeLate`, past the 4 s drain backstop. Away: twice the 15 s backstop, above the ~24 s remote pacing can hold on a 0.3 Mbit/s link (issue #427). |
| Unchanged | delta at 3 messages; 4 s / 8 s and 15 s / 15 s backstops; away's 256 KB, 128 KB, 512 KB | As before. |

## What else the five connections show (not fixed here)

- **Why one device held five.** The iPad app makes a scene per window (`WindowGroup` in iOSClient/SillApp.swift), each
  with its own `ContentView` and `@StateObject` StreamClient (ContentView.swift), and its scene manifest is generated
  (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation`), so several windows are allowed; on a Mac each window is one,
  and macOS reopens an app's windows at launch, each dialing the last Mac. Five connections within seconds of each
  launch in the log fit that. Not checked on a Mac (none here runs the iPad app); the reporter was asked how many Sill
  windows were open.
- **Refuse or fold a second connection from the same device (Noah's call; nothing built).** The plain home door sees
  no key, so only the TLS doors (Sill.app's home door, the remote door) can tell two connections from one device apart,
  by its paired key.
  1. Leave it: every window is a full device, as now. After this branch each is bounded; the link still carries one
     copy of the stream for each window.
  2. Refuse a second session from a key that has one: the second window is told goodbye (a reason an older device shows
     as a notice) and shows the connect screen; the first keeps streaming.
  3. Fold: the newest session from a key replaces the older one, which is told goodbye; the window used last streams.
  4. On the device: one stream for the whole app (the scenes share one StreamClient, or a window not in front lets go
     of its connection). Device-side only; needs the reporter's answer.
- **Copies or shared bytes.** `broadcast` serialises a frame once and hands the same `Data` to every connection, but the
  reporter's own numbers say each connection's queue held bytes of its own: the four stalled connections had 12,168.6 MB
  waiting between them, the fifth was further behind still, and Activity Monitor showed 17.64 GB, the sum, not the
  largest queue (about 3.5 GB) that shared buffers would have left. Where the copy is made is not known (likely
  Network.framework's Swift `send(content: Data?)`, which turns each `Data` into a dispatch data of its own); NWConnection
  offers no other way to hand it bytes, so sharing one buffer is not a small change. With this branch each queue stays at
  a few megabytes, so the copies cost little. The harness's five connections against one on main measure it: MEASURED.

## Verified

(MEASURED: filled in below as the holds ran.)

## Not verified, and why

(See the pull request.)
