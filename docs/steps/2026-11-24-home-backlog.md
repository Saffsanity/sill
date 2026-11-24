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
  largest queue (about 3.5 GB) that shared buffers would have left. The harness measured it on main: five connections
  with 57.2 MB queued each (LinkJudge's own count, 286 MB together) held 383 MB of resident memory, 1.3 times the sum;
  one connection with 86.7 MB queued held about 1.9 times its queue. Both fit one copy per connection (Network.framework's
  Swift `send(content: Data?)` turns each `Data` into a dispatch data of its own) plus the serialised frame itself, which
  each send's completion keeps alive until the frame is taken because it reads `data.count` there. Capturing the size
  instead would free that one at once, a one-line change not made here (it saves at most one queue's worth, and the
  queues are now a few hundred kilobytes); sharing one buffer between connections is not possible through NWConnection,
  which takes only `Data`.

## Verified (2026-11-25, two holds at be2344a7, main then 22ab5a3e; CI at 5e7b082c)

The disk sat under the 25 GB floor from 18:40 to 01:46 (24.1–24.9 GiB, once 0.2 GiB while other agents built), so
nothing was compiled here until then; the draft pull request went up at 00:57 so CI could build it meanwhile.

- **CI** (run 45469766779, 5e7b082c): `swift build -c release`, `Tests/checks/run-all.sh` (frame-pacing: 102 checks),
  the iOS app for the simulator, the CLI's steps: all green; no warning from FramePacing.swift or StreamServer.swift.
- **Hold 1** (01:46–01:59): `swift build -c release` in 61 s (only CaptureProbe's old warning); `Tests/checks/frame-pacing`,
  102 checks; its 51 mutants, 51 caught (276 s; each by a case of its own rule, none by a crash); the pacing harness's
  home cases, main's StreamServer.swift (644f03b8) against this one, each host under a minute on 127.0.0.1, memory
  stopped at 400 MB: every gate passed (runs in `.build/pacing/runs/20261125-014745`).
- **Hold 2** (02:00–02:42): H2, main's CLI (22ab5a3e, from `git archive`) against this one in the same hold, both
  synthetic hosts on 127.0.0.1 (lsof checked): idle 45 s, 9 lines each, identical masked; a Desktop client for 20 s, 35
  lines each, the other lines identical masked and the [1s] lines naming the same statistics (cap.complete,
  cursor.shape, disp.wakeDry, enc.mailboxDrop, enc.out, net.sent, net.tick). The harness's 14 away cases, main against
  this one, capped at 53 s (relay2 runs 90 s, dip 60 s, stillend and linkstill 55 s as written): every gate passed, and
  each case's fps the same within 0.6 (real24 59.3/59.4, ext120 120.0/120.0, dip back at 45 ms after 6.0 s on both,
  blackhole dropped for its silence on both). `Tests/checks/run-all.sh`: 79 of 79.

The reproduction (homeslow: 100 KB keyframes, 25 KB deltas at 60 fps, a home client on a 6 Mbit/s link, the path dead
from 35 s; the host's resident memory by `ps -o rss`, the device's worst frame age of that second):

| s after connecting | main: memory | main: frame age | this branch: memory | this branch: frame age |
|---|---|---|---|---|
| 5 | 34.3 MB | 3.6 s | 13.3 MB | 0.96 s |
| 10 | 64.2 MB | 7.4 s | 13.4 MB | 1.5 s |
| 20 | 111.8 MB | 14.9 s | 13.5 MB | 1.6 s |
| 30 | 164.2 MB | 22.5 s | 13.5 MB | 1.6 s |
| 34 | 177.6 MB | 25.5 s | 13.5 MB | 1.8 s |
| queued when the path died (LinkJudge) | 86.7 MB | | 163 kB | |

Main: 30 frames sent and 30 dropped every second (the reporter's sent == dropped), 7–8 keyframes a second at the device,
5.6 fps shown, 0.75 s further behind every second. This branch: 23.4 fps, 30 keyframes a minute, at most one frame
dropped a second (the rest withheld while it waits), one "dropping" line when the path died.

Five connections (homefive, each on its own 6 Mbit/s, the path dead from 22 s): main grew from 82.5 MB at 5 s to 310.8 MB
at 20 s and was stopped at 404 MB, every connection 14.9 s behind at 20 s, 150 sent and 150 dropped a second; this
branch 17.8–19.4 MB throughout, every connection 0.7–1.9 s behind, about 28 fps and 30 keyframes a minute each.

A stall (homestall: 250 KB keyframes, 31 KB deltas at 60 fps on 50 Mbit/s, 1.6 s with nothing from 12 s): main was at 60
fps and 8 ms before it and never recovered after it (30 sent and 30 dropped a second, 25 keyframes a second at the
device, 1.4 s behind at 15 s and 3.7 s at 29 s, memory 14 → 112 MB); this branch was back at 8 ms and 60 fps 2.4 s after
the stall, its memory flat. The same in the check's model: 1,800 keyframes a minute after one stall on main, 15 here.

Links that carry the stream, untouched: home (Low on 20 Mbit/s), homecable (Pro · Retina on 400 Mbit/s) and homeext
(Extreme at 120 fps on 600 Mbit/s): the same statistics named, and the same totals within a frame (net.sent 1,776 and
1,775, 1,778 and 1,778, 2,955 and 2,957; net.dropped 2 and 1, 0 and 0, 2 and 2), 60.0/59.9, 60.1/60.0 and 120.0/119.9 fps.

## Not verified, and why

- **A real device or a real slow link.** No iPhone or iPad is reachable here, a Mac running the iPad app neither, and
  the hardware encoder is off limits: everything above is the harness's fake encoder on loopback and the check's
  model. The real encoder squeezes keyframes under its rate limit when they come every other frame (the reporter's
  were about 50 KB), which moves the numbers, not the shape.
- **The kernel's send buffer on a real link.** On loopback the path holds about 1 MB that Sill cannot see; on Wi-Fi
  macOS may let it grow to 4 MB (`net.inet.tcp.autosndbufmax`), about 5 s at 6 Mbit/s. The model with a 4 MB buffer
  settles at 5.7 s behind (bounded, where main grows without end). Lowering the quality, which the link's callout
  already suggests, is the cure there; Network.framework offers no way to cap that buffer.
- **The flood of "not draining" lines** (258 in 4 s in the log) did not reproduce on loopback: main's cancel went
  through within a frame with 57–87 MB queued. One line per drop is by construction here (`evicted`); this branch
  printed exactly one per connection in homeslow and homefive.
- **Sill.app's TLS home door and the USB cable**: the same home rule (every `.home` route), not run (agents never run
  Sill.app).
- **The five connections' cause** (several windows of the iPad app on a Mac): not checked on a Mac.
