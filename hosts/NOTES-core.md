# Core notes (sill-protocol, sill-host-core)

## Status (newest first)

- **2026-10-14, fixes from the Linux agent's findings:**
  - `FfmpegEncoder`: a keyframe asked for before the first frame made every frame an IDR (the
    first frame's odd timestamp became FFmpeg's start time, and FFmpeg shifts every timestamp by
    it). The first frame is now always at timestamp 0 and never marked (it is an IDR anyway and
    answers the request). Test `a_request_before_the_first_frame` (request, 12 frames, a request
    after frame 7 → keyframes exactly [0, 8]); against the old code it got
    [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11]. **Linux: your workaround for this can go.**
  - Catalog: a window ID that comes back naming another app's window (X11 reuses IDs right after
    a client exits) is a new window: it goes last in the order and loses the old thumbnail and
    stamp; the streamed window counts as gone when its ID now names another app (the stream
    stops, as for a closed window). A window that leaves the list takes its thumbnail and stamp
    with it (it did before too). Icons stay: they are per app. Test
    `catalog::tests::a_reused_window_id_is_a_new_window`.
  - Viewport fitting no longer compares `resize`'s logical points with `Window.width/height`
    (Rect units, physical pixels on HiDPI Windows): a window already fitted to a target is not
    asked again, and the same answer twice (a refused size) restarts nothing. Checked with the
    synthetic host: the same viewport twice → one "Resized", a too-small target (100×80 → 300×200)
    asked once, a rotation at 1.5× → one more.

