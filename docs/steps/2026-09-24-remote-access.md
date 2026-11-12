**Remote access (2026-09-24/25, branch `remote-access` from `a9cc248`; the plan,
its open questions and the results are in `docs/remote-access-plan.md`).** Bring
your own VPN (Tailscale, WireGuard into the home network) or, behind a switch
of its own, a port forward: a device paired once reaches the Mac from anywhere.
Every open question took its default. Steps 1–8 are committed, and so are the
fixes of step 9's first review round (below); the branch merged as PR #13
(ba91136), with its merge and review in the entry above.
- Two doors. The home door (today's plain TCP listener, Bonjour, unchanged for
  old iOS builds) now admits only this Mac's own networks, loopback and Direct
  Wireless (`OriginPolicy`), with caps (1 MiB messages, 4 kind-17 changes a
  second, a clean device name). The remote door (`RemoteServer`, port 7455) is
  TLS 1.3 only, both ends self-signed P-256 keys pinned by SPKI SHA-256, ALPN
  `sill/1` for a paired key, `sill-pair/1` only while a pairing window is
  open; pre-auth caps (8 pending, 2 per source, backoff after 5 of its own
  refusals), 8 sessions, remote clients evicted after 8 s of silence, forced
  keyframes at least 2 s apart. Kinds 18 (the signed MacInfo: Mac ID, name,
  addresses), 19/20 (one pairing request and its answer), 21 (Pair This iPad…,
  home door only) and 22 (goodbye) are skipped by older readers; the TXT record
  carries a recognition tag (`r`) only paired devices can read.
- Pairing: the Mac's window shows a QR code (`sill://pair?…`, pinned to the
  Mac's key) and a 12-digit code (Damm check digit; PBKDF2 600k), 5 minutes,
  single use, five wrong tries, and the address to type with the code:
  Tailscale's MagicDNS name and its IPv4 under it ("or 100.101.102.103"), else a
  Tailscale IP (100.64/10, else fd7a:115c:a1e0::/48), else this network's
  address with any other VPN's IP under it ("or 10.8.0.6"). Another VPN never
  takes this network's place, since NordVPN's or WARP's address answers from
  nowhere; which of the two goes first is Noah's call. `PairingWindowAddress`
  decides, pure (Noah, 2026-09-25: from an iPhone's hotspot this network's
  address answered nothing, the Tailscale name and address both paired;
  checked with swiftc, 80 checks and 35 of 35 mutants, and photographed as the
  previews' `pairing-novpn`, `pairing-othervpn` and `pairing-longname`).
  Sill.app: Settings › Remote Access (a fifth tab: the switch, the addresses,
  the port, paired devices, the internet switch with the router's answer, the
  address name, sleep), the menu's Remote Access… and Pair iPhone or iPad…,
  identity in the login keychain (`KeychainIdentityStore`; label "Sill Remote
  Access", service `me.saffer.sill.remote`), idle sleep held off while a
  device is connected remotely. The CLI's `--remote` uses a throwaway identity
  per run.
- iOS: `DeviceIdentity` (a Keychain key, this device only), `SavedMacs`,
  `RemoteDialPolicy` + `RemoteConnector` (the dial order, happy-eyeballs 1 s
  apart, every failure's words), Remote rows after the network's 3 s, the
  reconnect order after a loss, liveness on every route; the connect screen's
  "Add a Mac…" card (the VisionKit scanner or the typed address and code),
  `sill://pair` links only ever confirmed, Pair This iPad… as an overlay over
  the stream, the panel's route line ("Connected through Tailscale · 48 ms"),
  its Away from home group and the slow-link callout; the Low preset (4 Mbps,
  first of the seven on both sides) and 60 fps away from home.
- Verified without Noah's devices: the plan's H1–H24 headless (the CLI's
  output byte for byte, the pure checks with mutants, the doors' refusals and
  caps, no plaintext on the wire, no code or secret in any log, a 2 Mbps
  +150 ms relay with no eviction and the base's keyframe rate), the app's
  persistence and previews, and on the simulator S1–S8: about 200 photos at
  the Duo sizes, phones and larger text, taps and accessibility as XCUITests,
  live pairing (QR, typed, an outside link confirmed first), reconnects,
  every failure's words, an older host, and a slow link (60 fps through a VPN
  route; the callout at +300 ms).
- Review fixes (step 9, the plan's "Review fixes (step 9)"): a pick never
  streams Sill's own windows (the virtual display's lookup skips them; the
  Desktop looks for Sill among every window when the on-screen look missed it);
  the internet switch counts only while Remote Access is on; Remove changes
  nothing when the keychain cannot be written, and the pane says so; a spent
  code shows no QR; kind 18 lists no addresses before the Mac's first look,
  and a device keeps its saved ones on an empty or Remote-Access-off kind 18;
  an overlay pairing ties the session only to the same Mac (by its signed kind
  18) and takes that kind 18's addresses; the scanner never restarts a pairing
  by itself (after a failure, the same code only from a tap); a link confirmed
  over the stream keeps the overlay for its outcome; the overlay's typed path
  says "Enter the Code from ‹Mac›" and moves up while typing; the status line
  is announced; saved Macs are cleared only when no device key exists at all.
  Checked headless, on the simulator with three new XCUITests against live
  hosts, and against the pre-fix build (which fails them).
- **Untested, for Noah (R0–R13; the plan's Results say exactly what):** R0 the
  probes (the Secure Enclave key, the login keychain identity with your OK, the
  router probe, the scanner on the iPad, with a failed pairing's code held
  until tapped); R1 Tailscale setup and pairing,
  timed; R2 away on the hotspot; R3 leaving home mid-stream; R4 Wi‑Fi to
  cellular; R5 Tailscale off at either end; R6 sleep; R7 removing the iPad
  while it streams; R8 a rebuild keeps port, Mac ID and pairing; R9 Pair This
  iPad… at home; R10 the port forward; R11 Direct Wireless at the café; R12
  VoiceOver and a hardware keyboard (Esc never reaches an app in the iPadOS 27
  simulator; only ⌘. was tested); R13 mixed builds. Also the pairing window's
  Address row, live (only its offscreen previews were seen): with this build's
  Sill.app, Pair iPhone or iPad… reads this Mac's MagicDNS name with "or" and
  its Tailscale IPv4 muted under it (what `SillHost --print-reachability`
  lists); with the window open, Tailscale off on the Mac gives 10.128.0.34
  alone and a window 18 pt shorter, and back on the name and the "or" line
  return (the IPv4 alone for a few seconds, until MagicDNS answers, is
  expected; note it if it stays); each line selects without "or" and pastes
  (Universal Clipboard) or types into Enter Code Instead (a code works once:
  New Code, or reopen the window, for a second try); VoiceOver reads the "or"
  line as one element. And a decision: beside a VPN that is not
  Tailscale (NordVPN, WARP, a work VPN, your own WireGuard) the window shows
  this network's address with that VPN's IP under it; the other order, or
  this network's address alone, is one line in `PairingWindowAddress.choose`.
- Known: the simulator iPad Pro 13" is shared with other work, so a test that
  installs the app there can replace someone else's build (the iPad Pro 11"
  was used for S8); an unsigned simulator build cannot use the keychain on a
  fresh simulator (-34018): build it ad hoc signed (`CODE_SIGN_IDENTITY=-`).
