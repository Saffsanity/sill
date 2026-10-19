# Sill hosts for Windows and Linux

Rust hosts that speak exactly the protocol of Sill for Mac (`../Sources/StreamProtocol`,
`../Sources/SillHost`), so the iPhone and iPad app and the Mac viewer connect to a PC unchanged.
Work in progress.

## Layout

| Crate | What | Owner |
|---|---|---|
| `sill-protocol` | The wire format: the 14-byte header, kinds 0–28 and their JSON and binary payloads, hvcC framing, TLS 1.3 with pinned self-signed P-256 keys (ALPN `sill/1`, `sill-pair/1`), identities, pairing (codes, proofs, recognition tags, `sill://pair` links), the TXT record | core agent |
| `sill-host-core` | The host without an OS: the home door (plain for development, TLS with pairing like Sill.app), sessions, the catalog, source switching, frame pacing and dropping, keyframes, input placement, host settings (kinds 16/17), ping/tick/liveness, the hello and goodbye, the trust list on disk, an FFmpeg-subprocess HEVC encoder any backend may use, and a synthetic backend (test pattern) for running it anywhere | core agent |
| `sill-host-core/src/platform.rs` | The `Platform` trait: the one contract between the core and a backend | core agent only |
| `sill-host-windows` | Windows backend: Windows.Graphics.Capture, Media Foundation HEVC (hardware MFTs), SendInput with its own HID-usage → scancode map, Win32 windows, DNS-SD (`DnsServiceRegister`), the binary | Windows agent |
| `sill-host-linux` | Linux backend: X11 capture (XShm/XComposite), HEVC through FFmpeg (VAAPI or NVENC, libx265 as a fallback, as a subprocess or a dynamically loaded library), XTest input with its own HID-usage → keycode map, EWMH windows, Avahi, the binary; Wayland later through the portals | Linux agent |

Rules for everyone:
- Each agent edits only its own crates (and its `NOTES-*.md`). A backend that needs the trait or the
  core to change writes the request in its notes file and works around it meanwhile.
- The Swift host is the reference for every behaviour. Where it is ambiguous, match what the
  clients (`../iOSClient`, `../MacClient`) accept.
- `../Scripts/sillclient.py` is the conformance test: it speaks the whole protocol (the plain door,
  `--tls`, pairing, settings, input). The Mac viewer's Debug build (`-SillConnect host:port`) and the
  iOS app are the end-to-end tests.
- Keys on a PC: ⌘ and ⌃ both become Ctrl, ⌥ Alt, ⇧ Shift (a Mac device's ⌘C copies). Each backend
  maps HID usages to its own keys.
- Latency beats quality: drop frames, never queue them.
- Licences: the repository is Apache-2.0. Use permissively licensed crates (MIT, Apache-2.0, BSD,
  ISC, Zlib). No GPL code linked in (FFmpeg only as a subprocess or an LGPL build loaded
  dynamically; x265 only through such an FFmpeg). Sunshine (GPL-3) may be read for ideas, never
  copied.

## Building

```
cargo build -p sill-host-core            # anywhere; the synthetic backend runs on macOS too
cargo check -p sill-host-windows --target x86_64-pc-windows-gnu   # from a Mac: ring needs MSVC headers for -msvc
CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc \
  cargo build -p sill-host-windows --target x86_64-pc-windows-gnu --release   # brew install mingw-w64
docker build -f sill-host-linux/Dockerfile .   # see sill-host-linux/NOTES-linux.md
```
