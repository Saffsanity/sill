# Away from home: pacing, the away quality, the link, coming home — the plan

2026-09-25. It stands alone: the implementer needs no other design document. Written from a
read-only survey of origin/main at ba91136 ("Merge pull request #13", remote access) and of PR
#12's branch `follow-best-path` at 8e1e4e3 (based on 76366e8, before #13; its merge with #13 was
under way in `/Users/noah/Downloads/winstream-ipad-settings` while this was written, with conflicts
in CLAUDE.md, DiscoveryPolicy.swift and StreamClient.swift). Line numbers are at ba91136 unless
marked "(PR #12)", which means 8e1e4e3. Nothing was built or started for this plan: no host, no
app, no simulator, and never the Mac's video encoder.

**Since then (the critique, 2026-09-25 evening).** origin/main has moved to cea195c: PR #11
(encoder recovery) merged at b50e224, and PR #12 at cea195c after its merge with #13 (f863c74).
The line numbers above stay; re-read each merged file before editing it. StreamServer.swift is
unchanged at cea195c (md5 54a77389), so the diff still applies (`git apply --check`). The critique
ran only the investigation's encoder-free harness, on the proposed file and on ba91136's; its runs
are in the session's scratch folder `…/scratchpad/remote-bundle-plan/critic/runs/`.

The evidence is the investigation of Noah's hotspot session of 2026-09-25 (Sill.log 13:55–14:56),
its encoder-free harness and an independent verification of both (workflow wfwhu0q5v). The
harness, the proposed diff (`remote-pacing.diff`, +76/−19) and every run are in that session's
scratch folder `…/scratchpad/remote-starvation/`; step 1 brings the harness into the repository as
`Scripts/pacing/`. The diff applies cleanly to ba91136 (`git apply --check`), whose
StreamServer.swift is byte for byte cb0ec55's (md5 54a77389), the file the investigation read.

**Noah's decisions (2026-09-25),** from that session:
1. Adopt the pacing fix for remote clients (a proven keyframe livelock).
2. Away sessions start on Low · Standard, without saving over the home quality.
3. The host reports how each device's link keeps up, with a one-tap suggestion on the device.
4. A remote session moves home when the home network lists the Mac.

