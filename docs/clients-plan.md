# The Android client

Branch `android-client`, 2026-10-18. The request was to "add full support for Windows and Android"
with no regressions for the Apple platforms, then to land each system on its own, Android first.
This file records what the Android client and the core it shares came to mean, the decisions, how
each part was checked, and what only real devices can show. The Windows client and the Windows and
Linux hosts come in their own changes on top of this one.

## What "support" means here

Sill has no platform layer to extend. The Mac host is ScreenCaptureKit, VideoToolbox,
Accessibility, a private virtual-display API and Network.framework end to end. The iPhone and iPad
app is SwiftUI and UIKit. Only `Sources/StreamProtocol` (the wire) is shared. So:

- **Android is a client.** The Mac stays the machine that streams its windows, which is what the
  product is (docs/BRIEF.md).
- **One shared core, in Kotlin on the JVM** (`clients/core`), the way StreamProtocol is shared by
  the Mac and the iPad. It runs unchanged on Android and on any JVM (the later Windows client). It
  has no dependency but the Kotlin standard library: JSON, DNS, DER and TLS pinning are written out, as
  the Swift side writes its certificate by hand.
- **Nothing on the Apple side changed.** No file under `Sources/`, `iOSClient/`, `Package.swift`,
  `Scripts/` or `Tests/` was modified. `.github/workflows/ci.yml` only gained `clients/**` in its
  `paths-ignore`, so a change confined to clients/ does not start the macOS job.
- **Not parity with the iPad app.** The client does what a session needs: discovery, pairing (ask
  and code, a pairing link, Add a Mac by address), TLS with pinned keys at both doors, the remote
  dial of a saved Mac, the reconnect, the window bar, apps, the picture, mouse, touch, keyboard,
  the clipboard both ways, quality, text size and the goodbye words. It does not have the Mac's
  menus, trackpad gestures, the first-run tour, the Duo or phone layouts, Direct Wireless, the
  cable rule, Larger Picture or the iPad's on-screen key row and trackpad. The wire carries them
  (`SillSession.fetchMenu`, `gesture`), and the UI does not offer them yet.

## Layout

- `clients/settings.gradle.kts`, `build.gradle.kts`, `gradlew`: one Gradle build. `:android` is
  included only where an Android SDK is configured, so the core builds anywhere with a JDK 17 or
  later.