- **Milestone C, most of it: done, verified on loopback.** The remote door (`--remote[=PORT]`,
  `--internet`): TLS like the home door, sessions for paired keys only, pairing only for this
  host's own window (an ask there → `closed`), at most 8 sessions (then goodbye `busy`), VPN and
  this network admitted, the internet only with `--internet`; kind 18 with `remoteAccess`, the
  port and the address list (Tailscale's 100.64/10 first, other VPNs, this network); the pairing
  link with `p=PORT&a=…`; remote pacing by bytes (StreamServer.paceRemote ported), 8 s silence
  eviction, 15 s drain backstop, keyframe spacing 2 s (4 s beside a home device); the away
  quality (Low · Standard while every device is away, a device away sets the away pair, home
  quality again when one at home joins). Also kind 26 (the host's pointer). See "Verified (C)".

- **Milestone B (TLS home door with pairing): done, verified on loopback** with sillclient.py
  (`--pair-ask --then-code`, `--pair-url`, `--pair-code`, `--tls`, `--expect-tls-fail`,
  `--pair-cancel`, `--pair-v`, `--pair-hold`) and with a Network.framework client built from
  `Sources/StreamProtocol` (RemoteTLS, the apps' own TLS builder): ask → "shown", code pairing with
  proof_M checked, a stranger's key refused (-9832), a pinned `sill/1` session streaming with kind
  18 verified. Not verified with the Mac viewer app (see "Open": it would write into the user's
  real viewer's saved Macs and keychain). Run it with `--pairing [--config-dir=DIR]`.
- **Milestone A (plain home door end to end): done and usable by backends.** The API below is
  stable. Verified on this Mac with `sill-host-synthetic` (libx265 through FFmpeg 9.0):
  `Scripts/sillclient.py` (stream, settings, picks, input, junk, oversized header, flood, eviction,
  goodbye) and the Mac viewer's Debug build streaming the test pattern at 105–107 fps (120 Hz
  panel). Details under "Verified".
- **Trait changes: one additive method** (`release_all_input`, default no-op) and doc
  clarifications. See "Trait changes".

## How a backend uses the core

```rust
use std::sync::Arc;
use sill_host_core::{platform::Platform, HostOptions};

fn main() {
    let (options, rest) = HostOptions::from_args(std::env::args().skip(1)).unwrap_or_else(|e| {
        eprintln!("{e}"); std::process::exit(2)
    });
    // `rest`: the arguments the core did not take (your own flags).
    let platform: Arc<dyn Platform> = Arc::new(MyPlatform::new());
    if let Err(e) = sill_host_core::run(platform, options) { eprintln!("{e}"); std::process::exit(1) }
}
```

- `run` blocks: it binds the home door, serves devices, and on Ctrl-C / SIGTERM sends every device
  goodbye `{"reason":"quit"}` (kind 22) and returns.
- Shared flags (`HostOptions::USAGE`): `--port=N` (default 0 = any free port, as the Mac),
  `--loopback` (127.0.0.1 only; also `SILL_TEST_LOOPBACK=1`), `--pairing` (the TLS home door),
  `--remote[=PORT]` (the remote door; any free port without one, 7455 is the Mac's), `--internet`
  (with `--remote`), `--config-dir=PATH`, `--name=NAME`, `--no-advertise`, `--bitrate=MBPS`,
  `--max-fps=N`, `--standard` (half scale).
- **For end users, pass `--pairing`** (the default stays the plain door, as `SillHost`; Release
  builds of the apps only dial a TLS door). That choice is the user's/your main.rs's (see "Open").
- Logging: `sill_host_core::log(line)` prints a line to stdout (flushed), the same place the core's
  lines go ("Client connected: …", "[1s] enc.out 60  net.sent 60 …", "Test input: …").
- Stats: `sill_host_core::stats::bump("key")` adds to the once-a-second line (use your own keys,
  e.g. `cap.frames`, `cap.dropped`).

### What the core calls, and from where

- The coordinator is one thread. It calls `start_stream`, `Stream::stop`, `request_keyframe`,
  `source_rect`, `inject`, `raise`, `resize`, `window_command`, `launch`, `pointer_location`.
  `windows`, `thumbnail`, `icon` are also called from the catalog thread (every 2 s while a device
  is connected; thumbnails of every window each poll, sent only when the bytes changed); `apps`
  once at start on its own thread. So `Platform` really must be `Sync`.
- `start_stream(config, sink)`: `config.scale` is 1.0 (device chose "Retina"/full) or 0.5
  ("Standard": half each way); `fps` is the highest panel rate among devices (60/120), capped by
  maxFPS; `bitrate` already scaled for fps (bitrate × fps / 60). A settings change, a new device
  rate, or a window resize **restarts** the stream (old one `stop`ped first, then a new
  `start_stream`).
- `sink.frame(EncodedFrame)` from any thread: NAL units without start codes; set `keyframe`; set
  `parameter_sets: Some([vps, sps, pps])` on every keyframe (and the first frame). The core frames
  them (4-byte lengths), stamps the time, paces per device. Frames after `stop` are ignored.
- `sink.cursor(shape)`: PNG + hotspot/size in source units; the core caches it and sends kind 14
  to everyone (and to devices that join later).
- `sink.ended(reason)`: the stream died; the core logs it and goes back to streaming nothing.
- `request_keyframe`: the next frame must be IDR; when the source is still, encode the last picture
  again (FfmpegEncoder does this for you).
- `source_rect`: the rectangle input lands in (the core maps device fractions onto it: x = rect.x
  + fx × rect.width; scroll dx × rect.width). Called for every input event: keep it cheap.
- `inject`: keys arrive as HID usage + the device's modifier bits, unchanged (map ⌘/⌃→Ctrl,
  ⌥→Alt, ⇧→Shift yourself). Devices that leave get their held keys and buttons released by the
  core (key-ups with modifiers 0, button-ups at the last pointer position). With nothing streaming
  only those releases go through.
- `raise(id)` on a device's pick of a window (regular mode on the Mac). Not on restarts.
- `resize(id, w, h)`: **w × h are logical points** (the device's panel ÷ its Aa scale, like Mac
  points). A backend whose `Rect` units are physical pixels multiplies by its display scale
  (Windows: by the window's DPI ÷ 96; Linux: by Xft.dpi ÷ 96). **The returned size is in the same
  logical points** (pixels ÷ that factor): the core compares it with the size it asked for and
  with `Window.width/height` ("asked again for a size the app already refused"), then restarts
  the stream at the window's new size from `windows()`.
- `launch(app_id)`: the core then picks the first window whose `app_id` matches (within 30 s).
- `pointer_location()`: read at every 30 ms tick while something streams (kind 26, the host's
  pointer on devices that are not moving it): keep it cheap (GetCursorPos, XQueryPointer), same
  units as `source_rect`. None: no kind 26 is sent. The core tells its own posts from the host's
  mouse (a move 0.5 units or more, outside 0.25 s after the core's last post, is the host's).
- `advertise(name, port, txt)`: plain door → `txt` is empty; the TLS door (`--pairing`) passes
  `r` (a fresh recognition tag) and `p` = "1" (pairing required): put both in the TXT record as
  given. Return `Err` to log "Not advertised" and go on.

### The TLS home door (`--pairing`)

- As `SillHost --pairing` / Sill.app: TLS 1.3 only (rustls + ring), both ends self-signed P-256,
  pinned by SPKI SHA-256; ALPN `sill/1` (sessions of paired keys only) and `sill-pair/1` (one
  kind 19, one kind 20). The device's key is judged inside the handshake (the host reads the
  ClientHello first to know the ALPN), so an unpaired key's session fails as on the Mac.
- Identity and trust list in the config dir (0700; files 0600): `identity.p8` (PKCS#8),
  `recognition.key` (32 bytes), `paired.json`. Default dir: `--config-dir`, else `SILL_CONFIG_DIR`,
  else `%APPDATA%\Sill` (Windows) or `$XDG_CONFIG_HOME/sill` / `~/.config/sill`. Delete
  `paired.json` to forget every device; delete the whole dir for a new identity (devices must
  pair again).
- A pairing window is always open (5 minutes, single use, 5 wrong tries with 1/2/4/8 s spacing,
  5 s per source): its 12-digit code and `sill://pair` link go to stdout only ("Pairing required
  for this run (TLS on the home door). Pair with 1234 5678 9012 or sill://pair?…"); a fresh one
  after each use or expiry ("Pairing: new code …"); a device's ask is answered `shown` and the
  code printed again ("Pairing: iPad (iPad14,1) asked; code …"). PBKDF2 600,000 rounds as Swift.
- Kind 16 then carries `away` (as SillHost --pairing), and kind 18 (SignedMacInfo, no addresses,
  remotePort 7455) follows it in every catalog.
- Door limits as Door.swift: 8 pending, 2 per source, 10 s to admission, 5 refusals in 60 s →
  300 s backoff (`SILL_TEST_BACKOFF_SECONDS`), VPN/internet sources dropped before a byte; one
  summary line a minute. `SILL_TEST_PAIRING_TTL=S` shortens the window.
- Not here (Mac-only rules): pairing by itself over the USB cable, the "Mac is locked" answer,
  Require pairing off (pairing is always required), Remove/rename at run time (edit
  `paired.json` while the host is stopped).

### The FFmpeg encoder (`sill_host_core::ffmpeg`)

```rust
use sill_host_core::ffmpeg::{FfmpegConfig, FfmpegEncoder, HevcEncoder, PixelFormat};
let mut cfg = FfmpegConfig::new(HevcEncoder::Libx265 /* or Vaapi{device}, Nvenc, VideoToolbox */,
                                PixelFormat::Bgra /* or Nv12 */, width, height, config.fps, config.bitrate);
cfg.prioritize_speed = config.prioritize_speed;
let enc = FfmpegEncoder::start(cfg, sink.clone())?;   // frames go straight to the sink
enc.submit(tightly_packed_frame);                     // never blocks; a waiting frame is replaced
enc.request_keyframe();                               // from Stream::request_keyframe
enc.stop();                                           // or drop it
```

- Frames must be exactly `enc.frame_len()` bytes (BGRA w×h×4, NV12 w×h×3/2; even sizes; no row
  padding). Scale before submitting: the encoded size is the submitted size.
- `HevcEncoder::parse("hevc_vaapi:/dev/dri/renderD128")` etc. for a `--encoder=` flag.
  `SILL_FFMPEG=/path/to/ffmpeg` picks the executable.
- How: Matroska (raw video, µs timestamps, DefaultDuration = 1/fps) into ffmpeg's stdin, NUT out of
  its stdout (each packet complete as it is written: no frame of extra latency), one frame inside
  ffmpeg at a time. A keyframe request rides on the timestamp (odd µs ⇒
  `-force_key_frames expr:…` makes it IDR). Measured: libx265 ultrafast, 1920×1200 at 60 fps,
  ~10–15 ms in→out on this Mac; first frame ~50 ms after start. Old FFmpeg (< 5.1) gets `-vsync`
  instead of `-fps_mode`. hevc_vaapi, hevc_nvenc and hevc_videotoolbox command lines are written
  but **untested here** (no such hardware run on this Mac; VideoToolbox deliberately not run).
- Pitfalls found (so you do not fight them again): `-fflags nobuffer` makes the Matroska demuxer
  hold the first frame until the second; without DefaultDuration the encoder's rate control takes
  the µs time base as the frame rate (280-byte frames at 15 Mbps); raw Annex-B, AVI, MP4 and
  Matroska output all cost a frame of latency.

### The synthetic backend

`sill_host_core::synthetic::SyntheticPlatform` and the binary `sill-host-synthetic`
(`cargo run --release -p sill-host-core --bin sill-host-synthetic -- --synthetic --loopback`): a
1920×1200 Desktop test pattern (sweeping bar, bouncing square, binary frame counter), two fake
windows (101 "Shopping list", 102 "Calculator"), three apps (launching "Sill Test Terminal" adds
window 103), JPEG thumbnails, PNG icons, an arrow cursor. Input is only logged ("Test input: …").
`SILL_TEST_PATTERN=noise` adds a square of noise so the stream's size follows its bitrate.
`--encoder=…` as above. Pass `--synthetic` so `sillclient.py --tap/--key/--input` agree to send
input (they check the listener's arguments).

## What the wire looks like (decisions to know)

- Kind 2 `WindowList`: `launchID` (random per launch), `protocol: 1`, no `hostVersion` (as
  SillHost), no `gestures` (devices send no kind 28).
- Kind 16: `settings.virtualDisplay` false, `directWireless` absent (no row on the device),
  `persistent` false, `virtualDisplayAvailable` false with a note, `softwareEncoder` false (true
  would show a Mac-specific callout), `stream` once the first frame says its size. Kind 17 takes
  exactly the Mac menu's values (maxFPS 60/120, the seven bitrate presets, captureScale 2/1,
  prioritizeSpeed); refusals logged per field; 4 a second per device.
- Kind 26 (the host's pointer) to every device that is not moving it, when its report changes
  (sampled at the 30 ms tick, as PointerWatch at its slower rate; no frame-rate sampler). No kind
  24 (no Menus button); kinds 25, 27, 28 are logged once and ignored.
- Catalog order on connect: 2, 16, icons (4), apps (5), thumbnails (3), cursor (14), as the Mac.
- Pacing (home rule): a device with more than two messages not yet written to its socket loses
  the next delta and waits for a keyframe (asked for at once); no frame drained for 4 s (8 s grace
  after connecting) evicts it. Ticks (kind 13, empty) every 30 ms while streaming or within 3 s of
  input. Pings echoed from the reader thread.
- The plain door admits loopback, link-local and this machine's own subnets; VPN interfaces
  (utun/tun/wg/tailscale…) and 100.64/10 are refused (one line a minute per source). Connections
  reset before they say anything are not logged.

## Verified (milestone A)

- `cargo test -p sill-host-core --test ffmpeg_encoder` (needs ffmpeg with libx265; skips
  otherwise): BGRA and NV12 in, the first frame IDR with VPS/SPS/PPS, deltas after, each frame out
  well under 0.5 s, a keyframe on request, and a still source's last frame re-encoded as a keyframe
  ≥ 40 ms after the request.
- `cargo test -p sill-protocol -p sill-host-core`: 34 tests (header round trips; every kind;
  JSON against payloads captured from the Swift `SillHost --synthetic` and against sillclient.py's
  shapes; ParameterSets against Swift bytes; cursor/image blobs; PBKDF2/HMAC proofs against
  Python's hashlib; certificate/SPKI/Mac ID; settings whitelist; NUT/hvcC/Annex-B helpers).
- `sillclient.py PORT 8 desktop --stats`: catalog `2 16 5 4×2 14`, 60 fps, 1–2 keyframes, pongs,
  ~30 ticks/s; the recorded stream decodes with `ffmpeg -i … -f null -` without an error.
- `--set=bitrate=…@2 --set=captureScale=1@3 --raw17=bitrate 200000000 --set=maxFPS=60@5
  --expect=…`: one restart per change, the 200 Mbps refused, `EXPECT ok`; `--fps=120` restarts at
  120 fps; `--pick=window:101` streams the window; `--tap/--key/--input` (scroll, text) logged as
  "Test input: …" at the right coordinates.
- `--junk` skipped; `--big-payload=2000000000` closed at once; `--flood=20` logs nothing;
  `--stop-read@3` with `SILL_TEST_PATTERN=noise` → "Client not draining for 4 s, dropping";
  Ctrl-C → the client prints `goodbye … quit`.
- Mac viewer (Debug, `-SillOpenAddresses 127.0.0.1:PORT`): hello logged ("Mac Studio
  (Mac15,14), Sill 0.5.1 (4), protocol 1"), Desktop picked, 120 fps viewport → restart at 120 fps,
  client reports 104–107 fps, frame age 0–12 ms; screenshot of its session window shows the
  pattern, the two windows with thumbnails and icons, and the three apps.

## Verified (milestone B), 2026-10-14

- `cargo test`: rustls server/client round trip with mutual pinning and ALPN; an untrusted key
  refused in the handshake; a wrong pin never completes; the pairing window (QR proof → proof_M,
  persisted identity and trust list, wrong codes → busy → stopped, `v` 2 → closed without a try).
- sillclient.py against `sill-host-synthetic --synthetic --loopback --pairing --config-dir=…`:
  `--pair-ask --then-code=FILE` → `shown`, then `PAIR ok … proof_M checked`, then the `sill/1`
  session (TLS 1.3, TLS_AES_256_GCM_SHA384), catalog `2 16 18 5 4×2 14`, `macInfo verified=1`
  (openssl over the exact info bytes, Mac ID = key); after a host restart the saved pin streams
  without pairing; `--pair-url` (QR) pairs; an unpaired key gets `TLSV1_ALERT_ACCESS_DENIED`
  (`EXPECT-TLS-FAIL ok`); a valid-looking wrong code → `code` (4 tries left), at once again →
  `busy` (retryAfter 0.9); `--pair-cancel` → `closed`; `--pair-v=2` → `closed`; `--pair-hold=12`
  → closed at 10.00 s; a plain client at the TLS door → EOF.
- Two TLS session bugs found after the first B runs and fixed, each with a test that fails
  without the fix (`cargo test -p sill-host-core --lib tls_transport`): a message over 64 KB (a
  keyframe) hit rustls' buffer limit and closed the session (now written in pieces; 2 MB test,
  and 150 Mbps noise over TLS: 176 KB keyframes, 59 fps); a burst of input larger than rustls'
  received-plaintext buffer closed it too (now fed as it is read out; 1 MB burst test).
- A Network.framework client (StreamProtocol's RemoteTLS/PairingProof/SignedMacInfo compiled with
  swiftc): ask → `shown`; code → ok, proof_M valid, Mac ID matches; a stranger on `sill/1` →
  -9832 access denied; the pinned session: 185 frames in 4 s, kind 18 `verified()` matches the
  pinned key, `away` present.

## Verified (C), 2026-10-14

- `--pairing --remote` on loopback: "Remote access: listening on port P (TLS, paired devices
  only; N paired)." then "Remote access for this run on port P … Pair with … or sill://pair?…&p=P
  &a=127.0.0.1"; `sillclient --pair-url` at the remote door → `PAIR ok`, then the session there
  ("Remote client connected: sillclient (sillclient) by address"), kind 18 `remoteAccess=1
  port=P addresses=[127.0.0.1/lan/This Mac]` verified; `--pair-ask` at the remote door →
  `closed`; the same key at the home door streams (one trust list).
- `SILL_TEST_REMOTE_ORIGIN=vpn` (loopback counts as a VPN at the remote door): the session is
  "through your VPN", kind 16 `this=1 run=1 bitrate=4000000 scale=1`, the stream 960×600 at 4 Mbps;
  `--set=bitrate=8000000` → "away bitrate 4 → 8 Mbps", `--expect=awayBitrate=8000000,
  thisConnectionAway=1` ok; a home device joins → "Home quality again …" (1920×1200, 15 Mbps),
  leaves → "Away from home …" (8 Mbps).
- Through `Scripts/sillrelay.py --rate-mbps 2 --delay-ms 150` with `SILL_TEST_PATTERN=noise`:
  25 s, no eviction, ~28 fps delivered, keyframes every 1–3 s, the link saturated (~240 kB/s).
  The pong round trip sits at ~4 s: that is the relay's own loopback receive buffer (it reads
  from the host only as fast as its rate, and macOS keeps loopback buffers at 340–590 KB+), the
  same through Swift's host; the remote sockets also get TCP_NOTSENT_LOWAT 32 KB (Linux, macOS)
  so a real link's kernel buffer cannot add to it.
- Two sillclients, one moving (`--move`), one `--pointer`: the watcher gets
  `pointer at … x=0.2500 y=0.2500 inside=1 seen=0`, the mover none.

## Open

- Not built: the router query (NAT-PMP/PCP) and an address name for `--internet` (the address
  list then has no internet entries: devices away reach the host through a VPN or this network);
  LinkJudge (kind 16's `link`: "the link can't carry …"); the frame-rate pointer sampler; the
  move home; menus (kind 24), gestures (kind 28); Require pairing off; Remove/rename at run time.
- Decision for the user: should the PC hosts default to `--pairing` (TLS, as Sill.app) rather
  than the plain development door (as `SillHost`)? Release builds of the apps refuse plain doors.
- The Mac viewer against the TLS door: not run. The Debug viewer shares its bundle ID, its
  UserDefaults (`Sill.savedMacs`) and its keychain item with the Release viewer running on this
  Mac, so pairing it would write a test host into the user's real saved Macs. Use the iPad/iPhone
  or a second Mac account, or the Network.framework stand-in above.
- The FFmpeg command lines for VAAPI/NVENC/VideoToolbox are untested.
- First frame after a (re)start waits for FFmpeg to start (~50 ms with x265 at 1080p).

## Trait changes

- 2026-10-14 (additive): `Platform::release_all_input(&self)` with a default no-op. The core calls
  it once when it stops (after releasing each device's held keys and buttons through `inject`).
  Answers NOTES-windows.md request 1: per-device release is the core's (it tracks what each
  device holds and sends the ups when the device leaves); your tracker may merge devices, which is
  fine since the ups go through it.
- 2026-10-14: doc only, `Platform::thumbnail`: the Mac fits thumbnails in 208×132 at JPEG q0.6
  (2× the device's tile); 400 px works too but costs bandwidth (request 3). The core now asks every
  2 s for the streamed window and changed windows, every 6 s for the rest (WindowCatalog's cadence).
- 2026-10-14: doc only, `Platform::resize`: width/height are logical points (panel ÷ Aa scale); a
  backend with physical-pixel `Rect`s scales them. No signature changed.

## Answers to the backends' requests

- Windows 1 (release at the host's end): the core now calls `Platform::release_all_input()` as it
  stops; implement it as your `release_input()` (or keep calling it after `run` returns).
- Windows 3 (thumbnail size): no rescaling in the core; the Mac's box is 208×132 at q0.6. Yours
  works; smaller is only cheaper.
- Windows 2 (ring and the MSVC cross-check from a Mac): the TLS door needs a crypto provider with
  C in it (ring); `cargo check --target x86_64-pc-windows-gnu` is the cross-check from macOS. On
  Windows with the Build Tools the MSVC target builds normally.
