# Away from home: pacing, the away quality, the link, coming home — the plan

2026-09-25. It stands alone: the implementer needs no other design document. Written from a
read-only survey of origin/main at ba91136 ("Merge pull request #13", remote access) and of PR
#12's branch `follow-best-path` at 8e1e4e3 (based on 76366e8, before #13; its merge with #13 was
under way in `/Users/noah/Downloads/winstream-ipad-settings` while this was written, with conflicts
in CLAUDE.md, DiscoveryPolicy.swift and StreamClient.swift). Line numbers are at ba91136 unless
marked "(PR #12)", which means 8e1e4e3. Nothing was built or started for this plan: no host, no
app, no simulator, and never the Mac's video encoder.

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
  fences, hold and adopt, `upWait`), so the branch for items 2–4 starts after PR #12 lands.

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
  still streams, so the Mac restarts once, at the home quality, before the fence comes down.
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
   with what would fit. The device shows a callout with a button, and a line on the stream. The
   Mac's card names it.
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
| 2 MB keyframes, 20 KB deltas, 16 Mbps | 29.4 fps, 21.7 drops a minute, ~1.2 s lag (base 1.5) | The same |
| Extreme · Retina on a 6–10 Mbps hotspot | Its deltas alone may exceed the link | Items 2 and 3 |
| A 12 s dip from 8 to 0.5 Mbps | Lag back to 45 ms about 2 s later than the base (7 s against 5 s) | Nothing here. It delivers up to 512 KB of backlog behind a keyframe where the old rule dropped: a deliberate, bounded exception to "Latency beats quality. Drop frames before queuing them.", remote clients only |
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
    /// The away quality runs now: every connected device is away.
    public var awayRunning: Bool
}