**Reading of them.**
- **Item 1** corrects shipped behaviour and stands alone: it can land first, as its own PR.
- **Item 2** ends "quality is host-wide and saved" (remote-access-plan.md §7.11) for two of the
  knobs. There are two qualities now: the home one (what the Mac's menu sets, saved as today) and
  the away one (saved under keys of its own, set by a device away or in the Mac's Settings). Only
  Quality and Resolution split. The frame rate limit, Prioritize Encoding Speed, the virtual
  display and Direct Wireless stay one setting each.
- **Item 3** is information on both screens, never a decision taken for the user. Automatic
  step-down is open question 2, off by default.
- **Item 4** reuses the move from AWDL to the network (PR #6) as PR #12 generalises it (chained
  fences, hold and adopt, `upWait`), so the branch for items 2–4 starts from a main that has PR
  #12: any main since cea195c.

---

## Decision

### What happened on the hotspot

- **14:00:26–14:02:39,** the iPad on the iPhone's hotspot through Tailscale, Low (4 Mbps) ·
  Standard: 56–58 fps, rtt 63–81 ms, nothing dropped.
- **14:02:40,** the iPad back on home Wi‑Fi. Tailscale took the LAN path (rtt 7–12 ms) and the
  session stayed on the remote door. At 14:02:55.8 the iPad picked Extreme and at 14:02:56.9
  Retina: "Settings from iPad (iPad14,1): bitrate 4 → 150 Mbps per 60 fps". The Mac saved both,
  as the remote plan intended, and kept them across the 14:10:26 relaunch. (The investigation
  called 150 Mbps "Pro"; it is Extreme, HostSettings.swift:174-176.)
- **14:13–14:36,** five sessions on the hotspot at Extreme · Retina. 1,383 one-second lines:
  enc.out 78,229, net.sent 1,914 (2.4 %), net.dropped 620, net.waitKey 75,695. The iPad got
  1.5–1.9 fps. 567 of the 615 gaps between drops were exactly 2 s, the forced-keyframe spacing,
  and 425 of the 618 drop seconds sent exactly 3 frames. The per-second median rtt stayed at the
  hotspot's 54–89 ms: the link sat idle between keyframes.
- **14:36:51,** back to Low · Standard: 44 fps the next second, 59 two seconds later, then 55–58
  fps, frame age 39–46 ms, rtt 62–88 ms, nothing dropped.
- **After 14:41** (the verifier's reading of the rest of the log): Pro (40 Mbps) · Retina flowed at
  56–58 fps for 3–4 s at a time, each run ending about one encoder keyframe interval later in the
  same 2 s loop (7–10 fps). Efficient (8 Mbps) · Retina sent 49 % of its frames (29 fps). The
  collapse grows with the keyframe's size, not with the average rate.
- **The session ends** (14:24:36, 14:29:27, 14:30:39, and the eviction "Client silent for 8 s,
  dropping" at 14:34:16) were the path stalling both ways, not the loop.

**The livelock** (StreamServer.swift):
1. `inflight` counts messages, not bytes (:34). `send` adds one (:978); only `.contentProcessed`
   takes it away (:984-986).
2. `paceRemote` drops any frame while more than two messages are unacknowledged (:927-931). A
   Retina keyframe (0.3–0.7 MB for that desktop, 1–2 MB for a busy one) is not taken until the
   hotspot has carried most of it, about 0.5 s against 17 ms per frame: the one or two deltas
   right behind it get through, and the next is dropped.
3. Every later delta references the dropped one, so all are withheld (`net.waitKey`, :906-908). A
   new keyframe is asked for only when `inflight <= 2` and 2 s after the last request (:910,
   `remoteKeyframeDue` :953-959). That keyframe blocks its own followers the same way: one
   keyframe and one or two deltas every 2 s, for ever.
4. It needs only a keyframe that takes longer than about two frame intervals to be taken. The same
   Extreme stream ran at 57 fps with nothing dropped over Tailscale's LAN path (14:02:57–14:07:31).

The verifier reproduced it with ba91136's file, unmodified, in the encoder-free harness: 2.5 MB
keyframes and 20 KB deltas over 32 Mbps (46 % average load) give "net.dropped 1 net.sent 3
net.waitKey 56" every 2 s, 1.4 fps. The proposed rule gives 60.1 fps with nothing dropped.

### How the four fit together

| # | What | Host | Device | Mac UI | Wire | Lands |
|---|---|---|---|---|---|---|
| 1 | Remote pacing counts bytes; liveness counts every byte | StreamServer | MessageReader (new) | — | none | PR A, first, on its own |
| 2 | Away sessions run the away quality | HostConfig, DeviceSettings, StreamCoordinator | the panel | Settings › Streaming, the menu | kind 16 `away` | PR B, after PR #12 |
| 3 | The host reports each device's link | StreamServer, LinkJudge (new), StreamCoordinator | the panel's callout, the stream screen's line | the card | kind 16 `link` | PR B |
| 4 | A remote session moves home | — | DiscoveryPolicy, StreamClient | — | none | PR B (needs PR #12's SessionLink) |

- **Items 2 and 3 share one host change:** kind 16 becomes per connection. Today one state is
  broadcast (StreamCoordinator.swift:1363-1368). Each device now gets its own: its own quality
  (item 2) and its own link (item 3).
- **Items 2 and 4 meet at the hand-over.** The home connection registers while the remote one
  still streams, so the Mac restarts once, at the home quality and the device's home rate (the
  first viewport, which the move sends at `.ready`: §5.4, §7.3), before the fence comes down.
- **Item 3's suggestion lands where item 2 says.** Its button is an ordinary kind 17 pick, so
  from away it changes the away quality only.

### Not in this bundle

- Automatic step-down (open question 2; off).
- The encoder's 4 s safety keyframe and its `DataRateLimits` (HEVCEncoder.swift:83, :86) for
  remote-only viewers: an encoder change, untested.
- Cheaper reconnects (the catalog's 119 icon messages ahead of the first keyframe).
- A bound on the kernel's send buffer (ack-based pacing).
- An rtt exception for remote sessions that run over the LAN (open question 1; rejected by
  default).
- Moving a session from home to away. A home connection that dies reconnects remotely, as today.
- A new message kind. Kinds 0–22 stay as they are; 23–25 stay held for the Mac menu bar and 26 for
  the pointer (pointer-visibility-plan.md).

---

## Final plan

### 1. Scope

**In this step:**

1. **Remote pacing by bytes** (host, remote clients only), the investigation's rule unchanged, and
   the harness in the repository (`Scripts/pacing/`).
2. **Liveness by bytes** on the device: payloads read in pieces of at most 256 KB, each piece a
   sign of life (`MessageReader`, new, checked with swiftc).
3. **Two qualities.** `HostConfig` gains the away quality. The host runs it while every connected
   device is away. A device away sets it and never the home one. Sill.app saves it under its own
   keys and shows it in Settings › Streaming.
4. **Kind 16 per connection,** with two optional fields: `away` and `link`.
5. **The link, per device:** fine, behind or stalled, judged by the host from what it withholds,
   with what would fit. While it is behind the device shows a callout with a button, and a line on
   the stream. The Mac's card names both.
6. **The move home:** a remote session moves to the home door once the network has listed the
   same saved Mac for 2 s, through PR #12's fenced hand-over.

**Not in this step:** see "Not in this bundle".

### 2. The design on one page

```
 iPad away ─── TLS (remote door, 7455) ──┐                  iPad at home ─── TCP (home door) ──┐
                                         ▼                                                     ▼
┌────────────────────────────────── StreamServer (sill.net) ───────────────────────────────────┐
│ remote clients: pendingBytes, keyframeInFlight, backlogFloor → paceRemote           (item 1) │
│ every client, each second: sent, withheld, bytes taken → LinkJudge                  (item 3) │
│   onClientLinkChanged(connection, verdict) ───────────────────────────────────┐              │
└───────────────────────────────────────────────────────────────────────────────┼──────────────┘
                                                                                ▼
┌─────────────────────────────── StreamCoordinator (main actor) ───────────────────────────────┐
│ routes → awayWanted: at least one device, and every one of them away                (item 2) │
│ config: the home and the away quality; the pipeline runs one (awayRunning)          (item 2) │
│ kind 16 to each connection: the pair it sets, away {…}, link {…}                (items 2, 3) │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
Sill.app: Settings › Streaming "Away from home"; the menu's Quality subtitle; the card's link
Device:   "Away: Low · Standard"; the link callout and its button; the stream's line;
          MessageReader (item 1); the move home once the network lists the Mac 2 s (item 4)
```

---

### 3. Item 1: remote pacing counts bytes

#### 3.1 The rule, in prose

What a remote client has queued is counted in bytes its connection has not taken yet
(`pendingBytes`). Every message counts: frames, the catalog, thumbnails, pongs, a settings reply.
Ticks do not, since they bypass `send` (StreamServer.swift:147).

- **Behind a keyframe still being taken, the followers go out** until more than `remoteHoldCap`
  (512 KB) waits beyond the keyframe itself. Every delta references that keyframe; dropping them
  for its sake wasted it, and that was the loop.
- **Otherwise a frame is dropped only when the backlog is over both** `remoteBacklogBudget`
  (256 KB) and the floor plus `remoteBacklogSlack` (128 KB). The floor (`backlogFloor`) is what
  the last keyframe left behind it when it was taken, followed down as the backlog shrinks. A
  backlog that shrinks is a link catching up. One that grows past the floor is a stream bigger
  than the link, and only then is a frame dropped.
- **A client that lost a frame waits for a keyframe, as before, but asks for one only once its
  connection has taken everything but control messages** (at most `remoteIdleBytes`, 16 KB,
  waiting). The keyframe then leads the queue instead of queueing behind the backlog that caused
  the drop. The spacing is unchanged: 2 s alone; beside a home client, 4 s since the last request
  and since the last keyframe of any kind.
- **The keyframe it waits for goes out when the backlog fits the budget,** or at once when the
  client has had no keyframe since it was admitted or the stream changed (the first keyframe,
  unchanged).

#### 3.2 The constants, with their reasons

| Constant | Value | Why |
|---|---|---|
| `remoteBacklogBudget` | 256 KB | A backlog that never drops a frame: about a quarter second at 8 Mbps, 30 frames of the Low preset |
| `remoteBacklogSlack` | 128 KB | Growth over what a keyframe left behind that is still noise: a thumbnail pass is 11 small JPEGs |
| `remoteHoldCap` | 512 KB | What may queue behind a keyframe still being taken: about a second of Low's deltas (60 × ~8 KB), what piles up while a large keyframe crosses a hotspot. Past it the stream is more than the link carries |
| `remoteIdleBytes` | 16 KB | A queue this short holds only control messages (pongs, a settings reply): a keyframe asked for now leads it |

All four were tuned on Low-sized frames (the verifier's caveat). Near-capacity cases (§3.7) are
the keyframe's cost, not a bad constant: raising the hold cap to the keyframe's size did no better.

**At the top presets.** An Extreme delta averages 312 KB (150 Mbps per 60 fps, twice that at 120
fps: the same bytes a frame), more than the budget: one delta still waiting when the next frame
comes drops it, and two behind a keyframe reach the hold cap. That happens only while the
kernel's send buffer is full, which a link faster than the stream does not let it be. The critique
ran it in the harness (2 MB keyframes, 312.5 KB deltas): at 120 fps through 600 Mbps with a 1 MB or
a 256 KB queue and through 1,000 Mbps with 512 KB, and at 60 fps through 400 Mbps with 256 KB, the
proposed file sent every frame (0 `net.dropped`, 0 `net.waitKey` after the first keyframe), where
ba91136's dropped 3–11 frames a minute. H3 keeps the case (`ext120`), and P14 runs it on a device:
the harness's host sends over loopback, and a real path's send buffer may stay smaller.

**At the hold cap's edge.** A keyframe that takes about a second to be taken leaves about 512 KB of
Low's deltas behind it, so a case there is bistable. bigkf8 (1.5 MB keyframes, 8 KB deltas, 8 Mbps,
85 % of the link on average) ran at 60 fps with nothing dropped in five of six runs across fix-v3
and the proposed file, a second or two behind; in the sixth (the proposed file, 2026-09-25) one
drop 6 s in set off the 2 s loop for good: 29.6 fps, 27.8 drops a minute, about 3 s behind, where
the base ran at 13.2–24.5 fps. Each forced keyframe is more than the link's spare capacity, so
nothing brings it back out (§3.7, open question 12).

#### 3.3 The host code (`Sources/SillHost/StreamServer.swift`)

`scratchpad/remote-starvation/remote-pacing.diff`, applied as it is:

- **`Client`** (:32-66) gains `pendingBytes`, `keyframeInFlight: (seq: Int, bytes: Int)?`,
  `keyframeSeq` and `backlogFloor`.
- **`send(_:to:isFrame:isKeyframe: = false)`** (:968-997): inside `if remote` only, add the size to
  `pendingBytes` and, for a keyframe, set `keyframeInFlight`. In `.contentProcessed`, subtract the
  size; if the message was that keyframe, clear `keyframeInFlight` and set
  `backlogFloor = pendingBytes`.
- **`paceRemote`** (:904-936):

  ```swift
  client.backlogFloor = min(client.backlogFloor, client.pendingBytes)
  if client.needsKeyframe {
      guard message.isKeyframe else {                                   // net.waitKey, as before
          if client.keyframeWanted, client.pendingBytes <= Self.remoteIdleBytes, remoteKeyframeDue(now) { ask }
          …
      }
      guard client.awaitingFirstKeyframe || client.pendingBytes <= Self.remoteBacklogBudget, let ps = … else {
          net.waitKey; client.keyframeWanted = true; return false       // was inflight <= 2
      }
      send(ps); needsKeyframe = false; awaitingFirstKeyframe = false
  } else {
      let tooMuch = client.keyframeInFlight.map { client.pendingBytes - $0.bytes > Self.remoteHoldCap }
          ?? (client.pendingBytes > max(Self.remoteBacklogBudget, client.backlogFloor + Self.remoteBacklogSlack))
      if tooMuch { net.dropped; needsKeyframe = true; keyframeWanted = true; return false }   // was inflight > 2
  }
  net.sent; send(data, to: client, isFrame: true, isKeyframe: message.isKeyframe)
  ```

- **Threads.** Completions and `paceRemote` share `sill.net` (the remote door starts its
  connections on `server.queue`, RemoteServer.swift:84, :239), so the byte counters need no lock.
- **The doc comment** above `paceRemote` becomes the diff's (the rule in four bullets and the
  2026-09-25 loop), and docs/remote-access-plan.md §4.9(6) gets one line: "Superseded by
  docs/remote-bundle-plan.md §3."

#### 3.4 The device: liveness counts every byte (`iOSClient/MessageReader.swift`, new)

**Today** `readPayload` (StreamClient.swift:1541-1561) asks for the whole payload in one receive,
and `lastReceivedAt` is stamped only when a whole header or payload has arrived (:1526, :1557).
Liveness (:1769-1779) then means "no complete message for max(6 s, 4 × worst rtt)", not "no byte",
which is what remote-access-plan.md §7.6 and §8 specify. A single slow keyframe ends a live
session: in the harness, a 1.6 MB keyframe on 2 Mbps gave "connection silent for 6 s: lost" every
~10 s while 245 kB/s still arrived, and not one frame ever, on either host build.

**The change.** The read loop moves into a small type, so it can be checked on its own like
SessionLink:

```swift
/// Reads the host's messages from one connection: the 14-byte header, then the payload in pieces
/// of at most `piece` bytes, reporting every piece (`onBytes`: liveness counts bytes, not
/// messages). Network and StreamProtocol only: checked with swiftc against a local listener.
final class MessageReader {
    static let piece = 256 * 1024
    enum End { case closed(NWError?), tooBig(StreamHeader) }
    init(connection: NWConnection, stillReads: @escaping () -> Bool, onBytes: @escaping () -> Void,
         onMessage: @escaping (StreamHeader, Data) -> Void, onEnd: @escaping (End) -> Void)
    func start()      // reads the first header; every callback runs on the connection's queue
}
```

- **The header,** as today. `onBytes` after it. A header over the caps (`maxFramePayload` for a
  frame, `maxOtherHostPayload` for anything else) ends with `.tooBig` before any payload is read.
- **The payload:** `receive(minimumIncompleteLength: 1, maximumLength: min(remaining, piece))`
  into a buffer reserved at the announced length. `onBytes` after every piece. The message is
  delivered once complete.
- **EOF or an error** between messages or mid-message ends with `.closed(error)`; a partial
  message is never delivered (today's rule, :1552-1555).
- **`stillReads` false** (the connection was replaced, or a move's fence came back): the loop stops
  without another receive, as `link.reads(c)` stops today's.
- **StreamClient** builds one per session connection:
  - `onBytes` stamps `lastReceivedAt`;
  - `onMessage` calls `deliver(_:_:from:)`;
  - `.tooBig` keeps today's line "closing: the host announced a N-byte message (kind K)" with
    `connectionLost(c, end: .notSill)` and `c.cancel()`;
  - `.closed` keeps "read error: …" with `connectionLost(c, error:)`.

  `readHeader` and `readPayload` go.
- **The move's probe** (`probeMove`, PR #6 and PR #12) keeps its own reader: its 5 s bounds it.
- **pbxproj:** four entries by hand, pair A020/F020. A01E–A01F are taken on the update-notice
  branch, and the pointer plan names A01E.

#### 3.5 What is unchanged

- **The home branch of `broadcast`** (:876-891), byte for byte. The new bookkeeping runs only
  inside `if remote`.
- **Eviction:** the remote silence sweep (8 s, :736-745); the drain backstop (15 s with a 15 s
  grace); the home rule (4 s, 8 s grace).
- **`remoteKeyframeDue`** and its spacing. Forced keyframes only get rarer: the harness went from
  28–32 a minute to 15, the encoder's own. So a home device watching beside a remote one gets
  fewer forced keyframes, never more.
- **The first keyframe** still goes out whatever the queue holds.
- **No new print, no new Stats key.** The CLI opens no remote door without `--remote`
  (SillHostCLI/main.swift:44-60), so its default stdout is identical by construction; H2 checks it
  anyway.
- **The device's wire, rtt, ping cadence and liveness limits.** Only what counts as a sign of life
  changes.

#### 3.6 Log lines

None new, on either side.

#### 3.7 What it does not fix

| Case | Measured (the verifier, the proposed file) | What helps |
|---|---|---|
| Near capacity: 1.5 MB keyframes, 40 KB deltas, 24 Mbps (~93 % load) | 43.8 fps, 20 drops a minute (base 15.1) | Each drop buys a whole keyframe, which pushes the link over. A lower quality: item 3 says so, item 2 starts away low |
| 2 MB keyframes, 20 KB deltas, 16 Mbps | 29.4 and 13.9 fps in the verifier's two runs, 22–30 drops a minute, ~1.2 s lag (base 1.5) | The same |
| bigkf8: 1.5 MB keyframes, 8 KB deltas, 8 Mbps (~85 % load) | Bistable (§3.2): 60 fps, nothing dropped, 1–2 s behind in five runs of six; the 2 s loop at 29.6 fps and ~3 s behind in the sixth (base 13.2–24.5 fps) | The same |
| A stream the link carries only through a standing queue in the kernel's send buffer (bigkf8's good runs: frame age p50 0.8–1.4 s, p95 1.6–1.9 s) | Every frame arrives, a second or two late | Nothing here: the rule sees only what Sill holds, not the socket's queue (a bound on it is not in this bundle), and the link judge (§6) sees nothing withheld. The device's frame age (the host's `client` lines) shows it |
| Extreme · Retina on a 6–10 Mbps hotspot | Its deltas alone may exceed the link | Items 2 and 3 |
| A 12 s dip from 8 to 0.5 Mbps | Lag back to 45 ms about 3 s later than the base (7.1–8.2 s against 4.1–5.0 s, three runs each) | Nothing here. It delivers up to 512 KB of backlog behind a keyframe where the old rule dropped: a deliberate, bounded exception to "Latency beats quality. Drop frames before queuing them.", remote clients only |
| The first seconds of a session on a slow link | The catalog drains ahead of the video; followers of the first keyframe can drop meanwhile | Later: icons after the first keyframe |
| A stream bigger than the link on average (60 KB deltas on 8 Mbps) | 4.6 fps with ~3.5 s lag (fix-v3's run) | No pacing rule fixes it: a lower quality |

---

### 4. Wire (items 2 and 3): two optional fields in kind 16

#### 4.1 The types (`Sources/StreamProtocol/HostSettings.swift`)

```swift
/// Away from home (docs/remote-bundle-plan.md §5): the Mac's two qualities, which one runs, and
/// which one this connection's controls set. From a host with a remote door (Sill.app; SillHost
/// --remote); nil from any other host, which has one quality for every device.
public struct AwayQuality: Codable, Hashable, Sendable {
    /// What runs while any connected device is at home: the Mac menu's Quality and Resolution.
    public var homeBitrate: Int
    public var homeCaptureScale: Double
    /// What runs while every connected device is away (through a VPN or over the internet): Low ·
    /// Standard until a device away, or the Mac's Settings, chooses another.
    public var awayBitrate: Int
    public var awayCaptureScale: Double
    /// The Mac counts this connection as away: its Quality and Resolution picks set the away
    /// quality, and `settings.bitrate` and `settings.captureScale` show it.
    public var thisConnectionAway: Bool
    /// Every connected device is away, so the away quality is the target: the host's `awayWanted`,
    /// never its pipeline's `awayRunning` (a restart may still be taking it, as `settings` can be
    /// ahead of `stream`). The state stays a function of the target and the snapshot (§5.4).
    public var awayRunning: Bool
}

/// How the link to this device keeps up, as the Mac sees from what it withholds
/// (docs/remote-bundle-plan.md §6). Only while it does not keep up.
public struct LinkReport: Codable, Hashable, Sendable {
    /// "behind": the link cannot carry this quality (frames withheld in 3 of the last 5 seconds).
    /// "stalled": for 3 s nothing taken while bytes waited, and nothing heard from the device; the
    /// Mac's card shows it, a device never does (it can only arrive once the path is back). A
    /// string, never an enum: a device reads any other value as keeping up.
    public var state: String
    /// Frames withheld from this device in the second the state was judged (dropped, or skipped
    /// while it waited for a keyframe).
    public var withheldPerSecond: Int
    /// The quality the link could not carry: the running bitrate, per 60 fps.
    public var bitrate: Int
    /// What the link carried in the seconds it was the limit, kilobits per second; nil until three
    /// such seconds were measured.
    public var carriedKbps: Int?
    /// What would fit (§6.2): a lower preset's bitrate, with 1 (Standard) when that is Low and the
    /// stream runs at Retina; or the same bitrate at Standard. Nil bitrate: nothing lower to offer.
    public var suggestedBitrate: Int?
    public var suggestedCaptureScale: Double?
}
```

`HostSettingsState` (:86-111) gains, with `= nil` defaults in its init:

```swift
    /// Away from home: nil from a host without a remote door, and from older hosts.
    public var away: AwayQuality?
    /// This connection's link while it cannot keep up; nil while it does, and from older hosts.
    public var link: LinkReport?
```

`QualityPreset` gains two helpers that both ends and the host's log use:
- `name(forBitrate:)`: "Pro", or "12 Mbps" for a bitrate that is no preset;
- `shortTitle(bitrate:captureScale:)`: "Low · Standard", "Pro · Retina", "12 Mbps · Retina".

`HostSettingsChange` (kind 17) is unchanged. Where a Quality or Resolution pick lands is the
host's decision, by the connection's route.

#### 4.2 What `settings` means now

`settings.bitrate` and `settings.captureScale` are **the quality this connection's controls set**:
the away quality for a connection the Mac counts as away, the home quality for any other. The
other four fields are shared, as today. `stream` still says what runs. So the ledger's rules
(HostSettingsLedger.swift:52-70) hold unchanged for every device, old or new: a pick is answered
with the value it asked for, in the field it asked about. And an older device away shows and sets
the away quality without knowing it.

#### 4.3 Examples

```json
// kind 16 to the iPad away, while it is the only device (away runs):
{"settings":{"maxFPS":120,"bitrate":4000000,"captureScale":1,"prioritizeSpeed":false,"virtualDisplay":false,
 "directWireless":false},"persistent":true,"virtualDisplayAvailable":true,"softwareEncoder":false,
 "stream":{"width":1512,"height":982,"fps":60,"mbps":4,"onVirtualDisplay":false},
 "away":{"homeBitrate":40000000,"homeCaptureScale":2,"awayBitrate":4000000,"awayCaptureScale":1,
         "thisConnectionAway":true,"awayRunning":true}}
// the same connection after it picked Extreme away, on a hotspot that cannot carry it:
 …"link":{"state":"behind","withheldPerSecond":52,"bitrate":150000000,"carriedKbps":6400,
          "suggestedBitrate":4000000,"suggestedCaptureScale":1}
// an iPhone at home beside it: settings.bitrate 40000000 and captureScale 2 (the home quality),
// "away":{…,"thisConnectionAway":false,"awayRunning":false}, and the iPad's "awayRunning" false too.
```

#### 4.4 Compatibility

| Device | Host | Result |
|---|---|---|
| Older (PR #13's, or main's up to cea195c), away | This host | Its Quality and Resolution show the away quality and set it. No "Away:" line. It ignores `link`, and keeps its rtt callout; the Mac's card still names the link. Its liveness still counts whole messages: a keyframe that takes more than 6 s to arrive still ends its session (§3.4), which this host's pacing makes rarer and cannot prevent |
| Older, at home | This host | As today |
| This device | Older host (PR #13's Sill.app, or main's up to cea195c) | No `away`, no `link`: the panel as today (one quality, the rtt callout). The move home works: that host sends a launch ID and a signed kind 18 |
| This device | CLI without `--remote` | `away` nil (no remote door); `link` works; nobody is ever away |
| `sillclient.py` from ba91136 | This host, default path | Identical output: no `away` (no remote door) and no `link` while the link keeps up, so the JSON is byte for byte today's |
| Any | Any | Items 1 and 4 change nothing on the wire |

Kinds 16 and 17 stay compatible both ways; no kind is added.

#### 4.5 Rules for later changes

The rules at the top of HostSettings.swift, applied to both new types: JSON only, new fields
optional, no enums (strings instead), never rename or retype. Its list of "every place a new
setting must go" gains one line: an away variant goes in HostConfig's away knobs, `applyingAway`,
`streamSettings(away:)` and the app's away keys, and never in `HostSettingsChange`.

---

### 5. Item 2: away sessions start on Low · Standard

#### 5.1 The rule

- **A device is away** when the remote door admitted it from a VPN or from the internet:
  `ClientRoute.remote` with origin `.vpn` or `.internet`, the labels "through Tailscale", "through
  your VPN" and "over the internet".
- **A remote-door session from this Mac's own networks or loopback** ("by address") is at home: a
  device dialling the Mac's LAN address through the remote door is in the house.
- **The away quality runs while at least one device is connected and every connected device is
  away.** Any device at home brings the home quality back.
- **With no device connected, the flag keeps its last value.** Nothing streams then. The next
  device to register decides, before its catalog goes out.
- **A device's Quality or Resolution pick** sets the quality its connection controls (§4.2): the
  away quality from away, the home quality from home. The other fields of the same change apply
  as today.
- **The away quality is remembered** as the last choice made away. Sill.app saves it under
  `awayBitrate` and `awayCaptureScale`, never over `bitrate` and `captureScale`. The CLI keeps it
  until it quits.
- **No rtt exception** (open question 1).

#### 5.2 `HostConfig.swift`

- **Two knobs,** required in the init like every other, so the compiler finds each place that
  builds one:

  ```swift
  /// The away quality (docs/remote-bundle-plan.md §5): what streams while every connected device is
  /// away from home. Per 60 fps and 2/1, like `bitrate` and `captureScale`.
  package var awayBitrate: Int
  package var awayCaptureScale: CGFloat
  ```

- **`standard`:** `awayBitrate: 4_000_000` (Low), `awayCaptureScale: 1` (Standard).
- **`validated()`:** the same bounds as the home pair: 1–200 Mbps, and 2 at 1.5 or more, else 1.
- **`changes(to:)`** adds "away bitrate 4 → 15 Mbps per 60 fps" and "away points → Retina".

#### 5.3 `DeviceSettings.swift`

- **`applyingAway(_ change:)`** beside `applying` (:18-27): the change's bitrate and capture scale
  go to `awayBitrate` and `awayCaptureScale`; its other fields as `applying` lays them.
- **`streamSettings(away:)`** replaces `streamSettings`: the away pair in `bitrate` and
  `captureScale` when `away`.
- **`accepted`** (:45-64) is unchanged: the same whitelist from both routes. Its doc comment says
  where an away connection's bitrate and capture scale land.

#### 5.4 `StreamCoordinator.swift`

- **New state:**

  ```swift
  /// Every connected device is away (the target): the away quality should run. Kept while no
  /// device is connected; the next to register decides (`routesChanged`).
  private var awayWanted = false
  /// The away quality runs: the value the last `select` (or `adopt`) took. The pipeline reads it.
  private(set) var awayRunning = false
  /// Each connection whose catalog went out (`sendCatalog`): the ones settings states reach.
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  /// The last state sent to each connection: at connect (`sendCatalog`) and by each publish.
  private var lastPublished: [ObjectIdentifier: HostSettingsState] = [:]
  ```

- **The pipeline reads the effective pair.** `bitrate` becomes
  `awayRunning ? config.awayBitrate : config.bitrate` and `scale` likewise (:36-37). `config`,
  `pendingConfig` and `target` keep their meaning (:16-19, :372): the settings as set, home and
  away pairs both, which is what the Mac's menu and Settings show.
- **`ClientRoute.isAway`** (StreamServer.swift:1003-1019): `.remote` with origin `.vpn` or
  `.internet`.
- **`routesChanged(joined:)`**, called in `onClientConnected` right after `routes[id] = route` and
  before `sendCatalog` (`joined: id`), and in `onClientDisconnected` right after
  `routes[id] = nil`, before its rate check (`joined: nil`) (:160-194):

  ```swift
  if !routes.isEmpty {                                   // nobody connected: keep the flag
      let away = routes.values.allSatisfy(\.isAway)
      if away != awayWanted {
          awayWanted = away
          print(away ? "Away from home: …" : "Home quality again: …")          // §5.9
          if let joined { flipAwaits(joined) }                   // its first viewport, or 1 s
          else { Task { @MainActor in await self.applyPending() } }
      }
  }
  status.update { $0.away = awayWanted && !routes.isEmpty }   // publishes (status.onChange)
  ```

- **One restart for a device that joins or leaves.** A flip on a connect waits for that device's
  first viewport, which carries its rate and which a device sends as soon as it is connected (a
  move home at `.ready`, §7.3): `flipAwaits(id)` notes the connection and a 1 s deadline, and the
  `.viewport` handler from that connection runs `applyPending` once `applyViewportToActiveWindow`
  has (or leaves it to select's defer while switching). The rate and the quality then go in one
  restart. Scheduled at once instead, the flip's Task and the viewport's raced: a 120 Hz home
  device whose viewport landed after `select` took the rate cost a second restart, for the rate
  alone. With no viewport by the deadline (a test client), `applyPending` runs then. A flip on a
  disconnect goes at once; placed before the rate check (:191-192), it rides that check's restart
  when a 120 Hz device left, as the commit takes both.
- **`applyPending`** (:403-409) runs when `pendingConfig != nil || awayWanted != awayRunning`, and so
  does **select's defer** (:757), which today comes back to `applyPending` only for
  `pendingConfig`: a flip that lands mid-switch, after the commit, would otherwise wait for some
  later restart (a device joining while a pick's capture starts would leave the other quality
  running). `restartNeeded(for:away:)` (:415-424) compares the effective pair of `new` under `away`
  with the running one; the rate, the encoder speed and the virtual display as today.
- **`select`'s commit** (:776-790) adopts when either differs: `adopt(pendingConfig ?? config,
  away: awayWanted)`. It sets `awayRunning` and prints "Settings: …" only when `config` changed,
  as today. So an away flip prints its own line (§5.9), then "Streaming … at 1512×982, 60 fps,
  4 Mbps", and no "Settings:" line.
- **The device hook** (:377) becomes
  `(@MainActor (HostSettingsChange, _ away: Bool) -> HostConfig)?`. In the `.changeSettings`
  handler (:548-586):

  ```swift
  let away = routes[id]?.isAway ?? false
  let before = target
  setTarget(onDeviceSettingsChange?(ok, away) ?? (away ? before.applyingAway(ok) : before.applying(ok)))
  if target != before { print("Settings from \(who): " + before.changes(to: target)) }
  ```

- **Kind 16 per connection.**
  - `settingsState(for id:, answering:)` replaces `settingsState(answering:)` (:1333-1342):
    `settings: target.streamSettings(away: routes[id]?.isAway ?? false)`, `away:` an
    `AwayQuality` when `remote != nil` (else nil), its `awayRunning` from `awayWanted`, and
    `link: linkReports[id]` (§6.5). Never the pipeline's `awayRunning`: it changes in `adopt`,
    which publishes only through a snapshot change (HostStatus.swift:204-208), and none comes when
    nothing streams, so a state built from it could stick at the old value.
  - `publishSettings()` (:1363-1368) sends each connection its own state, only when it differs
    from `lastPublished[id]`, through a new `StreamServer.send(each:)` that sends every registered
    connection its own message and skips the rest without a word, as `broadcast` does. Not
    `send(_:to:)`: for a connection that has just left, it prints "send: no client for …", and a
    publish can land between the server forgetting a client and `onClientDisconnected` reaching
    the main actor (the CLI's stdout, H2).
  - `sendCatalog` (:1304-1323) records what it sent in `lastPublished[id]` and only then adds the
    connection to `connections`. Publishes reach only the connections there, so no state goes out
    ahead of a connection's window list and the catalog keeps its order (2, 16, 18). Today's
    broadcast reaches every registered client, and only its deduplication kept a state from
    landing before a new client's list.
  - Answers go only to their device and leave `lastPublished` alone, as today.
  - A disconnect removes the connection's entries.
  - With one device and no `away` or `link`, every device gets exactly the messages it gets
    today (H2, H13).

#### 5.5 `HostStatus.swift`

- `HostStatusSnapshot.away: Bool`: at least one device connected, and the away quality is the
  target.
- `Device.link: LinkStatus?` (§6.5).

#### 5.6 CLI

- Nothing new: no flag, no line on the default path.
- `SillHost --remote` hosts run the rule. Their lines print only when a device connects from a VPN
  or the internet, which no baseline run does: the remote plan's loopback TLS clients are "by
  address", so at home.

#### 5.7 Sill.app

- **`HostSettings`** (app, :26-116):
  - keys `awayBitrate` and `awayCaptureScale`, with registered defaults from `HostConfig.standard`;
  - loaded into `config`, saved only when changed, as the others.
  - `defaults read me.saffer.sill.mac awayBitrate` answers "does not exist" until the first change,
    which is how the default reads.
- **`AppModel`** (:71-74):

  ```swift
  c.onDeviceSettingsChange = { [settings] change, away in
      settings.config = away ? settings.config.applyingAway(change) : settings.config.applying(change)
      return settings.config
  }
  ```

- **Settings › Streaming** (SettingsPanes.swift:151-190). A new section after the first, header
  "Away from home":
  - Picker "Quality" (the presets, plus "Custom — N Mbps" for a hand-set value, as the first
    section does);
  - Picker "Resolution" (Retina, Standard).

  Both bind to `$settings.config.awayBitrate` and `$settings.config.awayCaptureScale`. Footer: §8.
  The first section keeps its controls and footer.
- **The status menu** (StatusItemController.swift:75-82): Quality and Resolution keep setting the
  home quality. While the away quality runs (`snapshot.away`), Quality's subtitle is "Away from
  home now: Low · Standard" instead of "Per 60 fps; a 120 fps stream gets twice as much".
- **`DebugHooks`:**
  - `-SillSetAfter` learns `awayBitrate=N` and `awayCaptureScale=1|2` (:108-126);
  - the previews gain a sample `remote-away` (the remote device, `away` true) for menu.txt and a
    card;
  - the Streaming pane samples show the new section.
- **The card** needs nothing for item 2: its source row already shows the running Mbps.

#### 5.8 The device (`HostSettingsPanel.swift`)

- **Header** (:92-150). After the route line, while `away.thisConnectionAway`:
  - "Away: Low · Standard" while the away quality runs;
  - "Home quality: Pro · Retina (a device at home is connected)" while it does not.

  Its own line, same font as the readout, wrapping like it. Spoken as §8 says. Values from
  `away.*`, the Mac's word, never a pending pick.
- **A footnote** under the stream rows' footer (:419-433), three forms (§8): away and running;
  away with a device at home; at home, when the host sent `away` and this connection's kind 18
  says Remote Access is on.
- **The ledger** (HostSettingsLedger.swift) is unchanged: `settings` is already the controlled
  pair (§4.2).
- **`MockCatalog`** gains `-SillSettingsCase away`, `awaymixed` and `awayhome`.
- **`Scripts/sillclient.py`:**
  - `describe` appends ` away=h:40000000/2,a:4000000/1,this=1,run=1` when `away` is present;
  - `--expect` learns `awayBitrate`, `awayCaptureScale`, `thisConnectionAway` and `awayRunning`
    (read from `away`).

#### 5.9 Log lines (exact; each only on its event)

```
Away from home: every connected device is away; streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality stays Pro · Retina.
Home quality again: a device connected at home (fe80::1c2d:3e4f:5a6b:7c8d%en0.51447); streaming at Pro · Retina.
Settings from iPad (iPad14,1): away bitrate 4 → 15 Mbps per 60 fps
Settings: away bitrate 4 → 15 Mbps per 60 fps
```

"Settings from …" and "Settings: …" keep their exact form; tests grep them.

---

### 6. Item 3: the host reports the link

#### 6.1 The rule

Each second, per connected device, the host closes a window of what it did for that device:

- **frames sent**;
- **frames withheld:** dropped, or skipped while it waited for a keyframe. Frames skipped before
  its first keyframe since it connected or the stream changed do not count: that wait is the
  connect or a restart, not the link;
- **bytes taken** by its connection (`.contentProcessed`);
- **bytes waiting** at the second's end;
- **heard:** whether anything came from the device in the second (`lastHeardAt`; it pings every
  0.25 s).

`.contentProcessed` comes once a message has been taken whole: a 1.6 MB keyframe crossing 2 Mbps
can show as up to 6 s of nothing taken, then all of it, though the link carried it throughout (the
investigation's slowkfB). Both measures below allow for that.

From those:

- **A second is short** when at least 3 frames were withheld and at least a tenth of the second's
  frames. So a single drop at home (one frame, then the keyframe asked for at once) never counts,
  and neither does a still window (no frames).
- **Behind** ("the link can't carry this quality"): 3 of the last 5 seconds were short.
- **Stalled:** for 3 seconds in a row the connection took nothing while bytes waited, and nothing
  was heard from the device: the path is down both ways, as at the ends of the hotspot sessions.
  Nothing taken alone is not enough: a slow link carrying one large message, or a still window
  right after one, takes nothing for seconds while its device keeps pinging. A path down only
  towards the device reads as behind (its frames are withheld), and the device's liveness ends it
  (6 s without a byte): the host's drain backstop is checked only as a frame goes out, and none
  does. A stall ends at the first second in which anything is taken or heard: behind then if 3 of
  the last 5 seconds were short, else fine.
- **Fine again** (from behind): 5 seconds in a row that were not short. The hysteresis keeps the
  state from flapping.
- **A stream restart** (a settings change, a rate change, a new source) clears the window: the
  state goes back to fine and is judged afresh. Picking a lower quality clears the callout at
  once, and it comes back after 3 s only if the new quality cannot be carried either.
- **Carried:** the bytes taken in the last 5 seconds that ended with at least 16 KB waiting,
  divided by their number, needing 3 such seconds. In those seconds the link, not the stream, set
  the pace, and the kernel's buffer was full, so what the connection took is what the link
  carried. A mean, not a median: messages are taken whole, so a keyframe that crosses in 2 s
  counts as a second of nothing and a second of all of it, and at Extreme on a hotspot (312 KB
  deltas, about 750 KB a second carried) the median of such lumpy seconds can read half the link.
- **Reported** to the coordinator when the state changes, and once more when the carried rate is
  first measured during a spell. Never every second: the device's own stats carry its fps.

Every device is judged, at home too. The home branch only counts: nothing it sends or drops
changes.

#### 6.2 The suggestion

Relative to the running quality (the effective pair) and the stream's frame rate:

- **Candidates:** the presets below the running bitrate.
- **With a measured carried rate:** the highest candidate whose rate at the stream's fps
  (`bitrate × fps / 60`) is at most 70 % of what the link carried. If none fits, Low.
- **Without a measure:** the highest candidate, one step down.
- **Resolution:** Standard with it when the suggestion is Low and the stream runs at Retina.
- **No preset below the running bitrate** (Low, or a hand-set rate under it): the same bitrate at
  Standard from Retina; nothing (nil) from Standard, the "even Low" case. A suggestion is never a
  higher bitrate.

Why 70 %: in the harness, streams at about 51 % (Low on 8 Mbps) and 73 % (real24) of the link
kept 60 fps, and one at about 93 % did not (43.8 fps). The encoder's own 4 s keyframe and the
`DataRateLimits` window (bitrate/8 per second, HEVCEncoder.swift:86) sit inside that margin.

#### 6.3 `StreamServer.swift`

- **`Client`** gains the second's counters (`sentThisSecond`, `withheldThisSecond`,
  `takenThisSecond`; `heard` comes from `lastHeardAt`, kept for every client already) and
  `judge: LinkJudge`. `pendingBytes` is now kept for every client. Item 1's
  keyframe and floor bookkeeping stays remote only, and the home branch never reads
  `pendingBytes`.
- **Counting:**
  - in the home branch (:876-891) and in `paceRemote`, at each `net.sent`, `net.dropped` and
    `net.waitKey` bump;
  - `awaitingFirstKeyframe`, today cleared only for remote clients, is also cleared when the home
    branch sends a client its keyframe. The home branch does not read it.
- **The sweep** (`updateRemoteSweep`/`sweepRemote`, :717-745) becomes one 1 s timer on `sill.net`
  while any client is registered. Each tick closes every client's window
  (`judge.close(LinkJudge.Second(…))`) and reports a verdict through
  `onClientLinkChanged: ((NWConnection, LinkJudge.Verdict) -> Void)?`. The remote silence
  eviction stays in the same tick, remote only, unchanged.
- **`resetForNewStream`** (:760-768) also resets every judge. A judge that was not fine reports
  fine, marked as a reset: the coordinator clears the report without a line (nothing was measured;
  "keeping up again" at every restart would be untrue, and the pick that lowered the quality
  restarts the stream).
- **No Stats key, no print.** The lines are the coordinator's (§6.8).

#### 6.4 `Sources/SillHost/LinkJudge.swift` (new; pure: Foundation only; checked with swiftc)

```swift
struct LinkJudge {
    enum State: Equatable { case fine, behind, stalled }
    struct Second: Equatable { var sent: Int; var withheld: Int; var taken: Int; var waiting: Int; var heard: Bool }
    struct Verdict: Equatable { var state: State; var withheld: Int; var offered: Int; var carriedKbps: Int?; var waiting: Int; var reset: Bool }
    static let window = 5, shortToBehind = 3, cleanToFine = 5, stallSeconds = 3
    static let measureWaiting = 16 * 1024, headroom = 0.7
    static func isShort(_ s: Second) -> Bool            // withheld ≥ 3 and 10 × withheld ≥ sent + withheld
    private(set) var state = State.fine
    mutating func close(_ s: Second) -> Verdict?        // non-nil when reported (§6.1)
    mutating func reset() -> Verdict?                    // fine, when it was not; `reset` true
    var carriedKbps: Int? { get }
    static func suggestion(carriedKbps: Int?, bitrate: Int, fps: Int, captureScale: Double) -> (bitrate: Int, captureScale: Double?)?
}
```

The state is an enum inside the host only; the wire carries the string.

#### 6.5 `StreamCoordinator.swift` and `HostStatus.swift`

- **`server.onClientLinkChanged`** hops to the main actor. There it:
  - turns a verdict that is not fine into a `LinkReport`: the state's string, the withheld count,
    the running bitrate, the carried rate, and `LinkJudge.suggestion(…)` for the running pair and
    `status.stream.fps`;
  - stores it in `linkReports[id]` (removed when fine and at disconnect);
  - sets `status.devices[i].link`;
  - prints the line (§6.8).

  The snapshot change publishes, and each connection's state carries its own report.
- **`HostStatusSnapshot.Device.link: LinkStatus?`,** a package struct: `state` (behind, stalled),
  `withheld`, `bitrate`, `carriedKbps`, and the suggestion, for the card.
- **The suggestion is sent even when this device cannot apply it** (away, with a device at home):
  the device decides what to offer (§6.7).

#### 6.6 Sill.app: the card (`StatusText.swift`)

`deviceRow` (:205-215). While `d.link` is set, the first part of the detail becomes:
- behind: "3 fps, the link can’t carry Pro";
- stalled: "Nothing is getting through".

The frame age drops out to keep the row short. Then "· RTT 531 ms" (behind only) and the route
word, as today. `DebugHooks` gains card samples `link-behind` and `link-stalled`.

#### 6.7 The device

**Stalled is the Mac's alone.** A report of it queues behind the backlog it describes, so it can
only reach the device once the path is back, when it is no longer true, and the next report
follows within a second. The device shows nothing for it (no callout, no line); its own liveness
and frame age speak for a dead path.

**The callout** (`HostSettingsPanel.middle`, :174-258, where the slow-link callout sits). While
`client.settings.host?.link` says behind, one callout, first match wins:

| Situation | Callout | Button |
|---|---|---|
| Behind, away while a device at home is connected (`away.thisConnectionAway && !away.awayRunning`) | "The link can’t carry ‹Pro›, which ‹Mac› keeps while a device at home is connected." | none |
| Behind, a suggestion | "The link can’t carry ‹Pro›. ‹Low · Standard› is recommended." | "Use ‹Low · Standard›" |
| Behind, nothing lower | "The link to ‹Mac› is too slow for a steady picture, even at Low." | none |

- ‹Pro› is `QualityPreset.name(forBitrate: link.bitrate)`. The suggestion reads
  `shortTitle(…)` when it changes the resolution, else the preset's name alone ("Balanced").
- **The button** is an ordinary control: `client.changeSettings(HostSettingsChange(bitrate:
  suggestedBitrate, captureScale: suggestedCaptureScale))`. The ledger sends only what differs
  (rule 2), the Mac restarts once, and from away it changes the away quality only. At least 44 pt
  tall, like the panel's rows; spoken "Use Low, Standard".
- **The old callout** (the rtt test, :183-187, `client.slowLink`) shows only while the
  Mac sent no `away`: an older host. A host with a remote door judges the link itself, and a high
  round trip with nothing withheld is no reason to lower the quality.

**The stream screen's line** (`StreamScreen.contentArea` and `PortraitStreamScreen`):
- **Where:** a capsule at the top centre of the stream panel, 8 pt inside its top edge, at most the
  panel's width minus 32 pt. Footnote text on `Palette.bar` at 0.92 opacity; two lines at most at
  xxLarge text.
- **When:** from the moment a report of behind arrives, while the Settings panel, the
  drawer and the pairing overlay are closed. It goes 2 s after the report clears, so a quick
  flip back does not flicker.
- **Words:** §8.
- **Non-interactive** (`allowsHitTesting(false)`): it never takes a touch meant for the Mac.
- **VoiceOver:** one announcement of its text per spell (a spell ends when the line goes), not on
  every change.
- **Reduce Motion:** a fade either way.

**The harness** gains `-SillSettingsCase linkbehind`, `linkmixed`, `linklow` and `linkstalled`
(which must show nothing), and `-SillLinkLine behind` for the stream screen with the line up.

#### 6.8 Log lines (exact; on reports only)

```
Link to iPad (iPad14,1): cannot carry Pro (withheld 52 of 58 frames in the last second; the link carried about 6.4 Mbps); suggesting Low · Standard.
Link to iPad (iPad14,1): cannot carry Extreme (withheld 57 of 60 frames in the last second); suggesting Ultra.
Link to iPad (iPad14,1): cannot carry Low (withheld 20 of 45 frames in the last second; the link carried about 2.1 Mbps); nothing lower to suggest.
Link to iPad (iPad14,1): nothing has got through for 3 s, and nothing has come from it (1.2 MB waiting).
Link to iPad (iPad14,1): keeping up again.
```

A report that only adds the carried rate prints nothing, and neither does a reset at a restart
(§6.3): "keeping up again" is a judged recovery only. The device's DEBUG console prints
"link: behind (cannot carry Pro; suggesting Low · Standard)" and "link: keeping up".

#### 6.9 Automatic step-down: not in this bundle

Open question 2. The report carries what an automatic rule would need. The rule the investigation
proposed: 3 drops in 10 s on a remote device → the next preset down for that session, Retina →
Standard first, not saved, and said so.

---

### 7. Item 4: a remote session moves home

#### 7.1 The rule

While this device's session runs through the remote door, the network browser keeps running
(StreamClient.swift:490-515). Once it has listed the same saved Mac for `moveAfter` (2 s) without
a break, the session moves to the home door.
- **"The same Mac":** a network row whose TXT tag names the session's Mac ID
  (`FoundMac.macID == session.macID`; `savedSightings.since[id]`, :601-602).
- **Direct rows never count:** the AWDL move exists, and a Direct row is not home.
- **The move:**
  - the normal dial: the cable first when the row says Wired, the row as listed after 2.5 s or at
    once when the cable's dial cannot go on (`wiredDial`, `wiredWait`);
  - a probe of the new connection;
  - PR #12's fenced hand-over (`SessionLink.handOver`): the remote connection is the old one;
  - then the remote connection closes.
- **The panel's route line** goes ("Connected through Tailscale · 48 ms"), and the readout ends in
  the new connection's word ("Wi‑Fi" or "Wired").
- **The Mac restarts once,** at the home quality (§7.4).
- **A move that does not complete** leaves the session remote. The next try waits `upWait`
  (PR #12): 10 s after the first failure, then 20, 40, then every 60 s. A new listing (the row
  went and came back) resets the count.
- **Never:**
  - for a session made with **Connect Remotely** (`DialReason.connectRemotely`), which exists to
    test the VPN path from home;
  - to a listing found to be another launch of Sill, or another Mac, while that listing lasts;
  - while a move of any kind is under way.

#### 7.2 `DiscoveryPolicy.moveHome` (pure, beside `moveToNetwork` :290-295)

```swift
/// While this device's session runs through the remote door: whether to move it home now, to the
/// saved Mac's network row listed since `listedSince` (nil: not listed), or when to look again.
/// Once listed for `moveAfter` without a break; after `failures` moves in a row to this listing
/// that did not complete, not before `upWait(failures:)` from the last one's start (10, 20, 40,
/// then 60 s); never to a listing found to be another launch (`refusedListing`).
static func moveHome(listedSince: Double?, lastAttempt: Double?, failures: Int, refusedListing: Double?,
                     now: Double) -> (move: Bool, recheckAt: Double?) {
    guard let since = listedSince, since != refusedListing else { return (false, nil) }
    var due = since + moveAfter
    if let last = lastAttempt, failures > 0 { due = max(due, last + upWait(failures: failures)) }
    return now >= due ? (true, nil) : (false, due)
}
```

`upWait` is PR #12's: `min(pathHysteresis × 2^min(failures, 4), upBackoffCap)`, which gives 10, 20,
40 and 60 s for 1, 2, 3 and 4 failures (5 × 16 = 80 is capped at 60).

#### 7.3 `StreamClient` (on PR #12; re-read its merged file before editing)

- **`MoveKind`** (PR #12) gains `.fromRemote`.
- **State:**
  - `lastHomeMove: Double?`;
  - `failedHomeMoves: (listing: Double, count: Int)?`;
  - `refusedHomeListing: Double?`;
  - `remoteInfoIssuedAt: Double?`: the `issuedAt` of the remote session's last verified kind 18.

  All are cleared in `tearDown`, `abandonMove` and at a new session.
- **`moveHomeIfListed()`,** modelled on `moveToNetworkIfListed` (:886-901). It is called from
  `discoveryChanged` (:558-563), at the session's first window list beside
  `moveToNetworkIfListed()` and `followBestPath()`, once `sessionListed` and `sessionHost` are set
  (not from `remoteSessionReady`, StreamClient+Remote.swift:326-350, which that handler calls
  before setting them: its `sessionListed` guard would fail, and a Mac already listed would wait
  for the next discovery change), and after a move ends. It needs:
  - `connected`, `session.route.isRemote`, `session.why != .connectRemotely`, `sessionListed`;
  - no move under way, and a connection;
  - `let id = session.macID`, and a row `macs.first { $0.route == .network && $0.macID == id }`.

  Then it runs `DiscoveryPolicy.moveHome(…)` and moves, or schedules the look again.
- **The move:**
  - `lastHomeMove = now`; `lastMoveUp = now` too, so PR #12's `followBestPath` counts its
    hysteresis from it (the session is on the network afterwards, and may move to the cable
    later);
  - `startMove(to: wired.endpoint, kind: .fromRemote, fallback: mac.endpoint)` for a Wired row,
    else `startMove(to: mac.endpoint, kind: .fromRemote, fallback: nil)`. The move's own 5 s, 7.5 s
    at most with the wired attempt.
- **At the new connection's `.ready`,** before the probe, the home viewport goes straight out on
  it: `lastViewport` with `fps: StreamClient.wantedFPS(remote: false)`, sent on `c`, not through
  SessionLink. Both are main-thread state (UIScreen, `lastViewport`), so the move captures the
  message when it starts, on the main thread, and the `.ready` handler on `sill.net` only sends it.
  - A viewport cannot reorder input, and the Mac keeps a rate per connection.
  - It is the new connection's first viewport, which the Mac's flip waits for (§5.4), so a
    ProMotion device's 120 fps and the home quality go in one restart (§7.4).
  - `finishMove`'s re-send (PR #12's `if let v = lastViewport { sendViewport(v) }`) sends this
    captured viewport for `.fromRemote`, not `lastViewport`, which still carries the away
    session's 60 fps cap: re-sent after the fence, it would take the new connection's rate from
    120 to 60, and StreamScreen's re-send on `remoteRoute` back to 120, two more restarts. Sent
    through `sendViewport`, the captured one becomes `lastViewport`, and the Mac finds it
    unchanged.
- **The probe** (`probeMove`/`moveProbed`, PR #12) reads on to kind 18 for `.fromRemote`. The
  catalog's order is 2, 16, 18, so this costs a millisecond. The session is handed over only when
  all three hold:
  - the window list's launch ID equals the session's (`DiscoveryPolicy.sameHost`);
  - kind 18 verifies against the saved pin (`SignedMacInfo.verified()`, fingerprint and Mac ID
    equal to the saved Mac's);
  - its `issuedAt` ≥ `remoteInfoIssuedAt`.

  The Mac signs kind 18 afresh for every catalog (RemoteAccess.swift:537-542). A signature at
  least as new as the one this session received was made by the Mac since this session began, so
  a TXT tag and a kind 18 captured earlier and replayed are not enough to take the session over
  (§10). It does not prove the home door is the Mac: anyone who can reach the Mac's home door
  (anyone on its network) can fetch a fresh kind 18 and the launch ID there and relay them, the
  plaintext home door's exposure until M5, as for every reconnect over it today.

  A mismatch: "remote: move home refused: …" and `refusedHomeListing = savedSightings.since[id]`.
- **`finishMove(c, kind: .fromRemote, kept:)`** (PR #12):
  - guard: `connected`, `let old = connection`, `session?.route.isRemote == true`;
  - fenced: `link.handOver(from: old, to: c, …)`, with `fenceTimeout` 3 s;
  - then `session?.route = .network`, `session?.candidate = nil`, `session?.bonjourName =` the
    row's name, `remoteRoute = nil`, `setRoute(from: c.currentPath, fresh: true)`,
    `connectedAt = Date()`;
  - the ledger reset, as PR #12 does for every move;
  - `startMeasuring(c, remote: false)`: the viability rule is for remote paths only.

  The old connection's handlers find it no longer the session's (`connectionLost` checks
  identity), and it closes through `closeSoon` once what waited has gone out.
- **`moveEnded` for `.fromRemote`:** the session stays remote.
  `failedHomeMoves = (listing, count + 1)` for the same listing, else 1; then
  `moveHomeIfListed()`.
- **The remote connection dying while the move home is under way** (the hotspot dropped as the
  home Wi‑Fi joined): the move carries the session, as PR #12's `rescue` lets a move to Wi‑Fi
  under way carry a dead cable session. `rescue` today returns false for any remote session
  (pathPlan never moves one), so a `.fromRemote` move under way is checked first: `sessionDead`,
  what the device sends is held from that moment (`holdSends(c)`: unlike a move to Wi‑Fi, this
  move held nothing when it started), and the hand-over is an `adopt` without a fence, since
  nothing sent on a dead connection comes back. No connect screen; the session ends only if the
  move does not complete.
  - **Settings picks are not held.** While that hold stands, `changeSettings` sends nothing (the
    control stays on the Mac's value). A pick then is made against the away state the panel
    shows; held, it would go out on the home connection, and the Mac, which counts that one at
    home, would set the home quality and Sill.app would save it. The fenced hand-over needs no
    such rule: `finishMove` resets the ledger in the same main-thread turn as `handOver`, so a pick
    before it goes out on the remote connection (the fence has the Mac read it there, as away),
    and one after it waits for the home connection's state.
- **`receiveMacInfo`** (StreamClient+Remote.swift:521-545) records `remoteInfoIssuedAt` for a
  verified kind 18 on a remote session.
- **`StreamScreen`** also re-sends the viewport on a change of `client.remoteRoute`, so a session
  that stops being away asks for its full rate whatever path it took.

#### 7.4 What the Mac sees, and the one restart

1. "Client connected: fe80::…%en0.51447" and its catalog, while the remote session streams on.
2. The new connection registers, so `routesChanged` finds a device at home: "Home quality again:
   …". The flip waits for that connection's first viewport, the home one the move sent at
   `.ready` (§5.4): one restart, at the home quality and the device's home rate.
3. The fence's pong on the remote connection, then the device's held messages on the home one.
4. "Client left: 100.x.y.z:port" half a second later. Nothing else changes: a home device is
   still connected.

A move that fails after the home connection was admitted (no list, or no kind 18, within its 5 s)
flips the quality home and back: two restarts. It is rare: the listing named this Mac and the
connection was admitted.

#### 7.5 DEBUG console lines (device) and the harness

```
remote: Mac mini (A3C5HR4RBV67YR21) is on this network: moving the session home in 2.0 s
remote: moving the session home on en2 (wired)
remote: moving the session home (the row as listed)
remote: the session moved home (fence down after 184 ms; 3 held messages went out)
remote: the move home did not complete (2 in a row); the next try in 20 s
remote: move home refused: Mac mini on the network is another launch of Sill
remote: move home refused: the home door's kind 18 is not this Mac's, or older than this session's
```

- **`-SillMoveHomeTest to:HOST:PORT|refused|other:PORT`,** with `-SillDialSaved 1` against a
  synthetic `SillHost --remote`. A second after the remote session's first window list, the
  saved Mac is listed as a network row at that address with the session's Mac ID. Modelled on
  `-SillMoveTest` (`beginMoveTest`, PR #12). `refused` lists port 1 of that host; `other:PORT` a
  second synthetic host.
- **`-SillDialSaved remotely`** dials the first saved Mac as Connect Remotely does.

---

### 8. Copy (every new string)

**Mac.**

| Where | Text |
|---|---|
| Settings › Streaming, new section header | "Away from home" |
| Its footer | "Sill streams at these while every connected device is away from home, through a VPN or over the internet, so a slow connection never starts at your home quality. A device away from home changes these, and never your Quality and Resolution above." Then, while they run: " Streaming at these now." |
| The menu's Quality subtitle, while the away quality runs | "Away from home now: Low · Standard" |
| The card, a device behind | "3 fps, the link can’t carry Pro · RTT 531 ms · through Tailscale" |
| The card, a device stalled | "Nothing is getting through · through Tailscale" |

**Device.** ‹Mac› is the Mac's name; ‹home› and ‹away› are `shortTitle`s ("Pro · Retina").

| Where | Text |
|---|---|
| Panel header, away and running | "Away: ‹away›" (spoken ", away quality, Low, Standard") |
| Panel header, away with a device at home | "Home quality: ‹home› (a device at home is connected)" (spoken ", home quality, Pro, Retina, because a device at home is connected") |
| Footnote, away and running | "Away from home, ‹Mac› streams at what you choose here and keeps it for next time. At home it goes back to ‹home›." |
| Footnote, away with a device at home | "A device at home is connected, so ‹Mac› streams at its home quality, ‹home›. What you choose here applies once every device is away." |
| Footnote, at home (the host sent `away`; kind 18 says Remote Access is on) | "Away from home, ‹Mac› streams at ‹away›." |
| Callouts and the button | §6.7 |
| Stream screen line, behind with a suggestion | "The link can’t keep up with ‹Pro›. Lower it in Settings." |
| Stream screen line, any other behind | "The link to ‹Mac› can’t keep up." |
| VoiceOver, once per spell | The line's text |

---

### 9. Timeouts and limits

| What | Value |
|---|---|
| Remote backlog that never drops a frame | 256 KB (`remoteBacklogBudget`) |
| Growth over a keyframe's leftovers that is noise | 128 KB (`remoteBacklogSlack`) |
| Queue allowed behind a keyframe still being taken | 512 KB (`remoteHoldCap`) |
| Queue short enough to ask for a keyframe | 16 KB (`remoteIdleBytes`) |
| Forced keyframes for remote clients | unchanged: 2 s apart alone; beside a home client 4 s since the last request and since any keyframe |
| Device read piece | at most 256 KB |
| Device liveness | no byte for max(6 s, 4 × the worst rtt of the last second that measured one), now true per byte; remote paths also not viable for more than 3 s (unchanged) |
| A short second | ≥ 3 frames withheld and ≥ a tenth of that second's frames |
| Behind / fine again / stalled | 3 of the last 5 seconds short / 5 seconds in a row not short / 3 seconds with bytes waiting, none taken and nothing heard from the device |
| Carried rate | the bytes taken in the last 5 seconds that ended with ≥ 16 KB waiting, over their number (a mean); needs 3 |
| Suggestion headroom | 70 % of the carried rate, at the stream's fps |
| Stream screen line | shown on arrival; goes 2 s after the report clears |
| Move home: listed | 2 s without a break (`moveAfter`) |
| Move home: retries | 10, 20, 40, then every 60 s after moves that did not complete (`upWait`) |
| Move home: dial | the cable 2.5 s (`wiredWait`), then the row as listed; the move's connection 5 s (7.5 s at most) |
| Move home: fence | at most 3 s (`fenceTimeout`) |

---

### 10. Edge cases

| Case | Behaviour |
|---|---|
| The 14:02 case: at home, Tailscale re-paths over the LAN | The network lists the Mac, so the session moves home about 2 s later; Noah's pick at 14:02:55 would have been a home pick. Where Bonjour cannot see the Mac (a network that blocks mDNS), the session stays away at the away quality (open question 1) |
| A device connects from away while a home device streams | The home quality runs. The away device's header says so; its picks set the away quality |
| The home device leaves | The away quality: "Away from home: …", one restart |
| Every device leaves | The flag stays. Nothing streams; the next device to register decides |
| An older device away (PR #13) | Shows and sets the away quality as its Quality (§4.2); no header line |
| A remote-door session from this network ("by address") | At home |
| A VPN into the home router (WireGuard on the router) | The remote door sees a routed private source ("by address"), so the host counts it at home and runs the home quality, although the device still asks for 60 fps (its path used a tunnel). Open question 6 |
| The Mac's Settings changes the away quality while it runs | One restart; "Settings: away bitrate …" |
| The menu's Quality while the away quality runs | Sets the home quality (saved); nothing restarts; the subtitle says the away quality runs |
| A hand-set away bitrate (`defaults write … awayBitrate`) | "Custom — N Mbps" in the new section; a device away shows it read-only, as today's Custom |
| The home quality is Low · Standard already | The flip prints its line and restarts nothing |
| Link: a still window | No frames, nothing withheld: fine |
| Link: the connect burst, a restart | Frames before the first keyframe do not count; a restart clears the judge |
| Link: home Wi‑Fi far from the router at Extreme | Behind at home too; the button lowers the home quality (saved), as a menu click would |
| Link: two away devices, one on a poor link | Its callout; the button lowers the shared away quality for both (one stream). The panel already says "Applies to every device streaming from ‹Mac›" |
| Link: stalled | The card says so. The device shows nothing (§6.7), and its liveness decides the session |
| Link: a report queued behind the backlog it describes | Behind: it waits behind at most what §3 lets queue (a keyframe and up to 512 KB after it). Stalled: it arrives when the path recovers, the device ignores it, and the next report follows within a second |
| Link: a slow link carrying one large message, or a still window right after one | Not stalled: its device keeps pinging (§6.1). The carried rate counts the message in the second it was taken whole, over the seconds it took |
| Link: the path down only towards the device | Behind, not stalled: its pings still come. The device's liveness ends the session (6 s without a byte); the host's drain backstop is checked only as a frame goes out, and none does |
| Link: one drop on a remote device beside a home device | It waits for a keyframe up to 4 s (the spacing beside a home device), which can read as 3 short seconds: behind for about 8 s though the link recovered at once. Accepted: its picture did stop |
| Link: a stream carried whole but late (bigkf8's good runs, §3.7) | Fine: nothing is withheld. The device's frame age shows the lag |
| Move home: another Mac of the same name on the network | Rows match by Mac ID (the tag), never by name |
| Move home: an impostor replays the Mac's TXT tag | Its connection must show this launch's ID and a kind 18 signed by the pinned key at least as new as this session's, which only the Mac makes: a capture from before this session is refused. Anyone who can reach the Mac's home door can fetch both there and relay them: the home door is plaintext until M5, as it is for every reconnect over it today |
| Move home at the edge of the home Wi‑Fi | A home connection that dies soon after a move home reconnects remotely (the network no longer lists the Mac) and moves home again once it is listed 2 s: each round costs the Mac two restarts (home, then away). Not damped: the back-off counts moves that did not complete within one session, and each round is a new session. P10 notes how often it happens |
| A home device joins while only away devices stream | One restart, at its first viewport: its rate and the home quality together (§5.4); 1 s after it connected when no viewport comes (a test client) |
| A pick on the panel while the move home carries a dead remote session | Not sent (§7.3): it would set the home quality from an away panel |
| Move home: Connect Remotely | Never moves |
| Move home: the Mac seen only over AWDL | Never moves (Direct rows do not count) |
| Move home: the home connection admitted, then the move fails | Two restarts (home, then away again); the next try waits 10 s |
| Move home: a slow fence (Tailscale through DERP) | At most 3 s; input waits meanwhile, in order |
| Move home: the remote connection dies during the move | The move carries the session without a fence (§7.3); the session ends only if the move fails |
| Move home by the cable | A Wired row dials the cable first |
| Leaving home mid-session | Not a move: the home connection ends and the reconnect dials remotely (remote-access-plan.md §7.4). The away quality applies at registration |
| The panel open during a move | For the length of the probe the remote connection reads "Home quality: … (a device at home is connected)"; the device at home is itself. The hand-over resets the ledger and the home state follows |

---

### 11. Test gates

**Hard rules for the implementing session:**
- **Never touch** `/Applications/Sill.app`, the `me.saffer.sill.mac` domain, Noah's login
  keychain or his iPad. App paths use the bare `SillMenuBar --synthetic` with
  `SILL_TEST_REMOTE_DIR`; `defaults delete SillMenuBar` afterwards.
- **The encoder-free harness** (`Scripts/pacing/`) for every pacing and link-judging gate.
- **Synthetic hosts run with `SILL_TEST_SOFTWARE_ENCODER=1`.** If the pointer plan has not landed
  the hook, step 1 adds it as pointer-visibility-plan.md §4.10 defines it: a synthetic host only;
  it skips `EncoderProbe` and starts on the software encoder, with the line "Test encoder:
  software only (SILL_TEST_SOFTWARE_ENCODER); the hardware encoder is never probed.". **It also
  stops PR #11's re-check,** which §4.10 predates: since b50e224 a host on the software encoder
  tests the hardware every 30 s while a device is connected (`startRecheck`, a short
  `EncoderProbe.throughput` at the stream's size) and goes back to it once it keeps up, so the
  hook as §4.10 words it would reach the hardware encoder half a minute into H7–H13 and S2–S5,
  and could move the test stream onto it. `startRecheck` returns at once under the hook; H0
  checks it. On the software encoder a synthetic host runs at points and at most 60 fps
  (CLAUDE.md), so Retina ↔ Standard shows in the logs as bitrate only, and no viewport's rate
  restarts it.
- **H2's parity runs use the hardware encoder,** as every earlier parity run did. Run them only
  while `~/Library/Logs/Sill/Sill.log`, read-only, has no `client ` line in the last minute;
  otherwise wait and say so in the results.
- **Never `simctl recordVideo`, never XCUITest, never the iOS Simulator control tool's `attach`**
  while a host streams: the Simulator's recorder starved Noah's encoder on 2026-09-24.
- **Hosts** are started from Python with `start_new_session=True` and killed by PID, none left
  running. Harness and synthetic runs start only with the load average under 20
  (`sysctl -n vm.loadavg`); the verifier threw out runs made at ~550.
- **A simulator of its own,** not the shared iPad Pro 13".
- **`$T`** is a fresh temporary directory per gate.

**New and changed tools:**
- **`Scripts/pacing/`** (new; Swift and the Python standard library), from the investigation's
  scratch:
  - `main.swift`: the fake-encoder driver. Keyframes and deltas of chosen sizes, a keyframe on
    request and every `--gop` seconds, the catalog (`--icons`), thumbnails every 6 s, the remote
    door on RemoteTLS's server parameters accepting any key, or `--plain` for the home door. With
    item 3 it prints each link verdict as "Link: behind (withheld 52 of 58; carried 7.9 Mbps;
    suggesting Low)", the suggestion from `LinkJudge.suggestion` for `--bitrate B` (default Pro)
    at the run's fps, and `--still-at T:D` sends no frame for D seconds from T (a still window).
    Those lines compile only under `#if LINK_JUDGE`, which `build.sh` defines for HarnessNew
    alone: one main.swift serves both packages, and the base's StreamServer has no
    `onClientLinkChanged`.
  - `build.sh BASE`: assembles two throwaway SwiftPM packages under `$T`: HarnessBase from
    `git show BASE:` of StreamServer.swift and its neighbours (ClientLink, HostLog,
    InterfaceSnapshot, OriginPolicy, RefusalSummary, Stats, and LinkJudge once it exists), and
    HarnessNew from the working tree, each with `Sources/StreamProtocol`. Nothing is copied into
    the repository, so nothing drifts.
  - `device.py` (the device's reader, pings, stats and liveness; `--liveness-bytes` for the per-byte
    rule), `bottleneck.py` (a rate, a delay and a finite bottleneck queue; `--rate-at T:R`, where a
    rate of 0 stops the downlink only, and `--blackhole-at T`, both ways from T, as sillrelay.py's
    `--blackhole-after`), `run.py`, `summarize.py` and `matrix.sh`.
  - The device's key and certificate are made on first use with `/usr/bin/openssl` under `$T`,
    never committed.
- **`Scripts/sillclient.py`:** `describe` prints `away=` and `link=` when present; `--expect` learns
  `awayBitrate`, `awayCaptureScale`, `thisConnectionAway`, `awayRunning` and `linkState` (`fine`
  when absent).

**Headless (H).**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base; `git archive` it to `$SP/base` and build it. `Scripts/pacing/build.sh <base>`. H2's baselines. The ledger check's count (90 with 5,000 runs) and the policy checks' counts, PR #12's included. Once the software-encoder hook exists (step 1, or the pointer plan): the synthetic host's keyframe size and rate on it (`sillclient.py PORT 10 desktop`, its LINK line), from which S2 and H12 set their relay rates; and that the hook keeps the hardware encoder out: `startRecheck` returns under it (read the code), and a synthetic host with it and `sillclient.py PORT 75 desktop` stays on the software encoder throughout | Files and numbers recorded; no return to the hardware encoder |
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **The CLI byte for byte.** Base and new `SillHost --synthetic`: idle 35 s, and with `sillclient.py PORT 5 desktop`; both again with `--direct-wireless`; digits masked, sorted. After steps 1, 5 and 6 | Identical, the client's kind 16 lines and "settings messages" count included |
| H3 | **The pacing matrix,** base and new, each case's arguments as run by the investigation (host `--` relay `--` device): real24 `--kf 1500000 --delta 30000 -- --rate-mbps 24 --delay-ms 70 --queue-bytes 262144 -- --reconnect`; kf25m32 (2.5 MB, 20 KB, 32 Mbps); fastbig (1.5 MB, 150 KB, 100 Mbps, 20 ms, a 1 MB queue); bigkf8 (1.5 MB, 8 KB, 8 Mbps); low (150 KB, 8 KB, 8 Mbps); switch (sizes change at 30 s to Low's); dip (8 → 0.5 Mbps from 20 s to 32 s, a 1 MB queue, 60 s); over8 (60 KB deltas on 8 Mbps); slowkfB (1.6 MB on 2 Mbps with `--liveness-bytes`); home (`DOOR=Home`, `--plain`); ext120 (`--kf 2000000 --delta 312500 --fps 120 -- --rate-mbps 600 --delay-ms 6 --queue-bytes 262144`, 25 s). real24, kf25m32 and bigkf8 three times each | real24 ≥ 55 fps, 0 `net.dropped`, about 15 keyframes a minute, 3 of 3 (on the proposed file 60.1, 59.9 and 59.9 fps, against the base's 39.5); kf25m32 ≥ 55 fps (60.1 and 60.0 against 1.4); fastbig 60 fps and 0 drops (base 1.7 a minute); ext120 120 fps, 0 `net.dropped` and 0 `net.waitKey` after the first keyframe (measured: 120.0 fps, the base 8.6 drops a minute); slowkfB ≥ 55 fps after its first keyframe and no liveness loss (measured on the proposed file: 60.1 fps from 12 s, 0 drops). bigkf8 is bistable (§3.2), so it is recorded, not gated beyond each run ≥ the base's fps (on the proposed file two of three at 60 fps with 0 drops, the third in the 2 s loop at 29.6 fps). low, switch and home equal the base within noise. dip: no loss, no eviction, the lag back to 45 ms within 10 s of the dip's end (7.1–8.2 s measured; record it). over8 ≥ the base (record it) |
| H4 | **The remote door's slow-link gates again** (remote plan H14, H15): `sillrelay.py --rate-mbps 2 --delay-ms 150` for 90 s on a paired session; `--blackhole-after 5` | No eviction; frames in every 5 s window; keyframes at the encoder's cadence; "Client silent for … dropping" at about 13 s after a blackhole |
| H5 | **MessageReader** (swiftc, against a local NWListener): 2,000 random messages of 0 B to 3 MB written in random chunks of 1 B to 300 KB with random pauses; a 3 MB frame at 1 Mbps; EOF half-way through a payload; a header announcing 40 MB; `stillReads` turning false mid-stream | Every message delivered byte for byte and in order; `onBytes` at least once per 256 KB and at most 0.3 s apart during the slow frame; EOF gives `.closed` with nothing delivered; `.tooBig` with nothing read after the header; no receive after `stillReads` is false. At least 5 mutants caught: the stamp only at the message's end, `minimumIncompleteLength` = remaining, no piece cap, EOF mid-message ignored, no cap check |
| H6 | **The wire** (swiftc): `AwayQuality` and `LinkReport` JSON round trips; `{}` fails to decode them, and a state without them decodes; the base's StreamProtocol decodes the new kind 16 and the new decodes the base's | All pass |
| H7 | **Away.** `SILL_TEST_ORIGIN=vpn SILL_TEST_REMOTE_DIR=$T/h SillHost --synthetic --remote`; `sillclient.py --tls --pair-code=… --identity=$T/a`, then a session with `--set=bitrate=15000000@4` | "Away from home: …" once; "Streaming … 4 Mbps"; kind 16: `thisConnectionAway` 1, `awayRunning` 1, bitrate 4000000, scale 1, `homeBitrate` 15000000; at 4 s "Settings from sillclient: away bitrate 4 → 15 Mbps per 60 fps" and one restart at 15 Mbps; `homeBitrate` still 15000000 |
| H8 | **Mixed.** H7's host; a home client at 5 s from the Mac's own `fe80::…%en0` (`--host=`, admitted as this network) with `--fps=60` (its viewport right after its select), leaving at 12 s; again without `--fps` | "Home quality again: …" at 5 s and one restart, after the home client's viewport, or 1 s after it connected without one (§5.4); the remote client's kind 16 `awayRunning` 0 while the home client stays; at 12 s "Away from home: …" and one restart; exactly one "Streaming" line per flip |
| H9 | **The app.** Bare `SillMenuBar --synthetic -remoteAccess 1` (a launch-argument override, never saved) with `SILL_TEST_ORIGIN=vpn`, `SILL_TEST_REMOTE_DIR=$T/app` and `-SillPairAfter 1`; `sillclient.py --tls --pair-url=` from `$T/app/pairing.url`, then a session that changes the bitrate; relaunch; `-SillSetAfter '3 awayBitrate=8000000,awayCaptureScale=2'` | `defaults read SillMenuBar awayBitrate` 15000000 and `bitrate` absent; after the relaunch the away session starts at 15 Mbps; the SetAfter gives one "Settings: away bitrate 15 → 8 Mbps per 60 fps, away points → Retina" and one restart; then `defaults delete SillMenuBar` |
| H10 | **LinkJudge** (swiftc, at least 34 checks): behind at exactly 3 short of 5 (2 stays fine); fine after 5 clean in a row (4 stays behind); still seconds count as clean; stalled after 3 seconds with bytes waiting, none taken and nothing heard (2 not; 3 with the device heard not: a keyframe crossing a slow link); a stall ends at the first second with bytes taken or the device heard, to behind when 3 of the last 5 were short, else fine; stalled → behind → fine; reset reports fine, marked as a reset; `isShort` at 2 of 60 (no), 3 of 60 (no: 5 %), 6 of 60 (yes), 3 of 20 (yes); the carried rate needs 3 measured seconds and is their mean (0, 0 and 2.25 MB read 6 Mbps, where a median would read 0); the suggestion: the highest preset ≤ 70 % at 60 and at 120 fps, Low when none fits, one step down without a measure, Standard added only with Low from Retina, the same bitrate at Standard from Low · Retina and from a hand-set 2 Mbps at Retina, nil at Low · Standard, never above the running bitrate | All pass; at least 10 mutants caught (2 of 5, 4 clean, still seconds as short, `>` for `≥`, 0.8 for 0.7, fps ignored, Standard never suggested, the first-keyframe wait counted, stalled without the silence, the median for the mean) |
| H11 | **The link in the harness** (encoder-free, the new build): real24, over8 (`--bitrate 40000000`), dip, slowkfB, still (slowkfB's sizes and `--liveness-bytes`, with `--still-at 31:10`: the frames stop while its second keyframe is still crossing), a blackhole both ways at 20 s (`--blackhole-at 20`), the downlink alone at 0 from 20 s (`--rate-at 20:0`), home | real24 never behind; over8 behind within 5 s of the stream start, carried within 20 % of 8 Mbps and a Low suggestion; dip behind within 5 s of its start and fine within 10 s of its end; slowkfB and still never stalled or behind after the first keyframe; the blackhole stalled within 4 s; the downlink alone behind within 5 s and never stalled; home never behind |
| H12 | **The link end to end.** H7's host through `sillrelay.py --rate-mbps R` (R half the synthetic stream's rate, from H0), the away quality first raised to Balanced (`--set=bitrate=15000000@2`: at Low · Standard there is nothing lower to suggest); `--set` of the suggestion 20 s in | Within 6 s of the first `--set`'s restart a kind 16 with `link.state` "behind" and a suggestion below Balanced, and "Link to sillclient: cannot carry Balanced …"; after the second `--set`, one restart and a kind 16 without `link`, with no "keeping up again" line (a reset). The synthetic pattern's size does not follow the quality (under 1 Mbps whatever the target, CLAUDE.md), so behind can come back 3 s or more later: expected, recorded |
| H13 | **Per-connection states.** H8's two clients, and the one-client runs of H2 | Each gets its own pair; with one client, the kind 16 lines and count equal the base's |
| H14 | **The ledger check and the policy checks,** unchanged and PR #12's | As at H0 |
| H15 | **`moveHome`** (swiftc, with the policy check): 1.9 s no, 2.0 s yes; a blink restarts the count; retries at 10, 20, 40, 60, 60 s after 1–5 failures; a refused listing never; a new listing afresh | All pass; at least 5 mutants caught (no refusal, `upWait(0)`, a blink ignored, `>` for `≥`, failures ignored) |
| H16 | **Previews,** before and after (from the bundle made by `make-app.sh`, never installed) | Only the Streaming pane (the new section), menu.txt's `remote-away` sample, and the new card samples `remote-away`, `link-behind` and `link-stalled` differ. Look at each |
| H17 | **Hard rules** (grep) | No new Stats key; no `assumeIsolated` or `updateConfiguration` in Sources/SillHost; StreamMessage.swift unchanged by steps 4–9; `standard` has Low and Standard away; `DeviceSettings.accepted` still refuses Direct Wireless from afar; `HostSettingsChange` unchanged |

**Simulator (S):**

| # | Check |
|---|---|
| S1 | **The photo matrix.** `-SillSettingsCase away`, `awaymixed`, `awayhome`, `linkbehind`, `linkmixed`, `linklow` and `linkstalled` (no callout may show), and `-SillLinkLine behind`, at 1000x710, 710x1000, 500x710 and 710x500, and at `content_size accessibility-extra-large` (reset afterwards). Check: the header's lines never truncate; the callout's button is at least 44 pt; the line never covers the bar and nothing crosses y = 500 at 710x1000. Send Noah the sheet |
| S2 | **The reader, live.** A remote session through `sillrelay.py --rate-mbps R`, R such that the first keyframe takes at least 8 s (H0): pair by the typed path through the relay as S3 does. Not `-SillConnect`: it reaches the home door, whose drain rule (4 s, after an 8 s grace) evicts a device whose keyframe takes 8 s, whichever reader it runs. The base build's console shows "connection silent for 6 s: lost" within 30 s; the new build's never in 60 s, its HUD counts frames, and the host evicts nobody |
| S3 | **The callout, live.** Pair by the typed path through a relay (`-SillPairCode … -SillPairAddress 127.0.0.1:RELAY`, the remote plan's S8) to H7's host (away); the relay at H12's rate. The away quality first raised to Balanced from the panel (at Low · Standard there is no button). The callout appears within about 6 s; a headless tap on its button gives "Settings from … away bitrate …" on the host and one restart; the callout goes at once and the line 2 s later, and both may come back 3 s or more after (H12: the synthetic pattern's size does not follow the quality); the console shows the announcement once a spell |
| S4 | **The move home, live.** Pair with H7's host (`SILL_TEST_ORIGIN=vpn`: the remote session is away), then `-SillDialSaved 1 -SillRemoteRoute vpn -SillMoveHomeTest to:[fe80::…%en0]:HOMEPORT -SillScreenFPS 120` (the remote session asks for 60 fps as one through Tailscale does, the home connection for 120). The host logs "Client connected: fe80::…", "Home quality again: …", then "Client left: 127.0.0.1:…"; one "Streaming" line for the flip, right after the home connection's viewport (on the software encoder the stream stays at 60 fps, so the rate's share of that restart shows only on a hardware host with a 120 Hz device); the panel's route line gone and the readout ending in "Wi‑Fi"; "remote: the session moved home". Variants: `refused` (tries at about 2, 12, 32 and 72 s; the session stays remote); `other:PORT` (refused once, not again while listed) |
| S5 | **Connect Remotely stays remote.** `-SillDialSaved remotely -SillMoveHomeTest to:…`: no move in 30 s |
| S6 | **Accessibility.** The header lines spoken as §8 says; the callout and its button; one announcement per spell (DEBUG print) |

**Noah's devices (P), handed over at the end:** the iPad mini; the iPhone for its hotspot and
for P6.

| # | Check |
|---|---|
| P1 | **Pacing on the hotspot** (Tailscale). Pro · Retina, then Extreme · Retina, two minutes each on a busy window (scrolling Safari). Sill.log has no "net.dropped 1 net.sent 3 net.waitKey 5x" every 2 s. The `client iPad` lines stay near what the hotspot carries (≥ 50 fps at Pro where it carries it), and Extreme runs at whatever the link carries rather than a 1–3 fps loop (with PR B, with the link line up). No "Client left" without a real loss |
| P2 | **Liveness on a slow link.** Network Link Conditioner on the iPad (Settings › Developer, a custom profile of 1 Mbps down and 100 ms), at home through Connect Remotely at Pro · Retina (with PR B, pick Pro · Retina away first). The session stays, with slow frames, and never logs "connection silent for 6 s". In the harness the old rule lost such a session about every 10 s. Skip if the Developer menu is not there |
| P3 | **Home unchanged.** Two minutes on home Wi‑Fi at Extreme: `net.dropped` a minute and frame age as before |
| P4 | **Away starts low.** At home set Pro · Retina, then leave for the hotspot. The remote session starts at Low · Standard: "Away from home: …" in Sill.log, the panel's "Away: Low · Standard". `defaults read me.saffer.sill.mac bitrate` still 40000000 |
| P5 | **The away choice.** Pick Balanced away: one restart at 15 Mbps; `awayBitrate` 15000000; the home bitrate unchanged; the next away session starts at Balanced |
| P6 | **Mixed.** The iPad streaming away, then the iPhone connects at home on Wi‑Fi: one restart (a 120 Hz iPhone's rate and the home quality together). The home quality runs; the iPad's header says "Home quality: Pro · Retina (a device at home is connected)". Disconnect the iPhone: the away quality, one restart |
| P7 | **The Mac.** Settings › Streaming shows both sections. Changing the away pickers while the iPad is away restarts once. The menu's Quality subtitle says "Away from home now: …" |
| P8 | **The link.** Away at Extreme. Within about 5 s: the callout with its button, the stream's line, one VoiceOver announcement, and the Mac's card "iPad: … the link can’t carry Extreme". Tap the button: one restart; the callout and the line go; the card's row is normal within about 5 s |
| P9 | **A dip.** Cover the iPhone, or walk away from it, for 15 s. The line appears, then goes about 5 s after the link recovers; no reconnect |
| P10 | **Coming home.** Streaming away through Tailscale, join the home Wi‑Fi. Within about 5 s of the network listing the Mac: "Client connected: fe80::…%en0", "Home quality again", "Client left: 100.x". The route line gives way to "Wi‑Fi"; one restart; drag and type through it (no button stays down, no letters swap); the Mac's card shows the iPad once, "Wi‑Fi". At the edge of the home Wi‑Fi, note how often it goes back and forth (§10) |
| P11 | **Coming home by cable.** An away session; at home, plug the cable in. The move goes to the cable ("Wired"; the Mac logs `%en14` or `%anri0`) |
| P12 | **Connect Remotely at home** stays remote |
| P13 | **Mixed builds.** PR #13's iPad against this Sill.app, away: starts at Low · Standard; its Quality shows Low; no header line. This iPad against PR #13's Sill.app: no header line, no link callout, the move home works |
| P14 | **Extreme through the remote door on a fast path.** Connect Remotely at home through Tailscale's LAN path (rtt under 15 ms), Extreme · Retina picked away, two minutes on a busy window: no `net.dropped` in Sill.log's `[1s]` lines, the `client iPad` lines at its 60 fps. With a 120 Hz device on a remote session by address, the same at 120 fps (§3.2: the harness's host sends over loopback, and a real path's send buffer may stay smaller) |

---

### 12. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

**PR A, "Remote pacing"** (item 1). Branch `remote-pacing` from origin/main after `git fetch`. It
depends on nothing open and can merge first.

0. **Preflight** (no commit): H0.
1. **"Host: remote pacing counts bytes, not messages: a keyframe no longer starves its followers"**
   (StreamServer.swift, `Scripts/pacing/`, and the `SILL_TEST_SOFTWARE_ENCODER` hook if the
   pointer plan has not landed it). About 90 lines of host code and the harness (~700 lines,
   moved). Gates: H1, H2, H3, H4, and H0's keyframe measurement and its check of the hook.
2. **"iOS: the reader takes a message in pieces; liveness counts every byte"** (MessageReader.swift
   new, StreamClient.swift, pbxproj). About 150 lines. Gates: H1, H5, S2.
3. **"docs: remote pacing":** CLAUDE.md (the step, Layout, `Scripts/pacing/`), and
   remote-access-plan.md §4.9(6)'s line (§3.3). Stop here if Noah takes PR A alone.

**PR B, "Away from home"** (items 2–4). Branch from origin/main, which has PR #12 since cea195c,
after PR A or with PR A's commits first. Cherry-pick this plan's commit.

4. **"Protocol: the away quality and the link report in kind 16"** (HostSettings.swift). About 90
   lines. Gates: H1, H6.
5. **"Host: away sessions run the away quality; kind 16 per connection"** (HostConfig,
   DeviceSettings, StreamCoordinator, HostStatus, `sillclient.py`). About 250 lines. Gates: H1,
   H2, H7, H8, H13, H14.
6. **"Host: each device's link"** (StreamServer counters and sweep, LinkJudge.swift new, the
   coordinator's reports, HostStatus, the harness's verdict line). About 300 lines. Gates: H1, H2,
   H3 again, H10, H11, H12.
7. **"Sill.app: the away quality in Settings and the menu; the link on the card"** (HostSettings,
   AppModel, SettingsPanes, StatusItemController, StatusText, DebugHooks). About 150 lines. Gates:
   H1, H9, H16.
8. **"iOS: Away in the panel, the link callout and the stream's line"** (HostSettingsPanel,
   StreamScreen, PortraitStreamScreen, MockCatalog). About 250 lines. Gates: H1, H14, S1, S3, S6.
9. **"iOS: a session away moves home"** (DiscoveryPolicy.moveHome, StreamClient on PR #12's move,
   the harness hooks). About 200 lines. Gates: H1, H15, PR #12's fence check (its twelve modes)
   unchanged, S4, S5.
10. **"docs: away from home":**
    - this plan's Results;
    - CLAUDE.md: the step; Layout (MessageReader, LinkJudge, `Scripts/pacing/`); Build and run (the
      harness, the new `sillclient.py` keys, the DEBUG arguments); Untested, for Noah: P1–P14;
    - README: the away quality, the link callout, coming home.
11. **Review and hand-over.**
    - Three lenses: pacing and link judging on `sill.net` (bytes, completions, the sweep); the away
      flag, the per-connection states and restarts on the main actor; the device's UI and the move
      (fences, the kind 18 check, backoff).
    - A "Review fixes" commit if needed.
    - Then H3, H7, H8, H11, H12, S3 and S4 again on the final build.
    - Hand P1–P14 to Noah. **Stop there.**

**Rebases.**
- **PR #12 (follow-best-path)** has landed (cea195c, after its merge with #13 at f863c74): step 9
  builds on its `MoveKind`, `startMove`/`probeMove`/`finishMove`, `SessionLink` (fences, hold,
  adopt, `Released.close`), `closeSoon`, `rescue` and `upWait` as merged; re-read them (the
  merge changed `rescue` and the reader). MessageReader replaces the merged `readHeader`/
  `readPayload`; the move's probe keeps its own.
- **PR #11 (encoder-recovery)** has landed (b50e224): StreamCoordinator, HostStatus,
  HostSettings.swift (a doc comment), SettingsPanes, StatusText, DebugHooks, `sillclient.py` and
  HostSettingsPanel moved under this plan's line numbers. Its hardware re-check is why the
  software-encoder hook must stop it (§11).
- **update-notice** touches StreamServer, StreamCoordinator, SessionLink and StreamClient, and takes
  kind 23 for its hello, which the pointer plan holds for the menu bar. Not this plan's to settle;
  this plan takes no kind.
- **The pointer plan** (not built) touches StreamServer's tick and SessionLink's input count.

### 13. Hard rules (for every step)

- **The CLI's stdout stays byte for byte** on the default path, idle and streaming, with and
  without `--direct-wireless`. New lines only with `--remote` and a device from a VPN or the
  internet, or on events baseline runs never produce.
- **The home branch of `broadcast` sends and drops exactly what it does today.** Item 3 only
  counts there.
- **Kinds unchanged;** new fields optional; `HostSettingsChange` unchanged; no enums on the wire.
- **Only the Mac widens exposure.** Nothing here is device-writable beyond the qualities a device
  could already set.
- **Never `MainActor.assumeIsolated`** in core code; never reconfigure a running SCStream.
- **Tests never use the hardware encoder** while Noah may be streaming (H2's rule aside), never
  touch Sill.app, his defaults domain, keychain or iPad.
- **New iOS files** need their four pbxproj entries by hand. Swift 5 language mode. Apple
  frameworks only; the test tools use the Python standard library and the system `openssl`.

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **An rtt exception:** should a remote session whose round trip looks like the LAN keep the
   home quality (the 14:02 case)? Default: **no.**
   - Item 4 moves such a session home about 2 s after the network lists the Mac, which covers
     14:02.
   - An exception would need the device's rtt on the host (the median of five one-second medians
     under 20 ms, say). It would flip, and restart, whenever Tailscale re-paths between DERP and
     direct.
2. **Automatic step-down.** Default: **off** in this bundle: the callout and its button first.
   The alternative (§6.9) steps a remote session down one preset after 3 drops in 10 s, not saved,
   and says so.
3. **With a device at home and one away,** the home quality runs. Default: **yes,** as decided.
   The away device's picks then set the away quality, which applies once every device is away, and
   its panel says so.
4. **Only Quality and Resolution split.** Default: **yes.** The frame rate limit, Prioritize
   Encoding Speed and the virtual display stay shared; devices away ask for 60 fps anyway.
5. **The Mac can set the away quality** in Settings › Streaming. Default: **yes, not in the menu.**
   The menu's Quality and Resolution stay the home ones, and the subtitle says when the away one
   runs.
6. **A VPN into the home router** reaches the remote door as "by address", so it counts as home.
   Default: **home.** The alternative counts a routed private source (not on this Mac's link) as
   away; OriginPolicy would have to tell the two apart.
7. **Link state for devices at home too.** Default: **yes,** every device. At home the button
   lowers the home quality, as a menu click would. The alternative judges remote devices only.
8. **The suggestion's headroom.** Default: **70 %** of what the link carried. The alternative is
   80 %: higher suggestions, more drops near capacity.
9. **The stream's line.** Default: **non-interactive**, so it never takes a touch meant for the
   Mac. The alternative opens Settings on a tap.
10. **The move home checks kind 18** (the pinned key, as new as the session's). Default: **yes.**
    It costs a millisecond and stops a tag and a kind 18 captured before this session. A device
    on the home network can still fetch fresh ones from the Mac's home door and relay them: the
    home door stays plaintext until M5.
11. **Ship PR A (pacing) on its own first.** Default: **yes.** It is independent of PR #12, and it
    removes the livelock for every build of the device.
12. **The 512 KB hold cap** keeps up to about a second of Low's deltas behind a keyframe instead of
    dropping them: an exception to "Latency beats quality", remote clients only. Default: **keep
    it,** as the investigation measured. The alternative cap at 256 KB was not measured. A case at
    its edge is bistable (bigkf8, §3.2: five runs of six at 60 fps a second or two behind, one in
    the 2 s loop at ~30 fps and ~3 s behind); a larger cap would keep such a case out of the loop
    at the price of more lag behind every keyframe, a smaller one drops sooner. Neither measured.
13. **The link as the device counts it** (an optional `ClientStats` field: the bytes MessageReader
    read in each second). Default: **no:** the host's view (§6.1), where stalled needs the device
    silent too. The device's count would be exact where `.contentProcessed` sees only whole
    messages, and would tell a path down only towards the device from a slow one; it is a wire
    field (optional, compatible both ways) and more device code.
14. **A link only a little too slow** (found building PR B; "Results: PR B" has the runs). Behind
    needs 3 short seconds of 5, and under PR A's pacing such a link loses frames in rounds, which
    can leave fewer than 3 short in any 5. Default: **the rule as planned.** The alternative adds
    "or a fifth of the last 5 seconds' frames withheld".

---

## Results: PR A (remote pacing)

Built on `remote-pacing`, from main at 150f781 (2026-09-26): the host (72d469c), the harness
(5e8255b; review fixes 1e2e649, 556cc7c, d8dcf2a, 5d18b11), the device's reader (c5326df; review
fix e3a49ef), a comment (911202e), then main at cf05a78 merged in (7e577c5) and these docs
(b0fd105), main at 676b362 merged in (07fe32f, no source of the host or the device changed), the
review's two cases (a81a58f) and fixes (24dee3c, a933a4f), and main at 2b38179 merged in (dc471fa:
PRs #30–#33, the Mac's pointer among them, whose reports go out like ticks, outside `send`). Items
2–4 are PR B's, whose Results follow these.

### Defaults taken

Open questions 11 (PR A first, on its own) and 12 (the 512 KB hold cap kept), at their defaults.
The others are PR B's.

### Where the build departs from the plan, and why

- **Everything a test starts listens on 127.0.0.1 only:** the harness's door (TLS, `--plain` or
  `--home`) and both relays. StreamServer's own listener, which takes connections on every
  interface, is never started in the harness: `--home` serves each connection of the loopback door
  as a home client (`serve(_:route: .home(.loopback))`: the home branch of `broadcast` and the home
  eviction rule), where the harness first used that listener.
- **No synthetic host ran:** a synthetic host's doors listen on every interface, and its stream
  shares the hardware encoder with Noah's Sill.app. So:
  - **H2 ran only after the merge with main at 2b38179,** whose `SILL_TEST_LOOPBACK` and
    `SILL_TEST_SOFTWARE_ENCODER` (PR #31) let a synthetic host listen on 127.0.0.1 alone and never
    touch the hardware encoder. Before that it was argued from the code: the CLI opens no remote
    door without `--remote`, every change here is inside `paceRemote`, an `if remote` in `send` or
    the remote sweep, which only a remote client reaches, and the new `Client` fields are touched
    nowhere else. Run then (main's CLI against this branch's, both from clean builds, both hooks
    on, one run each): idle for 35 s, identical masked and sorted (7 lines); with `sillclient.py
    PORT 5 desktop`, identical (18 lines), and the client's own output identical but for the order
    its tally lists the kinds it met (a pong or the window list first). The `--direct-wireless`
    runs were left out: the listener is not this branch's.
  - **H4 ran in the harness:** `relay2` and `blackhole` put Scripts/sillrelay.py (2 Mbit/s,
    +150 ms) between the harness's host, the same StreamServer.swift, and its device, instead of a
    paired `SillHost --synthetic --remote`, at a synthetic host's sizes (100 KB keyframes, 2 KB
    deltas).
  - **No `SILL_TEST_SOFTWARE_ENCODER` hook,** and so no H0 keyframe measurement: no gate here needed
    one. PR B's gates (H7–H13, S3–S5) do, and a synthetic host that listens on loopback only; the
    pointer branch has an implementation of the hook (`PointerWatch.swift`, unverified, not merged).
- **S2 ran against the harness's host** (its plain remote door, so StreamServer serves the app as a
  remote client) with the app dialling it by address (`-SillConnect`), through bottleneck.py at
  2 Mbit/s: a 1.7 MB first keyframe, 6.8 s on the link, then 1 KB deltas at 60 fps. The fake
  catalog and frames do not decode, which the app skips; its liveness needs only bytes, and its
  HUD counts the frames that arrive ("no video").
- **The relay keeps a virtual clock** (bottleneck.py): the investigation's slept once per 16 KB
  chunk, so every late wake-up was a pause of the link, and at 600 Mbit/s the Extreme cases became
  a path with random stalls (ext120 on the base ran at 7–120 fps from run to run; with the clock,
  119–120 fps and 8.6 drops a minute every time, as the critique measured).
- **low, switch and home are one-sided gates** (no worse than the base run, within 2 fps and a drop
  a minute): with the clock the base loops in switch's Pro-sized half (27.5 fps against 60.0).
- **MessageReader,** beyond §3.4: an end that comes with a message's last bytes is the end then
  (the old reader read once more and printed the ENODATA as "read error" after a clean close), and
  it is reported only while `stillReads` holds, so a message that stops the reading (a move's fence
  coming back) is never followed by an end for a connection that is no longer the session's.
  `onBytes` passes the count. H5's slow case is a 1 MB frame at 2 Mbit/s (the plan's 3 MB at
  1 Mbit/s would take 24 s), and the check has 17 mutants where the plan asks for 5.

### Review (2026-09-27)

An adversarial pass before the pull request, over the pacing's arithmetic and edge cases,
starvation and bufferbloat, home sessions and the device's reader. It found two faults. Each got a
harness case first (a81a58f), which fails on the build before its fix, and then the fix:

1. **A restart while a keyframe was still being taken** (24dee3c). `paceRemote` kept one keyframe
   in flight, the last one sent. A stream restarted while one was still being taken (a pick, a
   rotation, a settings change: `resetForNewStream`) sent its first keyframe at once and forgot
   the one before it, whose bytes then counted as backlog waiting beyond the new one. The new
   stream's first delta was over the hold cap and dropped, and the device kept the new keyframe's
   picture until a third keyframe, asked for once everything had drained. The client now keeps
   every keyframe it is still taking (`keyframesInFlight`, their bytes in
   `keyframeBytesInFlight`), the hold cap counts what waits beyond all of them, and the floor is
   set once the last of them is taken. restartkf (2.5 MB keyframes, 4 KB deltas, 32 Mbit/s, the
   stream restarting 0.1 s after a keyframe three times), three runs each: the build before
   dropped a delta at every restart, 9 of 9 (54.7–56.2 fps, 136–152 `net.waitKey` after the first
   keyframe); the fix at none (60.0–60.1 fps, no `net.waitKey` after the first keyframe). With
   1.5 MB keyframes, 8 KB deltas and 20 Mbit/s, where this Mac's loopback buffers take most of a
   keyframe within the 0.1 s, the build before dropped at 3 of 9 restarts and the fix at none.
2. **A still window right after a drop** (a933a4f). A remote client that lost a frame asked
   for its keyframe only when a later frame came (`paceRemote`), once its queue had drained. When
   the window went still right after the drop (the end of a scroll, the last letters typed), no
   later frame came, and the device kept the picture from before the drop until the window next
   changed. Main has the same rule: it asked on the same later frame. A home client asks at the
   drop itself. The remote sweep, once a second, now asks too, on the same terms: a keyframe
   wanted, not a restarted stream's first, the queue at most `remoteIdleBytes`, the request due.
   The encoder then encodes the still window's last frame again (HEVCEncoder.requestKeyframe, once
   nothing has repainted for 50 ms). stillend (1.5 MB keyframes and 60 KB deltas on 16 Mbit/s, so
   frames are dropped all along; the window still for 8 s three times), three runs each: on the
   build before (24dee3c) the device kept the older picture through every still spell, 9 of 9,
   and 9 of 9 on 07fe32f; with the fix it showed the last frame, encoded again, within 2.2 s of
   each spell's start, 9 of 9 (2.2–2.3 s against 07fe32f).

**Looked at and left as they are:**
- **The byte counts.** Every message `send` hands over adds its size to `pendingBytes`, and its
  completion takes the same size away. Both run on `sill.net`, and a connection's completions come
  in order, so the count neither drifts nor goes negative, and a keyframe's completion means
  everything queued before it was taken. Ticks bypass `send`: 14 bytes, at most every 30 ms.
- **Bufferbloat.** Behind keyframes being taken, what Sill holds for a remote client is at most
  those keyframes and 512 KB. With none, it is at most 256 KB, or the floor and 128 KB. The floor
  is set only as the last keyframe being taken is taken, to what waits behind it: at most 512 KB
  and a delta. Several keyframes are in flight at once only while their deltas stay under the cap,
  and deltas reach it within about a second. In one ad hoc run where the keyframes alone exceed
  the link (1.6 MB every 4 s with 2 KB deltas on 2 Mbit/s, 60 s, not a case), the build before
  the review had a frame age of 11.3 s at the median and 17.1 s at p95, the final tree 10.8 and
  13.9 s: keeping every keyframe lets no queue grow that keeping one did not. Both are a stream
  the link cannot carry. The kernel's send buffer (autotuned up to 4 MB here,
  `net.inet.tcp.autosndbufmax`) and the network's queue come on top, unseen (§3.7).
- **Starvation.** A client waiting for a keyframe takes the encoder's own (every 4 s of frames)
  whenever its queue is under the budget. So traffic that keeps its queue over `remoteIdleBytes`
  (thumbnails on a slow link) delays its request, never its recovery. The loops left are a stream
  bigger than the link (over8, stillend) and the bistable edge of §3.2.
- **Home sessions.** Every change is inside `paceRemote`, an `if remote` in `send` or the remote
  sweep, whose timer runs only while a remote client is connected. No new print or Stats key.
  The harness's home case (a home client over plain TCP: the home branch and the home eviction
  rule) after the review: 60.1 fps on both builds, nothing dropped, the worst frame age of a
  second 15 and 18 ms at the median.
- **The device's reader:** its pieces, caps, ends and `stillReads`, its queue (every connection it
  reads starts on the client's network queue) and its lifetime (held by its pending read).
  Unchanged; the check's 46 cases and 17 mutants ran again.
- **bottleneck.py's comment** said macOS kept its 64 KB receive buffer. It does not: on loopback
  the buffer held 340–590 KB whatever SO_RCVBUF said, set before connecting or after. So the path
  holds 0.7–1 MB in the host's send buffer and the relay's receive buffer besides its queue. The
  comment says so now. The relay is unchanged, so every figure here stands.
- **The plan's example line** for "Home quality again" carried a real device's link-local
  address; it has a made-up one now.

### Verified

On this Mac (an M2 Pro), 2026-09-27, with no device, simulator recording or video encoder involved:

- **H1, the builds,** before the merge (5d18b11), on it (7e577c5) and after the review (a933a4f):
  `swift build -c release` from clean, only the CaptureProbe warning; the iOS app for the
  simulator, Debug and Release (arm64, unsigned), only the old `StreamClient` capture warning.
- **H3 and H4, the harness** (`Scripts/pacing/run.sh --full`, against origin/main at cf05a78 on the
  merge and at 676b362 after the review, whose StreamServer.swift is 150f781's both times). Each run
  started with the load average under 20, and one that ended at 20 or more ran again, twice at
  most. fps is the device's mean after its first 5 s; drops are the host's `net.dropped` a minute.

| Case | On the merge (7e577c5), base → new fps | After the review (a933a4f), base → new fps | New drops a minute, after the review | Gate (new) |
|---|---|---|---|---|
| real24 (×3) | 19.0, 7.7, 31.3 → 56.6, 59.3, 59.4 | 45.1, 53.9, 53.1 → 59.3 ×3 | 0 (base 2.9–5.9) | ≥ 55 fps, none dropped: pass; 14.6 keyframes a minute |
| kf25m32 (×3) | 1.5, 1.4, 1.5 → 60.1 ×3 | 1.3, 1.5, 1.4 → 58.2, 60.1, 59.9 | 0 (base 28.3) | ≥ 55 fps: pass |
| bigkf8 (×3) | 1.9, 1.9, 1.6 → 59.8, 59.8, 59.9 | 24.5, 18.2, 18.3 → 59.8, 59.9, 59.8 | 0 (base 20.5–22.0) | each ≥ its base run: pass |
| slowkfB | 0.4 → 64.8 | 0.4 → 64.8 | 0 | ≥ 55 fps after the first keyframe (67.9), no liveness loss: pass |
| slowkf | 0.0 → 0.0 | 0.0 → 0.0 | – | recorded: the old device's rule lost the session 5 times on either host |
| ext120 | 119.9 → 120.0 | 119.8 → 120.0 | 0 (base 5.7) | ≥ 115 fps, none dropped, no `net.waitKey` after the first keyframe: pass |
| ext60 | 59.9 → 60.0 | 59.7 → 60.0 | 0 (base 11.4) | the same at 60 fps: pass |
| fastbig | 60.0 → 60.0 | 60.0 → 60.0 | 0 | pass |
| dip | 50.3 → 52.8 | 50.3 → 52.8 | 1.1 (base 3.2) | no loss or eviction, the frame age back at 45 ms 6.0 s after the dip (base 4.0): pass |
| over8 | 1.7 → 4.9 | 1.7 → 4.9 | 27.8 | recorded, ≥ the base: pass |
| low | 60.1 → 60.1 | 60.1 → 60.1 | 0 | no worse than the base: pass |
| switch | 36.5 → 60.1 | 59.4 → 60.1 | 0 (base 0) | no worse than the base: pass |
| home | 60.0 → 60.0 | 60.1 → 60.1 | 0 | no worse than the base: pass |
| relay2 (H4) | 61.4 → 62.3 | 61.5 → 62.1 | 0 | no loss or eviction, a frame every second, 15.3 keyframes a minute (base 15.9): pass |
| blackhole (H4) | dropped at 13.1 s on both | dropped at 13.1 s on both | – | dropped for its silence 11–16 s after connecting: pass |
| stillend (review) | – | 1.4 → 6.0; the last frame shown in 0 → 3 of 3 still spells | 17.6 (base 16.5) | every still spell ends with the last frame shown, within 5 s (2.2 s): pass |
| restartkf (review) | – | 1.6 → 60.1 | 0 (base 33.3) | none dropped, no `net.waitKey` after the first keyframe: pass |

  - Before the merge (5d18b11) the same cases ran with the same verdicts (that column is in this
    file at b0fd105); the matrix ran in three pieces, since other work on this Mac held the load
    average at 200–700 for over twenty minutes.
  - On the merge one base run, kf25m32's second, was skipped after its retry waited 20 minutes for
    the load; its first try, which ended with the load at 31, ran at 1.4 fps.
  - After the review other work on this Mac lifted the load average past 100 every ten minutes or
    so: eight runs ended over 20 and ran again, and every run kept ended under 17.
  - The base's loop depends on timing: real24 and switch fell into it less often after the review
    than on the merge (switch not at all), while kf25m32 and restartkf (2.5 MB keyframes) looped
    in every run. The new build's figures stayed where they were.
  - bigkf8 was in the good state in all nine runs of the new build (§3.2 found it bistable), with
    a frame age of 0.6 s at the median and 1.5 s at p95: the standing queue of §3.7.
  - relay2 has a standing queue in the host's send buffer on both builds, since sillrelay.py reads
    through a 64 KB buffer as in the remote plan's H14: the pong's round trip at p95 was 1.2 s on
    the new build and 1.3–1.4 s on the base, on the merge and after the review.
- **H5, the reader** (`Tests/checks/message-reader`): 46 checks, and 17 of 17 mutants caught (the
  plan's five among them), before the merge, on it and after the review. The pull request's first
  CI run failed its slow case on GitHub's macOS runner ("delivered (15.0 s)"): the stand-in wrote
  each 4 KB 16 ms after the last was taken, so every late timer slowed the frame. Its writers now
  keep to the clock (4ca5124); with every timer 44 ms late the old pacing failed as CI did and the
  new one delivered in 4.2 s, and here the check passed 40 runs in a row, 17 of 17 mutants caught.
- **S2, the reader live,** on a private iPad mini simulator (iOS 27.0), origin/main's app and then
  this branch's against the same harness host: origin/main's lost the session 7.3 s after
  connecting ("connection silent for 6 s: lost"; 7.2 s on the merge's run) while 1.8 MB came
  through; this branch's never did in 60 s. Its first keyframe landed about 8 s in, then it ran
  at 60 fps with a frame age of 40 ms (the app's own stats, and its HUD counting frames, "no
  video"), and the host evicted nobody. Before the merge and on it; after the review, this branch's
  app alone against the final host: no loss in the 57 s it ran, its first frames 9 s in, then
  59–60 fps at a frame age of 40–46 ms, nobody evicted.
- **The pure checks** (`Tests/checks/run-all.sh`): all 16 pass, before the merge and on it; all 17
  after the review (`dmg-layout` came with main at 676b362).
- **On the merge with main at 2b38179** (dc471fa; PRs #30–#33, the Mac's pointer among them):
  `swift build -c release` from clean and the iOS app for the simulator, Debug and Release, with
  only the known warnings; all 21 pure checks (main's four new ones among them); the harness's gate
  cases and home against origin/main at 2b38179, one run each, every gate passing (real24 27.5 →
  59.3 fps, kf25m32 1.5 → 60.1, bigkf8 7.8 → 59.8, restartkf 1.6 → 60.1, stillend 0 → 3 of 3 still
  spells, slowkfB 0.5 → 64.8, ext120 119.9 → 120.0, dip back at 45 ms 6.0 s after it, relay2 61.4
  → 62.4 with no loss, the blackhole dropped at 13.1 s on both, home 60.0 on both); and S2 once
  more, this branch's app against the merged host: no loss in 60 s, its first frames 9 s in, then
  about 60 fps at a 40 ms frame age.

### Not verified here, for Noah

On his devices: P1 (pacing on the hotspot at Pro and Extreme · Retina), P2 (liveness on a
1 Mbit/s link), P3 (home unchanged at Extreme) and P14 (Extreme through the remote door on
Tailscale's LAN path, at 60 fps and, from a 120 Hz device, at 120). From the review, on the hotspot
too: a scroll that stops settles on where it stopped within a few seconds, and a pick or a rotation
while it scrolls keeps moving from the new stream's first picture. Nothing here ran on a device,
the hardware encoder or a real path: the harness sends over loopback, whose kernel buffers take
0.7–1 MB the pacing never sees, and a real path's send buffer may stay smaller (§3.2).

---

## Results: PR B (away from home)

Built on `remote-away`, from `remote-pacing` at c564142 (PR A, #34, open) on 2026-09-27, one
commit per step: the wire (340f98b), the host's away quality and per-connection states (934f997),
each device's link (98290b6), Sill.app (0e5d4ce), the device's panel, callout and line (6222d7c),
the move home (2e40673) and these docs, then the review (below). It stacks on PR A: its
pull request is against `remote-pacing`, and GitHub moves it to main once PR A merges.

### Defaults taken

Open questions 1–10 and 13 at their defaults: no rtt exception (the move home covers 14:02), no
automatic step-down (the callout and its button), the home quality while a device at home is
connected, only Quality and Resolution split, the away pair in Settings › Streaming and never in
the menu, a VPN into the router counts at home ("by address"), every device's link judged (at home
the button lowers the home quality), 70 % headroom, a line that takes no touch, the move home's
kind 18 check, and the host's view of the link (no device-side byte count).

### Where the build departs from the plan, and why

- **SILL_TEST_REMOTE_ORIGIN=vpn|internet** (new, TEST ONLY, a host that does not advertise): the
  remote door alone counts loopback as that origin, the home door keeps it at home. A test host
  listens on loopback only (SILL_TEST_LOOPBACK), so SILL_TEST_ORIGIN, which applies to both doors,
  could not give one host a device at home beside one away. H8's home client and S4's home door are
  127.0.0.1 through the home door, not this Mac's `fe80::…%en0`, which a loopback-only host
  refuses; the readout after S4's move therefore has no route word (lo0), where the plan expected
  "Wi‑Fi".
- **SILL_TEST_PATTERN=noise** (new, TEST ONLY, a synthetic host): a square of random pixels, a third
  of the frame's height on a side, new every frame. The plan set H12's relay at half the synthetic
  stream's rate, but the sweeping bar compresses to about 56 kbit/s whatever the quality, and a
  relay at 28 kbit/s would take minutes to carry the catalog. With the square the software encoder
  keeps about 14 frames a second at 1512×948, about 3.6 Mbit/s at Low and 10.6 at Balanced, so a
  lower quality makes a smaller stream (H12, S3). An earlier try, 8-pixel blocks over the whole
  frame, left the encoder at 8 frames a second and the stream at its own size whatever the quality.
- **H2 on the software encoder** on both builds (SILL_TEST_SOFTWARE_ENCODER, with
  SILL_TEST_LOOPBACK): this session kept off the hardware encoder altogether, which Noah's Sill.app
  shares. The kind 16 lines and their count are the ones H2 compares, and they do not depend on the
  encoder.
- **The link's reports.** LinkJudge reports the carried rate again during a spell once it has moved
  by a quarter (`carriedMove`): the harness showed the first measure reading high while the buffers
  between the host and the link filled (12 Mbit/s on an 8 Mbit/s path), and a suggestion made from
  it stood for the whole spell. The coordinator publishes a report only when its state or its
  suggestion changes, so the device and the card see no report that only moved the rate. A report
  judged at a quality that is no longer the target (a pick has just changed it, and the restart's
  reset follows within milliseconds) is left out of kind 16, so the answer to the pick that lowers
  the quality already carries none (H12 found the answer carrying the old report).
- **H11's gates for a slower path, restated.** The host judges only what it withholds, and it
  withholds nothing while the buffers between it and the slower link fill: the dip's 1 MB queue and
  the loopback's socket buffers took 5.9 s, the stopped downlink's 256 KB queue 2.9 s. Behind comes
  at the third short second after that, so the dip and the downlink's stop are gated at "behind
  within 3 s of the end of the host's first second withholding frames" (2.2 s both), not "within
  5 s of the change" (8.0 and 5.0 s); the dead path at "stalled within 8 s" (5.0 s), not 4. The
  harness prints how long the buffers took beside each.
- **H12's rate.** At the plan's half of the stream (5 Mbit/s against Balanced's 10.6) the report
  came 4.8 s after the pick's answer, inside the 6 s gate. At 6 Mbit/s (1.8 times over) it took 8.1
  and 8.6 s in two runs: PR A's pacing drops, waits for the backlog to drain, then sends a keyframe
  and a second or two of deltas the buffers absorb, so clean seconds fall between the short ones and
  the third short second of five comes in the next round. A link only a little too slow for the
  quality may never show three short seconds in five (open question 14, below). In every H12 run
  the carried rate went unmeasured (seconds rarely end with 16 KB waiting while the pacing drains
  the queue before each keyframe), so the suggestion was one step down (Efficient from Balanced).
- **The move home refuses another launch at its window list,** before its kind 18: a host without a
  remote door sends none, and the move waited out its 5 s and counted as a failure (S4's `other:`).
  Its test row (`-SillMoveHomeTest`) is named "‹Mac› (home test)": on this Mac the simulator's
  browser also lists Sill.app under the Mac's name, and a row of the same name hid it.
- **The fence check** gains two modes, `remotehome` (the fenced hand-over from a TLS connection to a
  plain one, the old one closed once what waited went out) and `remotedead` (the remote connection
  gone mid-move: held, adopted, delivered): 17 modes.
- **Headless taps:** `-SillSettingsScript '<t> set K=V | suggestion; …'` (DEBUG, under
  `-SillInputScript`'s guard: a loopback session to a host with no version) takes the panel's
  controls, and the callout's button, for S3. The device's console prints "link: behind (cannot
  carry Pro; suggesting Low · Standard)", "link: keeping up" and "link: the stream's line “…”
  (announced)" (§6.8).
- **S1's phone sizes** on the iPad simulator with `-SillIdiom phone` (the harness's way to draw a
  phone's layout on a larger simulator): 440x894 upright and 956x440 on its side.
- **H16 from the bare binary,** with the SDK recorded by vtool as make-app.sh does and signed ad hoc,
  base and new at one path, instead of the bundle: the bundle's defaults domain is
  me.saffer.sill.mac, and make-app.sh signs with the login keychain's identity.
- **The footnote's qualities are kept whole** (no-break spaces) like the header's: S1 at 1000x710
  wrapped "Low" and "· Standard." onto two lines.

### Verified

On this Mac (an M2 Pro), 2026-09-27; no device, no hardware encoder, no Sill.app; every host on
loopback alone, on the software encoder, killed by PID.

- **H0.** H2's and H3's base is origin/main at 2b38179 (its StreamServer.swift is PR A's base), built
  from `git archive`; H16's is c564142 (`remote-pacing`), the branch point.
- **H1, the builds:** `swift build -c release` of each step's tree from clean, only the CaptureProbe
  warning; the iOS app for the simulator, Debug (signed ad hoc, for the keychain) and Release, only
  the old `StreamClient` capture warning; step 8's sources, which leave out the move home, also
  typechecked on their own for Debug and Release.
- **H2** (the step 6 host against origin/main's CLI, idle 35 s and with `sillclient.py PORT 5
  desktop`, with and without `--direct-wireless`): every line but the stats lines identical, masked
  and sorted; the stats lines' count within one; the client's kind 16 lines, their count (2) and
  its first kinds identical: 14 of 14.
- **H3, the harness** (`Scripts/pacing/run.sh --full --base origin/main`, the step 6 tree; each run
  started with the load under 20, four ran again after other work lifted it past 75): every pacing
  gate passes, and the new build's figures are PR A's: real24 56.4, 60.0, 36.4 → 59.3 ×3 fps (no
  drops); kf25m32 1.5 ×3 → 60.1 ×3; bigkf8 35.2, 19.0, 7.3 → 59.8 ×3; slowkfB 0.5 → 64.8; ext120
  120.0 → 120.0 (base 2.9 drops a minute, new none); ext60 59.8 → 60.0; fastbig 59.9 → 60.1; dip
  50.5 → 52.8, the frame age back at 45 ms 6.0 s after it; relay2 61.4 → 62.4 with no loss; the
  blackhole dropped for its silence on both; stillend 3 of 3 still spells; restartkf 1.6 → 60.1;
  over8 1.8 → 4.9; low, switch and home no worse (60.1, 60.1, 60.1).
- **H6:** `Tests/checks/away-wire`, 47 checks, 9 of 9 mutants (step 4).
- **H7** (away): 12 of 12, on step 5 and on the final build: "Away from home: …" once, the stream at
  4 Mbps, the pick of Balanced answered in the away pair and restarting once at 15, the home
  bitrate untouched. **H8 and H13** (mixed): 24 of 24: the home client joining brings "Home quality
  again" and one restart (0.01 s after its viewport, 1.01 s without one), the away one back when it
  leaves, each client its own pair.
- **H9** (the bare app, domain `SillMenuBar`, its own log file, `-remoteAccess 1` for the run): 12 of
  12: away at Low · Standard; a device's Balanced saved as `awayBitrate`, with `bitrate` and
  `remoteAccess` never written; after a relaunch away at Balanced; a SetAfter of the away pair one
  "Settings: away bitrate 15 → 8 Mbps per 60 fps, away points → Retina" and one restart; the domain
  emptied after.
- **H10:** `Tests/checks/link-judge`, 74 checks (the plan asked for 34), 22 of 22 mutants (its ten
  among them).
- **H11, the link in the harness** (the new build's Link lines): real24 (three runs), slowkfB,
  linkstill and home never behind or stalled; over8 behind 3.0 s after its first keyframe, the
  carried rate 7.1 Mbit/s on 8 (the median of 27 reports), Low suggested for Pro; the dip behind
  2.2 s after the host's first second withholding frames (5.9 s into the dip) and fine 6.0 s after
  its end; the downlink's stop behind 2.2 s after the host's first such second (2.9 s after the
  stop), never stalled; the dead path stalled 5.0 s after the blackhole.
- **H12** (end to end, a noise host away, sillrelay.py at 5 Mbit/s and 40 ms): 14 of 14: behind 4.8 s
  after the pick of Balanced was answered, "Link to sillclient (sillclient): cannot carry Balanced
  (withheld 3 of 13 frames in the last second); suggesting Efficient.", one line for the spell,
  never stalled; the pick of Low one restart, its answer without a report, no "keeping up again",
  and at Low 4.3 Mbit/s through the relay with nothing behind. At 6 Mbit/s (two runs) 13 of 14:
  behind 8.1 and 8.6 s after the pick.
- **H14:** the ledger check, 90 with its 5,000 random runs; the policy check, 286 before and 303
  after (the move home's 17).
- **H15:** `moveHome` in the policy check (1.9 s no, 2.0 s yes, a blink restarting the count, retries
  at 10, 20, 40, 60 and 60 s, a refused listing never, a new listing afresh, a model of the glue),
  and 76 of 76 mutants, its six among them (the first run missed "upWait(0) with no failure": a case
  for a listing that begins a moment after a try catches it).
- **H16:** previews from c564142 and this branch, each bare binary with the SDK recorded by vtool and
  signed ad hoc, at one path: only `pane-streaming` (light and dark) and `menu.txt` (the
  `remote-away` sample) differ, and six cards are new (`remote-away`, `link-behind`,
  `link-stalled`); each looked at.
- **H17:** no new Stats key; no new `assumeIsolated` or `updateConfiguration` in Sources/SillHost
  (HostShutdown's one is older); StreamMessage.swift and `HostSettingsChange` unchanged since
  c564142; `standard`'s away pair Low · Standard; DeviceSettings still refuses Direct Wireless
  from afar.
- **The fence check:** 17 modes (remotehome and remotedead new), and 32 of 32 mutants over them.
- **The pure checks** (`Tests/checks/run-all.sh`): all 25 pass (the four new ones among them).
- **S1:** 144 photos of the harness's mock on a private iPad Pro 13-inch simulator (iOS 27.0): the
  seven cases and both lines at the Duo's four sizes, the iPad's two and an iPhone's two, at the
  default and accessibility-extra-large text (the sheets went to Noah). The header's lines wrap and
  never truncate; the button is 44 pt (88 px at 2×, measured); the line sits inside the stream
  panel, clear of the bar; at 710x1000 nothing crosses the fold.
- **S3** (the noise host away through sillrelay.py at 3 Mbit/s; paired by the typed path through the
  relay): 18 of 18. With the panel closed the report came 10 s after the pick of Balanced (the
  software encoder kept 6 to 12 frames a second beside the simulator), the line showed and was
  announced once; the callout's button ("Use Low") restarted the stream once, the report cleared
  at once and the line 2 s later; at Low the link was behind again 5 s on ("The link to ‹Mac›
  can’t keep up.", its own spell and announcement). With the panel open the callout showed, its
  button ("Use Efficient") restarted once, and the callout went at once.
- **S4** (the move home; a host whose remote door counts loopback as a VPN): the listing 1.9 s into
  the session, the move 2.1 s after it by the row as listed, the fence down by its pong after 1 ms;
  the host: the home connection, "Home quality again", one restart at 15 Mbps, then the remote
  connection left; the panel's route line and away line gone, the Quality Balanced · Retina.
  `refused`: tries 2.0, 12.2, 32.2 and 72.2 s after the listing, the session staying remote;
  `other:`: refused once at its window list, no second try in 30 s. **S5:** `-SillDialSaved
  remotely`: no move in 30 s.
- **S6:** the spoken labels ("…, away quality, Low, Standard", "Use Low, Standard") in the away-copy
  check; one announcement a spell in S3.

### Where home pairing meets this (branch `home-pairing`, PR #37)

When both have landed, whichever merges second:
- **The routes.** home-pairing's `ClientRoute.home(origin, peer:)` carries the TLS key; AwayPolicy
  reads only `isRemote` and `origin`, so `ClientRoute.isAway` (StreamCoordinator.swift's last lines)
  stands as it is: a TLS home session is at home.
- **The move home dials a TLS home door.** `startMove` makes its connection with
  `moveParameters()`, the session's home trust, and a remote session has none (`Session.home` is
  nil for it, so plain), which a TLS home door refuses. The move home takes
  `HomeTrust.saved(pin:)` with the saved Mac's key (the one the remote door pins too), says its
  hello inside TLS, and sets `session.home` at the hand-over; with TLS a connection is ready before
  the Mac has judged the key, so the probe's window list is still what admits it. The pinned
  handshake then proves the Mac, and the kind 18 check (§7.3) says it a second time: keep it (a
  millisecond) or drop it.
- **`receiveMacInfo`** was restructured there (`macInfoNamesSession`, `connectionKey`): the away
  branch's two lines (a remote session's newest `issuedAt`, the first one starting the move home)
  go after its `macInfoSaved = true`.
- **Kind 16 per connection and the flip.** home-pairing's serve gate admits a TLS home session only
  after its hello; the flip's wait for the new connection's first viewport (§5.4) counts from its
  registration, so it is unchanged. Its `HostStatus` and `StatusText` changes meet this branch's
  `Device.link`, `LinkStatus` and `linkWords` in the same structs: keep both.
- **The Settings panel.** home-pairing edits HostSettingsPanel's header and footers (37 lines),
  MockCatalog's cases and ContentView's harness docs, the places this branch adds the away line,
  the callout, the footnote and seven cases: a textual merge, both kept.
- **Connect Remotely at home** stays remote on both (`DialReason.connectRemotely`); home pairing's
  cable pairing and asks never go through the remote door, so no move home starts from them.

### Open question for Noah

14. **A link only a little too slow.** Behind needs 3 short seconds of 5, and under PR A's pacing
    a link that carries most of the stream loses frames in rounds (drop, drain, keyframe, a second
    or two of deltas), which can leave fewer than 3 short seconds in any 5: the picture stutters
    and no callout comes. Default: **the plan's rule, as built.** The alternative adds "or at least
    a fifth of the last 5 seconds' frames withheld", which would have reported H12's 6 Mbit/s runs
    at about 4 s.

### Not verified here, for Noah

On Noah's devices, the plan's P4–P13 (P1–P3 and P14, PR A's, are still open): away starting at Low ·
Standard with the home bitrate untouched (P4); the away choice kept (P5); mixed home and away, one
restart each way, the iPad's header (P6); Settings › Streaming's section and the menu's subtitle
(P7); the link at Extreme away: the callout, the line, one announcement, the card's row, the
button's one restart (P8); a dip (P9); coming home on Wi‑Fi and by the cable, dragging and typing
through the move (P10, P11); Connect Remotely at home staying remote (P12); mixed builds (P13).
Nothing here ran on a device, a real path or the hardware encoder: the link's timing on a hotspot,
the move's on a real network, and VoiceOver on a device are all untested.