- `clients/core`: `Json`, `StreamMessage` (framing, kinds, parameter sets, blobs, Annex B),
  `Payloads` (every JSON payload, field for field), `Text` (SillVersion, SafeText, the address
  parser with the C library's inet_* written out), `Crypto` (base64url, SPKI, the Mac ID, the
  hand-built certificate, pairing codes and proofs, recognition tags, pairing links, kind 18's
  signature), `Tls` (TLS 1.3, one ALPN, SNI "sill", the pin as the whole of trust, no resumption),
  `Mdns` (one-shot multicast DNS queries from an ephemeral port), `Session` (hello first, the reader
  with the Mac's caps, ping, liveness, stats, the auto-Desktop rule, keyframe gating, move
  coalescing), `Pairing` (ask, code, link, cancel, the saved Macs), `Policy` (the goodbye words, the
  home dial, the redial schedule), `Client` (what an app is a view over), `Keys` (HID usages
  from Android and AWT key codes, the modifiers, the coast, frame mapping), `TouchGestures`,
  `HevcSps`, `ReplayingRouter`. Test fixtures: `ModelHost` (a model of the Mac's TLS door) and
  `HevcSample` (libx265 streams as the Mac sends VideoToolbox's).
- `clients/android`: the Android app. Platform APIs only (no AndroidX), minSdk 29 (TLS 1.3 and
  ALPN), MediaCodec on a SurfaceView, the device key sealed by an Android Keystore key.
- `clients/wire-vectors`: `generate.sh` compiles the real StreamProtocol with swiftc (on Linux too:
  13 of its 17 files as they are, `Remote.swift` without its two signing functions) and writes
  `vectors.json`. `--verify` regenerates the file and compares it by content. `--check` decodes
  what the Kotlin core wrote, using the Mac's own types. `mdns_fixture.py` (python-zeroconf) and
  `hevc_sample.sh` (libx265) make the other fixtures.
- `.github/workflows/clients.yml`: two jobs (core with the Swift check, Android).

## Decisions taken (each the default a later change can revisit)

1. **A client only.** As above.
2. **Kotlin on the JVM.** One implementation of the wire and its rules, which a desktop client can
   share later, instead of one per platform.
3. **No third-party dependency.** MediaCodec decodes HEVC in hardware on every device that has it;
   the app uses platform APIs only (no AndroidX).
4. **Discovery by one-shot mDNS queries** (RFC 6762 §5.1) from an ephemeral port on every
   multicast interface. Nothing binds port 5353 (Android's mdnsd holds it), and Android needs no
   multicast lock. Queries go out at once, then after 1 and 2 s, then every 3 s; a Mac that stops
   answering drops off after its TTL.
5. **Ctrl is ⌘** on an Android hardware keyboard, so Ctrl+C copies on the Mac as it does on the
   device. Meta is ⌃ and Alt is ⌥.
6. **Keys as text or keys by the iPad's rule** (KeyChords.swift): keys without text and shortcuts
   go as keys, everything else as the text it types, so the Mac's keyboard layout never re-maps
   what was typed.
7. **The clipboard:** the Mac's copies arrive on the device's clipboard. The device's copy goes to
   the Mac when the stream window comes back to the front, if it changed. The iPad needs a Paste
   tap because of iOS's paste prompt; Android has no prompt.
8. **The device key at rest:** PKCS#8 sealed with AES-GCM by a non-exportable Android Keystore key.
9. **Scrolling:** a mouse wheel is a scroll gesture (began, deltas, ended after 120 ms still), so
   Mac apps rubber-band; fingers coast by the iPad's rule.
10. **Package name:** `me.saffer.sill`, the iOS bundle ID. Version 0.6.0, build 1.
11. **Releases of the apps in `clients/` never touch the Mac's.** Sill.app's update check reads
    GitHub's latest release (`releases/latest`), the site's download page links that release's
    `Sill.dmg`, and release.yml runs on every `v*` tag. So a client's binary, when one is
    published, goes out on a tag of its own (`android-v0.6.0`), never `v*`, as a release that is
    not marked latest (`gh release create --latest=false`): otherwise every Mac would be offered
    an Android build and the download link would break. Nothing publishes one yet: clients.yml
    keeps the debug APK as a run's artifact only.

## How it was checked (on this Linux machine, 2026-10-18)

- **The wire against the Mac's own Swift.** swift.org's 6.1.2 toolchain compiled the real
  StreamProtocol and produced 57 payloads (every kind the clients read or write), 8 binary layouts,
  25 versions, SafeText's class of every Unicode scalar and 69 address cases. The core decodes every
  payload and round-trips it, and Swift decodes all 57 of Kotlin's encodings back to the Mac's
  values (`generate.sh --check`: ALL PASS). SafeText agrees on all 1,112,064 scalars except 5,812:
  exactly the characters Unicode 15.1 and 16.0 added, which Java 21's Unicode 15.0 does not know
  (it removes them from a name; Swift keeps them). A renamed Swift field makes `--verify` fail
  (tried, then restored).
- **Crypto against independent implementations.** The pairing vectors that Tests/checks/protocol
  holds the Swift code to (computed in Python) pass: PBKDF2 at 600,000 rounds, both proofs on both
  paths, the Mac ID, the recognition tag. openssl verifies the hand-built certificate's
  self-signature, reads it as v3 / ecdsa-with-SHA256 / prime256v1 / until 9999, and hashes its SPKI
  to this core's fingerprint. openssl's `dgst -verify` accepts kind 18's signature.
- **TLS against openssl.** This core dials `openssl s_server` (TLS 1.3, client certificate
  required, ALPN `sill/1,sill-pair/1`): handshake, pin, ALPN, bytes through. Another pin is refused
  before anything is sent; a server without Sill's ALPN reads as "not a Sill door". `openssl
  s_client` with an openssl-made certificate pairs with the model Mac.
- **The model Mac** (`ModelHost`): the hello first on every session (the model records a violation
  otherwise; none occurred), the viewport, the auto-Desktop pick, keyframe gating, 200 pointer moves
  sent as 1–3, a stale kind 26 dropped, stats and pings, a kind 18 from another key ignored, a
  goodbye then the close, silence ending the session at the liveness limit, a 5 MiB header refused
  before its payload, a refused key ending the session as refused. The whole client: ask, the Mac's code (a typo caught locally), a pinned
  session, the row recognized by its tag under another Bonjour name, the same identity at the next
  launch, a quit and the reconnect, a removal (no reconnect, the row "Not paired"), a removal while away (the next dial refused: "pair
  again"), an open door,
  pairing by link then the remote dial at kind 18's address, Add a Mac by typed address and code.
- **mDNS:** a response that python-zeroconf built parses. zeroconf reads this core's queries as
  intended (both questions, the QU bit). TTLs and goodbyes behave. With `SILL_LIVE_MDNS=1`, a live
  zeroconf responder on this machine's eth0 was found over the network in 1.7 s.
- **Video:** the HEVC SPS parser reads 320×240 and 642×418 (the latter through its conformance
  window) from libx265 streams split as the Mac sends VideoToolbox's output.
- **Android:** `assembleDebug` and `assembleRelease` build. Android lint runs with
  `checkDependencies`, so the core's API use is checked against minSdk 29. It found one real crash
  (`Activity.getDisplay()` needs API 30) and three other findings (backup rules, `performClick`,
  `commit()`'s reason), all fixed. What remains is one note that Gradle 8.14.6 is out.
- **Repetition found two real bugs**, both fixed, each with a test. First, a session the Mac ended
  at once (a refused key) shut its timer down while `start()` was still scheduling on it; the
  `RejectedExecutionException` would have killed the client's worker thread. Second, a key refused
  after the TLS 1.3 handshake (an alert on the first read) or at the dial read as a lost link, so a
  removed device retried for ever instead of asking to pair again. Three earlier timing races were
  in the tests, not the code. The final code ran the core's suite (52 tests) 20 times in a row
  clean.

## Untested: what only real devices and a real Mac can show

Nothing here ran against a real Mac. The model Mac is this repository's reading of the host's
rules, not the host. Nothing ran on an Android device (no KVM here, so no emulator). The first
thing to do with a real Mac is the list below, in order:

1. **A1, pairing at home:** Sill.app on the Mac, the app on a phone on the same Wi-Fi
   (`adb install -r android/build/outputs/apk/debug/android-debug.apk`). The Mac is listed with "Not
   paired". A tap brings up the Mac's pairing window; its code pairs and the session starts
   (Sill.log: "Client hello: ‹phone›, Sill 0.6.0 (1), protocol 1"). This is the first proof that the
   Mac's Network.framework accepts Android's client certificate and handshake.
2. **A2, the picture:** the Desktop at Retina size through MediaCodec (`KEY_LOW_LATENCY` on Android
   11 and later); the fps and frame age in the bar.
3. **A3, input:** tap, long press as a right-click, one- and two-finger scrolling and the coast, the
   soft keyboard, a hardware keyboard and mouse (ChromeOS, DeX), rotation.
4. **A4, the bar:** thumbnails, a window picked, Apps, Quality, text size, Disconnect, and the Mac
   quitting Sill (the words and the reconnect).
5. **A5, links and away from home:** the camera app opening the Mac's QR code (confirmed before
   pairing); Add a Mac by the address the pairing window shows (Tailscale).
6. **A6, the key:** it survives an app restart and not a reinstall.
7. **Also:** Universal Clipboard is the Mac's; the clipboard both ways; a Mac on another subnet
   (not listed: Add a Mac by address); a Mac whose Require pairing is off (the open door).

Known gaps, to do next: the Mac's menus and the trackpad gestures in the UI, an adaptive icon,
localization, a session that survives the activity (a foreground service), and a signed release
build.