/// How the link to this device keeps up, as the Mac sees from what it withholds
/// (docs/remote-bundle-plan.md §6). Only while it does not keep up.
public struct LinkReport: Codable, Hashable, Sendable {
    /// "behind": the link cannot carry this quality (frames withheld in 3 of the last 5 seconds).
    /// "stalled": nothing taken for 3 s while bytes waited. A string, never an enum: a device reads
    /// any other value as keeping up.
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
| Older (PR #13, or #12 once merged), away | This host | Its Quality and Resolution show the away quality and set it. No "Away:" line. It ignores `link`, and keeps its rtt callout; the Mac's card still names the link |
| Older, at home | This host | As today |
| This device | Older host (PR #13's Sill.app) | No `away`, no `link`: the panel as today (one quality, the rtt callout). The move home works: that host sends a launch ID and a signed kind 18 |
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
- **`routesChanged()`**, called in `onClientConnected` right after `routes[id] = route` and before
  `sendCatalog`, and in `onClientDisconnected` (:160-194):

  ```swift
  if !routes.isEmpty {                                   // nobody connected: keep the flag
      let away = routes.values.allSatisfy(\.isAway)
      if away != awayWanted {
          awayWanted = away
          print(away ? "Away from home: …" : "Home quality again: …")          // §5.9
          Task { @MainActor in await self.applyPending() }
      }
  }
  status.update { $0.away = awayWanted && !routes.isEmpty }   // publishes (status.onChange)
  ```

- **`applyPending`** (:403-409) runs when `pendingConfig != nil || awayWanted != awayRunning`.
  `restartNeeded(for:away:)` (:415-424) compares the effective pair of `new` under `away` with the
  running one; the rate, the encoder speed and the virtual display as today.
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
    `AwayQuality` when `remote != nil` (else nil), `link: linkReports[id]` (§6.5).
  - `publishSettings()` (:1363-1368) sends each connection its own state, only when it differs
    from `lastPublished[id]`.
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
Home quality again: a device connected at home (fe80::47b:5945:e0aa:d0ac%en0.51447); streaming at Pro · Retina.
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
- **bytes waiting** at the second's end.

From those:

- **A second is short** when at least 3 frames were withheld and at least a tenth of the second's
  frames. So a single drop at home (one frame, then the keyframe asked for at once) never counts,
  and neither does a still window (no frames).
- **Behind** ("the link can't carry this quality"): 3 of the last 5 seconds were short.
- **Stalled:** the connection took no byte for 3 seconds in a row while bytes waited.
- **Fine again:** 5 seconds in a row that were not short, and not stalled. The hysteresis keeps
  the state from flapping.
- **A stream restart** (a settings change, a rate change, a new source) clears the window: the
  state goes back to fine and is judged afresh. Picking a lower quality clears the callout at
  once, and it comes back after 3 s only if the new quality cannot be carried either.
- **Carried:** the median of the bytes taken in the last 5 seconds that ended with at least 16 KB
  waiting, needing 3 such seconds. In those seconds the link, not the stream, set the pace, and
  the kernel's buffer was full, so what the connection took is what the link carried.
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
  `takenThisSecond`) and `judge: LinkJudge`. `pendingBytes` is now kept for every client. Item 1's
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
  fine.
- **No Stats key, no print.** The lines are the coordinator's (§6.8).

#### 6.4 `Sources/SillHost/LinkJudge.swift` (new; pure: Foundation only; checked with swiftc)

```swift
struct LinkJudge {
    enum State: Equatable { case fine, behind, stalled }
    struct Second: Equatable { var sent: Int; var withheld: Int; var taken: Int; var waiting: Int }
    struct Verdict: Equatable { var state: State; var withheld: Int; var offered: Int; var carriedKbps: Int?; var waiting: Int }
    static let window = 5, shortToBehind = 3, cleanToFine = 5, stallSeconds = 3
    static let measureWaiting = 16 * 1024, headroom = 0.7
    static func isShort(_ s: Second) -> Bool            // withheld ≥ 3 and 10 × withheld ≥ sent + withheld
    private(set) var state = State.fine
    mutating func close(_ s: Second) -> Verdict?        // non-nil when reported (§6.1)
    mutating func reset() -> Verdict?                    // fine, when it was not
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

**The callout** (`HostSettingsPanel.middle`, :174-258, where the slow-link callout sits). While
`client.settings.host?.link` says behind or stalled, one callout, first match wins:

| Situation | Callout | Button |
|---|---|---|
| Stalled | "Nothing is getting through from ‹Mac› right now." | none |
| Behind, away while a device at home is connected (`away.thisConnectionAway && !away.awayRunning`) | "The link can’t carry ‹Pro›, which ‹Mac› keeps while a device at home is connected." | none |
| Behind, a suggestion | "The link can’t carry ‹Pro›. ‹Low · Standard› is recommended." | "Use ‹Low · Standard›" |
| Behind, nothing lower | "The link to ‹Mac› is too slow for a steady picture, even at Low." | none |

- ‹Pro› is `QualityPreset.name(forBitrate: link.bitrate)`. The suggestion reads
  `shortTitle(…)` when it changes the resolution, else the preset's name alone ("Balanced").
- **The button** is an ordinary control: `client.changeSettings(HostSettingsChange(bitrate:
  suggestedBitrate, captureScale: suggestedCaptureScale))`. The ledger sends only what differs
  (rule 2), the Mac restarts once, and from away it changes the away quality only. At least 44 pt
  tall, like the panel's rows; spoken "Use Low, Standard".
- **The old callout** (the rtt test, :183-187, `StreamClient.isSlowLink`) shows only while the
  Mac sent no `away`: an older host. A host with a remote door judges the link itself, and a high
  round trip with nothing withheld is no reason to lower the quality.

**The stream screen's line** (`StreamScreen.contentArea` and `PortraitStreamScreen`):
- **Where:** a capsule at the top centre of the stream panel, 8 pt inside its top edge, at most the
  panel's width minus 32 pt. Footnote text on `Palette.bar` at 0.92 opacity; two lines at most at
  xxLarge text.
- **When:** from the moment a report that is not fine arrives, while the Settings panel, the
  drawer and the pairing overlay are closed. It goes 2 s after the report clears, so a quick
  flip back does not flicker.
- **Words:** §8.
- **Non-interactive** (`allowsHitTesting(false)`): it never takes a touch meant for the Mac.
- **VoiceOver:** one announcement of its text per spell (a spell ends when the line goes), not on
  every change.
- **Reduce Motion:** a fade either way.

**The harness** gains `-SillSettingsCase linkbehind`, `linkmixed`, `linklow` and `linkstalled`,
and `-SillLinkLine behind|stalled` for the stream screen with the line up.

#### 6.8 Log lines (exact; on reports only)

```
Link to iPad (iPad14,1): cannot carry Pro (withheld 52 of 58 frames in the last second; the link carried about 6.4 Mbps); suggesting Low · Standard.
Link to iPad (iPad14,1): cannot carry Extreme (withheld 57 of 60 frames in the last second); suggesting Ultra.
Link to iPad (iPad14,1): cannot carry Low (withheld 20 of 45 frames in the last second; the link carried about 2.1 Mbps); nothing lower to suggest.
Link to iPad (iPad14,1): nothing has got through for 3 s (1.2 MB waiting).
Link to iPad (iPad14,1): keeping up again.
```

A report that only adds the carried rate prints nothing. The device's DEBUG console prints
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
  `discoveryChanged` (:558-563), at the remote session's first window list (`remoteSessionReady`,
  StreamClient+Remote.swift:326-350) and after a move ends. It needs:
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
  - A ProMotion device's 120 fps then usually reaches the Mac before its quality restart takes the
    rate (§7.4).
  - The same viewport goes out again through the link after the fence, as PR #12's `finishMove`
    does; the Mac finds it unchanged.
- **The probe** (`probeMove`/`moveProbed`, PR #12) reads on to kind 18 for `.fromRemote`. The
  catalog's order is 2, 16, 18, so this costs a millisecond. The session is handed over only when
  all three hold:
  - the window list's launch ID equals the session's (`DiscoveryPolicy.sameHost`);
  - kind 18 verifies against the saved pin (`SignedMacInfo.verified()`, fingerprint and Mac ID
    equal to the saved Mac's);
  - its `issuedAt` ≥ `remoteInfoIssuedAt`.

  The Mac signs kind 18 afresh for every catalog (RemoteAccess.swift:537-542). A signature at
  least as new as the one this session received proves the home door's host holds the Mac's key
  now. A replayed TXT tag and a replayed kind 18 are not enough to take the session over (§10).

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
  under way carry a dead cable session. `sessionDead`, what the device sends is held
  (`holdSends`), and the hand-over is an `adopt` without a fence, since nothing sent on a dead
  connection comes back. No connect screen; the session ends only if the move does not complete.
- **`receiveMacInfo`** (StreamClient+Remote.swift:521-545) records `remoteInfoIssuedAt` for a
  verified kind 18 on a remote session.
- **`StreamScreen`** also re-sends the viewport on a change of `client.remoteRoute`, so a session
  that stops being away asks for its full rate whatever path it took.

#### 7.4 What the Mac sees, and the one restart

1. "Client connected: fe80::…%en0.51447" and its catalog, while the remote session streams on.
2. The new connection registers, so `routesChanged` finds a device at home: "Home quality again:
   …", and one restart at the home quality.
   - The home viewport is already in, or lands during the restart's capture stop, before
     `select` takes the rate.
   - A viewport later than that costs a second restart, for the rate only. S4 records which.
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
| Stream screen line, stalled | "Nothing is getting through from ‹Mac›." |
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
| Behind / fine again / stalled | 3 of the last 5 seconds short / 5 seconds in a row not short / 3 seconds with bytes waiting and none taken |
| Carried rate | median of the bytes taken in the last 5 seconds that ended with ≥ 16 KB waiting; needs 3 |
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
| Link: stalled | The card says so at once. The device's line only if the report gets through, and its liveness decides the session |
| Link: a report queued behind the backlog it describes | Behind: it waits behind at most what §3 lets queue (a keyframe and up to 512 KB after it). Stalled: it arrives when the path recovers, and the next report follows |
| Move home: another Mac of the same name on the network | Rows match by Mac ID (the tag), never by name |
| Move home: an impostor replays the Mac's TXT tag | Its connection must show this launch's ID and a kind 18 signed by the pinned key at least as new as this session's, which it cannot make. A live relay between the two networks remains possible: the home door is plaintext until M5, as it is for every reconnect over it today |
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
  the hook, step 1 adds it exactly as pointer-visibility-plan.md §4.10 defines it: a synthetic
  host only; it skips `EncoderProbe` and starts on the software encoder, with the line "Test
  encoder: software only (SILL_TEST_SOFTWARE_ENCODER); the hardware encoder is never probed.".
  On the software encoder a synthetic host runs at points (CLAUDE.md), so Retina ↔ Standard shows
  in the logs as bitrate only.
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
    item 3 it prints each link verdict as "Link: behind (withheld 52 of 58; carried 7.9 Mbps)".
  - `build.sh BASE`: assembles two throwaway SwiftPM packages under `$T`: HarnessBase from
    `git show BASE:` of StreamServer.swift and its neighbours (ClientLink, HostLog,
    InterfaceSnapshot, OriginPolicy, RefusalSummary, Stats, and LinkJudge once it exists), and
    HarnessNew from the working tree, each with `Sources/StreamProtocol`. Nothing is copied into
    the repository, so nothing drifts.
  - `device.py` (the device's reader, pings, stats and liveness; `--liveness-bytes` for the per-byte
    rule), `bottleneck.py` (a rate, a delay and a finite bottleneck queue; `--rate-at T:R`, where a
    rate of 0 is a blackhole), `run.py`, `summarize.py` and `matrix.sh`.
  - The device's key and certificate are made on first use with `/usr/bin/openssl` under `$T`,
    never committed.
- **`Scripts/sillclient.py`:** `describe` prints `away=` and `link=` when present; `--expect` learns
  `awayBitrate`, `awayCaptureScale`, `thisConnectionAway`, `awayRunning` and `linkState` (`fine`
  when absent).

**Headless (H).**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base; `git archive` it to `$SP/base` and build it. `Scripts/pacing/build.sh <base>`. H2's baselines. The ledger check's count (90 with 5,000 runs) and the policy checks' counts, PR #12's included. Once the software-encoder hook exists (step 1, or the pointer plan): the synthetic host's keyframe size and rate on it (`sillclient.py PORT 10 desktop`, its LINK line), from which S2 and H12 set their relay rates | Files and numbers recorded |
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **The CLI byte for byte.** Base and new `SillHost --synthetic`: idle 35 s, and with `sillclient.py PORT 5 desktop`; both again with `--direct-wireless`; digits masked, sorted. After steps 1, 5 and 6 | Identical, the client's kind 16 lines and "settings messages" count included |
| H3 | **The pacing matrix,** base and new, each case's arguments as run by the investigation (host `--` relay `--` device): real24 `--kf 1500000 --delta 30000 -- --rate-mbps 24 --delay-ms 70 --queue-bytes 262144 -- --reconnect`; kf25m32 (2.5 MB, 20 KB, 32 Mbps); fastbig (1.5 MB, 150 KB, 100 Mbps, 20 ms, a 1 MB queue); bigkf8 (1.5 MB, 8 KB, 8 Mbps); low (150 KB, 8 KB, 8 Mbps); switch (sizes change at 30 s to Low's); dip (8 → 0.5 Mbps from 20 s to 32 s, a 1 MB queue, 60 s); over8 (60 KB deltas on 8 Mbps); slowkfB (1.6 MB on 2 Mbps with `--liveness-bytes`); home (`DOOR=Home`, `--plain`). real24, kf25m32 and bigkf8 three times each | real24 ≥ 55 fps, 0 `net.dropped`, about 15 keyframes a minute, 3 of 3 (verified: 60.1 fps against the base's 39.5); kf25m32 ≥ 55 fps (60.1 against 1.4); fastbig 60 fps and 0 drops (base 1.7 a minute); bigkf8 ≥ 55 fps and 0 drops; slowkfB ≥ 55 fps after its first keyframe. These last two were measured on fix-v3 only, never on the proposed file, so they are first proven here. low, switch and home equal the base within noise. dip: no loss, no eviction, the lag back to 45 ms within 8 s of the dip's end (record it). over8 ≥ the base (record it) |
| H4 | **The remote door's slow-link gates again** (remote plan H14, H15): `sillrelay.py --rate-mbps 2 --delay-ms 150` for 90 s on a paired session; `--blackhole-after 5` | No eviction; frames in every 5 s window; keyframes at the encoder's cadence; "Client silent for … dropping" at about 13 s after a blackhole |
| H5 | **MessageReader** (swiftc, against a local NWListener): 2,000 random messages of 0 B to 3 MB written in random chunks of 1 B to 300 KB with random pauses; a 3 MB frame at 1 Mbps; EOF half-way through a payload; a header announcing 40 MB; `stillReads` turning false mid-stream | Every message delivered byte for byte and in order; `onBytes` at least once per 256 KB and at most 0.3 s apart during the slow frame; EOF gives `.closed` with nothing delivered; `.tooBig` with nothing read after the header; no receive after `stillReads` is false. At least 5 mutants caught: the stamp only at the message's end, `minimumIncompleteLength` = remaining, no piece cap, EOF mid-message ignored, no cap check |
| H6 | **The wire** (swiftc): `AwayQuality` and `LinkReport` JSON round trips; `{}` fails to decode them, and a state without them decodes; the base's StreamProtocol decodes the new kind 16 and the new decodes the base's | All pass |
| H7 | **Away.** `SILL_TEST_ORIGIN=vpn SILL_TEST_REMOTE_DIR=$T/h SillHost --synthetic --remote`; `sillclient.py --tls --pair-code=… --identity=$T/a`, then a session with `--set=bitrate=15000000@4` | "Away from home: …" once; "Streaming … 4 Mbps"; kind 16: `thisConnectionAway` 1, `awayRunning` 1, bitrate 4000000, scale 1, `homeBitrate` 15000000; at 4 s "Settings from sillclient: away bitrate 4 → 15 Mbps per 60 fps" and one restart at 15 Mbps; `homeBitrate` still 15000000 |
| H8 | **Mixed.** H7's host; a home client at 5 s from the Mac's own `fe80::…%en0` (`--host=`, admitted as this network), leaving at 12 s | "Home quality again: …" and one restart at 5 s (the home quality); the remote client's kind 16 `awayRunning` 0 while the home client stays; at 12 s "Away from home: …" and one restart; exactly one "Streaming" line per flip |
| H9 | **The app.** Bare `SillMenuBar --synthetic -remoteAccess 1` (a launch-argument override, never saved) with `SILL_TEST_ORIGIN=vpn`, `SILL_TEST_REMOTE_DIR=$T/app` and `-SillPairAfter 1`; `sillclient.py --tls --pair-url=` from `$T/app/pairing.url`, then a session that changes the bitrate; relaunch; `-SillSetAfter '3 awayBitrate=8000000,awayCaptureScale=2'` | `defaults read SillMenuBar awayBitrate` 15000000 and `bitrate` absent; after the relaunch the away session starts at 15 Mbps; the SetAfter gives one "Settings: away bitrate 15 → 8 Mbps per 60 fps, away points → Retina" and one restart; then `defaults delete SillMenuBar` |
| H10 | **LinkJudge** (swiftc, at least 30 checks): behind at exactly 3 short of 5 (2 stays fine); fine after 5 clean in a row (4 stays behind); still seconds count as clean; stalled after 3 seconds with bytes waiting and none taken (2 not); stalled → behind → fine; reset reports fine; `isShort` at 2 of 60 (no), 3 of 60 (no: 5 %), 6 of 60 (yes), 3 of 20 (yes); the carried median needs 3 measured seconds; the suggestion: the highest preset ≤ 70 % at 60 and at 120 fps, Low when none fits, one step down without a measure, Standard added only with Low from Retina, the same bitrate at Standard from Low · Retina and from a hand-set 2 Mbps at Retina, nil at Low · Standard, never above the running bitrate | All pass; at least 8 mutants caught (2 of 5, 4 clean, still seconds as short, `>` for `≥`, 0.8 for 0.7, fps ignored, Standard never suggested, the first-keyframe wait counted) |
| H11 | **The link in the harness** (encoder-free, the new build): real24, over8, dip, a blackhole at 20 s (`--rate-at 20:0`), home | real24 never behind; over8 behind within 5 s of the stream start, carried within 20 % of 8 Mbps and a Low suggestion; dip behind within 5 s of its start and fine within 10 s of its end; blackhole stalled within 4 s; home never behind |
| H12 | **The link end to end.** H7's host through `sillrelay.py --rate-mbps R` (R half the synthetic stream's rate, from H0); `--set` of the suggestion 20 s in | Within 6 s a kind 16 with `link.state` "behind" and a suggestion, and "Link to sillclient: cannot carry …"; after the `--set`, one restart and a kind 16 without `link` |
| H13 | **Per-connection states.** H8's two clients, and the one-client runs of H2 | Each gets its own pair; with one client, the kind 16 lines and count equal the base's |
| H14 | **The ledger check and the policy checks,** unchanged and PR #12's | As at H0 |
| H15 | **`moveHome`** (swiftc, with the policy check): 1.9 s no, 2.0 s yes; a blink restarts the count; retries at 10, 20, 40, 60, 60 s after 1–5 failures; a refused listing never; a new listing afresh | All pass; at least 5 mutants caught (no refusal, `upWait(0)`, a blink ignored, `>` for `≥`, failures ignored) |
| H16 | **Previews,** before and after (from the bundle made by `make-app.sh`, never installed) | Only the Streaming pane (the new section), menu.txt's `remote-away` sample, and the new card samples `remote-away`, `link-behind` and `link-stalled` differ. Look at each |
| H17 | **Hard rules** (grep) | No new Stats key; no `assumeIsolated` or `updateConfiguration` in Sources/SillHost; StreamMessage.swift unchanged by steps 4–9; `standard` has Low and Standard away; `DeviceSettings.accepted` still refuses Direct Wireless from afar; `HostSettingsChange` unchanged |

**Simulator (S):**

| # | Check |
|---|---|
| S1 | **The photo matrix.** `-SillSettingsCase away`, `awaymixed`, `awayhome`, `linkbehind`, `linkmixed`, `linklow` and `linkstalled`, and `-SillLinkLine behind` and `stalled`, at 1000x710, 710x1000, 500x710 and 710x500, and at `content_size accessibility-extra-large` (reset afterwards). Check: the header's lines never truncate; the callout's button is at least 44 pt; the line never covers the bar and nothing crosses y = 500 at 710x1000. Send Noah the sheet |
| S2 | **The reader, live.** The simulator by address (`-SillConnect`) through `sillrelay.py --rate-mbps R`, R such that the first keyframe takes at least 8 s (H0). The base build's console shows "connection silent for 6 s: lost" within 30 s; the new build's never in 60 s, its HUD counts frames, and the host evicts nobody |
| S3 | **The callout, live.** Pair by the typed path through a relay (`-SillPairCode … -SillPairAddress 127.0.0.1:RELAY`, the remote plan's S8) to H7's host (away); the relay at H12's rate. The callout appears within about 6 s; a headless tap on its button gives "Settings from … away bitrate …" on the host and one restart; the callout and the line go; the console shows the announcement once |
| S4 | **The move home, live.** Pair with H7's host (`SILL_TEST_ORIGIN=vpn`: the remote session is away), then `-SillDialSaved 1 -SillMoveHomeTest to:[fe80::…%en0]:HOMEPORT -SillScreenFPS 120`. The host logs "Client connected: fe80::…", "Home quality again: …", then "Client left: 127.0.0.1:…"; one "Streaming" line for the flip (record whether the rate needed a second); the panel's route line gone and the readout ending in "Wi‑Fi"; "remote: the session moved home". Variants: `refused` (tries at about 2, 12, 32 and 72 s; the session stays remote); `other:PORT` (refused once, not again while listed) |
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
| P6 | **Mixed.** The iPhone at home on Wi‑Fi and the iPad away. The home quality runs; the iPad's header says "Home quality: Pro · Retina (a device at home is connected)". Disconnect the iPhone: the away quality, one restart |
| P7 | **The Mac.** Settings › Streaming shows both sections. Changing the away pickers while the iPad is away restarts once. The menu's Quality subtitle says "Away from home now: …" |
| P8 | **The link.** Away at Extreme. Within about 5 s: the callout with its button, the stream's line, one VoiceOver announcement, and the Mac's card "iPad: … the link can’t carry Extreme". Tap the button: one restart; the callout and the line go; the card's row is normal within about 5 s |
| P9 | **A dip.** Cover the iPhone, or walk away from it, for 15 s. The line appears, then goes about 5 s after the link recovers; no reconnect |
| P10 | **Coming home.** Streaming away through Tailscale, join the home Wi‑Fi. Within about 5 s of the network listing the Mac: "Client connected: fe80::…%en0", "Home quality again", "Client left: 100.x". The route line gives way to "Wi‑Fi"; one restart; drag and type through it (no button stays down, no letters swap); the Mac's card shows the iPad once, "Wi‑Fi" |
| P11 | **Coming home by cable.** An away session; at home, plug the cable in. The move goes to the cable ("Wired"; the Mac logs `%en14` or `%anri0`) |
| P12 | **Connect Remotely at home** stays remote |
| P13 | **Mixed builds.** PR #13's iPad against this Sill.app, away: starts at Low · Standard; its Quality shows Low; no header line. This iPad against PR #13's Sill.app: no header line, no link callout, the move home works |

---

### 12. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

**PR A, "Remote pacing"** (item 1). Branch `remote-pacing` from origin/main after `git fetch`. It
depends on nothing open and can merge first.

0. **Preflight** (no commit): H0.
1. **"Host: remote pacing counts bytes, not messages: a keyframe no longer starves its followers"**
   (StreamServer.swift, `Scripts/pacing/`, and the `SILL_TEST_SOFTWARE_ENCODER` hook if the
   pointer plan has not landed it). About 90 lines of host code and the harness (~700 lines,
   moved). Gates: H1, H2, H3, H4, and H0's keyframe measurement.
2. **"iOS: the reader takes a message in pieces; liveness counts every byte"** (MessageReader.swift
   new, StreamClient.swift, pbxproj). About 150 lines. Gates: H1, H5, S2.
3. **"docs: remote pacing":** CLAUDE.md (the step, Layout, `Scripts/pacing/`), and
   remote-access-plan.md §4.9(6)'s line (§3.3). Stop here if Noah takes PR A alone.

**PR B, "Away from home"** (items 2–4). Branch from origin/main **after PR #12 has merged** (and
after PR A, or with PR A's commits first). Cherry-pick this plan's commit.

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
      harness, the new `sillclient.py` keys, the DEBUG arguments); Untested, for Noah: P1–P13;
    - README: the away quality, the link callout, coming home.
11. **Review and hand-over.**
    - Three lenses: pacing and link judging on `sill.net` (bytes, completions, the sweep); the away
      flag, the per-connection states and restarts on the main actor; the device's UI and the move
      (fences, the kind 18 check, backoff).
    - A "Review fixes" commit if needed.
    - Then H3, H7, H8, H11, H12, S3 and S4 again on the final build.
    - Hand P1–P13 to Noah. **Stop there.**

**Rebases.**
- **PR #12 (follow-best-path)** must land before PR B: step 9 builds on its `MoveKind`,
  `startMove`/`probeMove`/`finishMove`, `SessionLink` (fences, hold, adopt, `Released.close`),
  `closeSoon` and `upWait`. If PR A lands first, #12's merge carries MessageReader (it touches
  neither `readPayload` nor the reader).
- **PR #11 (encoder-recovery)** touches StreamCoordinator, HostStatus, HostSettings.swift (a doc
  comment), SettingsPanes, StatusText, DebugHooks, `sillclient.py` and HostSettingsPanel: a small
  rebase for PR B whichever lands first.
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
    It costs a millisecond and stops a replayed tag. The home door stays plaintext until M5.
11. **Ship PR A (pacing) on its own first.** Default: **yes.** It is independent of PR #12, and it
    removes the livelock for every build of the device.
12. **The 512 KB hold cap** keeps up to about a second of Low's deltas behind a keyframe instead of
    dropping them: an exception to "Latency beats quality", remote clients only. Default: **keep
    it,** as the investigation measured. The alternative cap at 256 KB was not measured.
