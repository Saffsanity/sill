# Windows backend notes (sill-host-windows)

Owner: the Windows agent. Scope: `hosts/sill-host-windows/**` and this file.

## Status (2026-10-14)

- The whole `Platform` trait is implemented for Windows 10 1903+ and 11, and type-checks and lints
  clean for `x86_64-pc-windows-gnu` (against the real core) and `x86_64-pc-windows-msvc` (against
  a stub core: see Building); a real `.exe` with the core links with mingw-w64. **Nothing has run on Windows yet**: everything below that touches the OS is untested.
- `main.rs` serves devices: `sill-host-windows [host options]` is sill-host-core's `run` (milestone
  A, the plain home door, NOTES-core.md) with `WindowsPlatform`; the core's flags (`--port=N`,
  `--loopback`, `--name=NAME`, `--no-advertise`, `--bitrate=MBPS`, `--max-fps=N`, `--standard`)
  pass through. `--selftest` and `--list` test the backend alone. Backend log lines go through
  `sill_host_core::log` with a "Windows: " prefix.
- The platform-independent parts are unit-tested on macOS: 45 tests (the HID → scancode table
  against every usage the Mac maps, the key state machine incl. 2,000 random sessions, Annex-B
  splitting and parameter sets, absolute-coordinate normalisation round-tripping every pixel,
  wheel scaling, output sizes, JPEG/PNG/cursor conversion).

## Design

| Module | What |
|---|---|
| `keymap.rs` (portable) | HID usage (page 7) → Set 1 scancode + extended flag; all 82 usages the Mac maps (KeyStrokes.swift `virtualKeys`) plus Insert, keypad, non-US keys, Application, Print Screen, Scroll Lock, F13–F24. ⌘ and ⌃ → Ctrl (left/right kept), ⌥ → left Alt (right Alt is AltGr on many layouts), ⇧ → Shift. |
| `keys.rs` (portable) | `KeyTracker`: a device's key as PC key events. A key carrying modifier flags with no modifier key down (an older device's ⌘C) presses the PC modifier around it ("chord" modifiers, released once no non-modifier key is down); a modifier key held by two device keys (⌘ and ⌃ are both Ctrl) stays down until both are up; a key or text whose flags drop a modifier lets go of it first (KeyStrokes' rule); text lets go of all modifiers and goes out as KEYEVENTF_UNICODE ("\n"/"\r\n" Return, "\t" Tab, "\u{8}" Backspace as keys); `release_all` lets go of keys, then modifiers. |
| `annexb.rs` (portable) | Annex-B → `EncodedFrame`: NALs without start codes, VPS/SPS/PPS split out and cached (in-band or from MF_MT_MPEG_SEQUENCE_HEADER), sent with the first frame, every keyframe and after they change; AUD/EOS/EOB/filler dropped; keyframe = an IRAP NAL (16–23). `to_annexb` for the self-test's file. |
| `pointer.rs` (portable) | Desktop pixels → MOUSEEVENTF_ABSOLUTE\|VIRTUALDESK 0…65535 aimed at pixel centres (every pixel reachable, checked against Windows' `(n × size) >> 16`); pixel scroll deltas → wheel units (120 per ~50 px, remainder carried, horizontal negated for HWHEEL, clamp ±2400/event). |
| `sizing.rs` (portable) | Encoded size: × `StreamConfig.scale` (≤ 1), even, 64…4096 per side (long side capped at 4096 keeping the shape: many AMD/older GPUs stop there). |
| `imaging.rs` (portable) | Thumbnails (BGRA → JPEG q60, ≤ 400 px long side, as platform.rs says; the Mac sends 208×132), icon PNGs (premultiplied → straight alpha, square, 128 px), cursor bitmaps (colour+mask and monochrome AND/XOR) → RGBA. |
| `win/catalog.rs` | EnumWindows in Z order, filtered like Alt-Tab: visible, not minimized (a minimized window shows nothing to stream, as the Mac lists on-screen windows only), not owned, not WS_EX_TOOLWINDOW/NOACTIVATE unless WS_EX_APPWINDOW, not DWM-cloaked, a title, ≥ 100×100 (DWMWA_EXTENDED_FRAME_BOUNDS, physical px), not this process or its console, not Progman/WorkerW/tray. App: packaged apps by AppUserModelID (GetApplicationUserModelId; ApplicationFrameHost windows resolved to the CoreWindow child's process) with the Applications folder's display name; others by executable path (QueryFullProcessImageNameW) with its FileDescription. Window ID = HWND truncated to 32 bits, sign-extended back. `listed(id)`: every per-window call checks the ID names a window the list would show. |
| `win/apps.rs` | Start Menu `.lnk` files in ProgramData's and AppData's Programs folders (IShellLinkW target; app ID = target .exe so it matches its windows, else the .lnk), uninstallers/readmes/help skipped, plus packaged apps from shell:AppsFolder (parsing name with `!`); deduplicated by ID and name, sorted. `launch` only for an ID the app list or a listed window names (ShellExecute of the .lnk, the .exe, or `shell:AppsFolder\AUMID`). Icons via IShellItemImageFactory (ICONONLY, 128 px) → PNG. |
| `win/input.rs` | SendInput: moves/buttons as one absolute virtual-desk event each, scroll = move + WHEEL/HWHEEL, keys by scancode (KEYEVENTF_SCANCODE, EXTENDEDKEY when extended), text by KEYEVENTF_UNICODE; dwExtraInfo marks Sill's events. Double/triple clicks are Windows' own counting. Scroll phases only reset the wheel remainder. A refused SendInput (UIPI: elevated window, secure desktop) is logged once. `release_all` on request and on drop. |
| `win/winops.rs` | raise: restore if minimized (ShowWindowAsync), a no-op SendInput to satisfy the foreground lock (as PowerToys does), SetForegroundWindow, then the AttachThreadInput fallback. resize: takes logical points (platform.rs: × the window's DPI ÷ 96) and returns points; keeps the top-left, sizes the visible frame (window rect minus invisible borders), SWP_ASYNCWINDOWPOS, waits ≤ 0.5 s for the app to settle and returns what it took. Commands: WM_SYSCOMMAND SC_CLOSE / SC_MINIMIZE / SC_MAXIMIZE↔SC_RESTORE (PostMessage: a hung app never blocks). |
| `win/gdi.rs` | HBITMAP → bytes; PrintWindow(PW_RENDERFULLCONTENT) into a DIB, cropped to the visible frame (skips hung and all-black windows). |
| `win/cursor.rs` | GetCursorInfo/GetIconInfo → PNG + hotspot (physical px), only when the shape changes; polled at 20 Hz by each stream. |
| `win/dnssd.rs` | DnsServiceConstructInstance/DnsServiceRegister: `<name>._sill._tcp.local` on `<host>.local`, TXT keys as given; DnsServiceDeRegister on drop. |
| `win/d3d.rs` | One D3D11 device per stream, on the first hardware HEVC encoder's adapter (MFT_ENUM_ADAPTER_LUID → EnumAdapterByLuid), BGRA + VIDEO support, multithread-protected, wrapped for WinRT (IDirect3DDevice) and MF (IMFDXGIDeviceManager). |
| `win/capture.rs` | Windows.Graphics.Capture: GraphicsCaptureItem from the HWND or the primary HMONITOR (IGraphicsCaptureItemInterop), free-threaded frame pool (3 buffers, B8G8R8A8), IsCursorCaptureEnabled false, IsBorderRequired false (Win 11), MinUpdateInterval 1/fps (24H2). The FrameArrived handler keeps only the newest frame. Pool recreated when the content size changes; Closed → the stream ends ("The window closed."). |
| `win/convert.rs` | D3D11 video processor: BGRA (full range RGB) → NV12 (BT.709, video range), scaled to the encoded size, auto-processing off. Colour spaces through ID3D11VideoContext1's DXGI types (RGB_FULL_G22_NONE_P709 → YCBCR_STUDIO_G22_LEFT_P709) where available (some drivers ignore the older struct's range), else the older struct. |
| `win/encoder.rs` | MFTEnumEx(VIDEO_ENCODER, HEVC out): hardware (MFT_ENUM_FLAG_HARDWARE\|SORTANDFILTER) first, then software (SYNCMFT\|ASYNCMFT, NV12 in). Async MFTs unlocked (MF_TRANSFORM_ASYNC_UNLOCK), D3D-aware ones get the device manager. ICodecAPI: AVLowLatencyMode on, CBR at the bitrate, 1 s buffer, 0 B-frames, GOP fps×4 (the Mac's safety interval), QualityVsSpeed 0 with "prioritize speed" else 50; ForceKeyFrame per requested frame. Output type HEVC Main 4:2:0 8-bit with BT.709 video-range VUI, input NV12. Async events read by a thread blocking on GetEvent (shut down via IMFShutdown); each MFT detached from its IMFActivate right after activation (the activate caches its object, so a rebuild after a resize would otherwise get the shut-down MFT back). One frame inside at a time, raised to 2…4 only if an encoder returns nothing for 50 ms with fewer; frames inside are tracked by sample time (an output at time T settles every frame up to T, so a frame the encoder dropped does not linger). Output samples reused while ProcessOutput gives nothing. Stream changes renegotiated; parameter sets from the stream or MF_MT_MPEG_SEQUENCE_HEADER. A non-D3D encoder gets NV12 bytes read back through a staging texture. |
| `win/stream.rs` | The stream thread: newest WGC frame → copied into our own BGRA texture (the capture buffer goes back at once) → converter → encoder, paced to `fps`, frames dropped never queued. Keyframe requests ride the next frame, or re-encode the last picture once the source has been still 50 ms. A content size that holds for 150 ms rebuilds converter and encoder. A hardware encoder that errors, is full with nothing back for 1.5 s, or keeps new frames out for 1.5 s without asking for input is replaced by the software one, once (the hung one is torn down on a thread of its own, since a wedged driver can block its teardown); then the stream ends with the reason. A still source whose encoder still holds a frame after 100 ms gets the last picture once more, so the last change reaches the devices. `timeBeginPeriod(1)` while streaming (60/120 fps pacing). `source_rect`: the window's frame bounds or the monitor's rect, physical px. |
| `win/mod.rs` | `WindowsPlatform`; per-monitor-v2 DPI awareness set once at start (so window rects, capture, SendInput and GetCursorPos all speak physical pixels); `release_input()`. |
| `selftest.rs` | `--selftest` / `--list` (below). |

## Building

From macOS (what was run here, 2026-10-14, against the real core at milestone A):

```
rustup target add x86_64-pc-windows-msvc x86_64-pc-windows-gnu
brew install mingw-w64                       # for the GNU target's C compiler and linker
cargo check  -p sill-host-windows --target x86_64-pc-windows-msvc
cargo clippy -p sill-host-windows --all-targets --target x86_64-pc-windows-msvc -- -D warnings
cargo clippy -p sill-host-windows --all-targets --target x86_64-pc-windows-gnu  -- -D warnings
cargo test   -p sill-host-windows            # the portable modules, 45 tests
CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc \
  cargo build -p sill-host-windows --target x86_64-pc-windows-gnu --release
```

Results: clippy (`--all-targets`) has no findings in this crate on the GNU and macOS targets
(`-D warnings` trips only on three lints inside sill-host-core, so run it without and read this
crate's lines); 45/45 tests pass; the release `.exe` (11.5 MB, PE32+ x86-64 console) imports only
system DLLs (kernel32, user32, gdi32, d3d11, dxgi, mfplat, dnsapi, dwmapi, iphlpapi, ws2_32,
combase, shell32, version, winmm, bcrypt, the UCRT api sets…), no mingw runtime.

The MSVC target cannot be checked against the real workspace from macOS: sill-protocol depends on
`ring` (through rustls), whose build script compiles C for the target and needs the MSVC CRT
headers (`assert.h`), which only the licence-gated MSVC/xwin download provides (not installed, per
the rules). So for `x86_64-pc-windows-msvc` this crate was checked and linted (`-D warnings`,
clean) in a scratch workspace whose sill-host-core is a stub with the real `platform.rs` and the
real signatures of `run`, `HostOptions` and `log` (outside the repo). The Windows code is the same
for both targets. On a Windows PC with Visual Studio Build Tools, MSVC builds normally.

On Windows (the real thing):

```
rustup default stable-x86_64-pc-windows-msvc   # Visual Studio 2022 Build Tools with the C++ workload
cd hosts
cargo build -p sill-host-windows --release
target\release\sill-host-windows.exe --list
target\release\sill-host-windows.exe --selftest --frames 300 --out %TEMP%
target\release\sill-host-windows.exe            # the host; allow it through Windows Firewall
```

Devices (Debug builds of the apps, which still dial the plain door) find it by Bonjour, or by
address with the Mac viewer's `-SillConnect <pc-ip>:<port>` (the port is in the "Home door" line;
`--port=N` fixes it). Windows Firewall asks the first time the host listens: allow "Private".

## Requirements on the PC

- Windows 10 1903 (build 18362) or later, 64-bit; Windows 11 recommended (no yellow capture border;
  borderless capture needs 11). mDNS advertising needs Windows 10 1809+ (DnsServiceRegister).
- An HEVC encoder Media Foundation can use: a GPU with hardware HEVC encode (NVIDIA GTX 950 / 9xx
  2nd gen Maxwell or later, AMD RX 400 / Polaris or later, Intel 6th-gen Skylake or later) with
  its current driver, or Microsoft's "HEVC Video Extensions" from the Store (software; slow).
  With neither, a stream fails with a message saying so (`encoder::NO_ENCODER`).
- Input reaches elevated windows (Task Manager, installers, admin consoles) only when the host
  runs as administrator; never the secure desktop (UAC prompts, lock screen).

## Test checklist for a human on Windows

Build as above, then (nothing here needs a device unless it says so):

1. `--list`: the windows you see in Alt-Tab, front to back, minus minimized ones and the console;
   sensible app names ("Notepad", "Microsoft Edge", "Calculator" for the UWP calculator, not
   "Application Frame Host"); app IDs are .exe paths or `…!App` AUMIDs. Installed apps: your Start
   menu's apps, no uninstallers, no duplicates, Store apps included. Encoders: your GPU's
   ("NVIDIA HEVC Encoder MFT", "AMDh265Encoder", "Intel® Quick Sync Video H.265 Encoder MFT") first.
2. `--selftest`: writes `selftest-thumbnail.jpg` (the front window, ~400 px, colours right),
   `selftest-icon.png` (its app icon, transparent background), streams the primary display; move
   windows around so frames flow. Expect ~60 fps, a keyframe first (with VPS/SPS/PPS) and one
   mid-way; cursor shapes printed when you move over text/links. Play `ffplay -f hevc selftest.h265`
   (or VLC): picture right-side up, correct colours (no green/pink tint: BT.709 video range), no
   cursor in the video, no yellow border (Windows 11).
3. Leave the screen still during `--selftest`: it must still report a keyframe for the still
   source ("no keyframe came for a still source: FAIL" is a bug).
4. `--selftest --window <id from --list>`: one window only; resize it during the run → a line
   "Source resized: …" ~150 ms after you stop, frames continue at the new size; close it → "stream
   ended: The window closed."
5. HiDPI: on a 150 % display the sizes in `--list` and the capture are physical pixels (a
   maximized window on a 3840×2160 screen ≈ 3840 wide).
6. Laptop with two GPUs (Intel + NVIDIA): the encoder line says which, and the stream works.
7. No hardware HEVC (e.g. a VM): with HEVC Video Extensions installed, "software,
   system-memory input" and frames; without, the NO_ENCODER message.
8. Once the core serves devices (iPad/iPhone/Mac viewer): pick windows and the Desktop; tap,
   drag (text selection), double-click a word, triple-click a line, right-click; two-finger
   scroll vertical and horizontal (a long web page, a wide spreadsheet: direction natural, speed
   reasonable); type with the software keyboard (accents, emoji, Return, Backspace); a hardware
   keyboard: arrows, Home/End, Delete, F-keys, ⌘C/⌘V (= Ctrl+C/V), ⌘⇧T in a browser, ⌥-letter in
   menus, Caps Lock; Spotlight key (⌘Space) must leave nothing held: the next tap is a plain click
   (no Ctrl-click). Disconnect while holding ⌘: no stuck Ctrl on the PC.
9. Raise: pick a window that is behind others or minimized → it comes to the front with the
   keyboard (typing goes there). Note any "Windows kept another window in front" line.
10. Aa / text size: the window resizes to fit the device, its top-left stays put; an app with a
    minimum size reports what it took.
11. Thumbnail menu: close (an unsaved Notepad asks "Save?"), minimize, full screen (maximize, and
    again to restore).
12. Launch from "All apps": a desktop app, a Store app (Calculator), a shortcut with arguments.
13. Advertising: the device lists the PC under its name without typing an address (Bonjour browse
    `_sill._tcp`); `dns-sd -B _sill._tcp` from a Mac on the same network shows it with its TXT keys.
14. Elevated window (Task Manager) in front: input does nothing and one log line says why; run
    the host as administrator and it works.
15. Five minutes of streaming a busy window at 60 fps: frame age stays low, CPU low (hardware
    encoder), no "Encoder: allowing N frames inside" line (if there is one, note the GPU).

## Untested (needs a real Windows machine)

Everything in `win/`: enumeration and filtering, UWP resolution, FileDescription names, Start Menu
and AppsFolder scans, ShellExecute launches, icons (incl. whether the shell's bitmaps are really
premultiplied), PrintWindow thumbnails, SendInput of every kind (incl. scancode/extended choices
per key and the KEYEVENTF_UNICODE surrogate handling), the foreground nudge and AttachThreadInput,
resize settling, WM_SYSCOMMAND commands, cursor capture (colour, monochrome, animated cursors),
DnsServiceRegister (incl. whether a NULL address makes Windows publish the host's own addresses),
WGC on Windows 10 vs 11 (cursor/border flags), the video processor's colour conversion, every
encoder vendor's behaviour (NV12 surfaces with BIND_VIDEO_ENCODER, async event flow,
ForceKeyFrame honoured, low-latency output per input, SPS VUI), the software encoder path
(readback), size changes, the hardware → software fallback, timeBeginPeriod pacing at 120 fps,
and DPI awareness.

## Review

A read-only review of the media pipeline and input code (a second agent, 2026-10-14) found, and
this version fixes: the cached MFT reused after its shutdown on every resize; false "hung" verdicts
from counting one output per input; a hung encoder's teardown blocking the fallback; an encoder
that stops asking for input freezing silently; Num Lock sent as Pause (now extended 0x45); the
older colour-space struct being ignored by some drivers. Left as known gaps: on Windows 11 an
unpackaged app may need `GraphicsCaptureAccess::RequestAccessAsync(Borderless)` before
`SetIsBorderRequired(false)` takes effect (cosmetic: the yellow border); the mDNS instance is
registered without addresses (Windows answers `<host>.local` itself, but perhaps not on a Public
network profile); the software path maps its staging texture synchronously (stalls the GPU a little
per frame; double-buffer if it matters); after `MF_E_TRANSFORM_STREAM_CHANGE` an async MFT is not
asked for output again until its next HaveOutput.

## Requests to core

1. ~~A way to let go of held input.~~ Answered by the core (NOTES-core.md): a device that leaves
   gets key-ups (modifiers 0) and button-ups, which release this backend's chord modifiers too.
   Still open, minor: nothing at the host's own end if a key is down then; main.rs calls
   `WindowsPlatform::release_input()` after `run` returns, so it is covered here anyway.
2. **Cross-checking the MSVC target from a Mac**: `ring` (rustls' provider) needs the MSVC CRT
   headers to build for `x86_64-pc-windows-msvc`, so README's `cargo check -p sill-host-windows
   --target x86_64-pc-windows-msvc` fails on macOS without the licence-gated xwin download. The GNU
   target works with mingw-w64. No change needed on Windows itself; maybe README should say
   `--target x86_64-pc-windows-gnu` for cross-checks.
3. **Thumbnail size**: platform.rs says ~400 px on the long side; the Mac sends 208×132 (2× the
   device's tile). This backend follows platform.rs; tell me if the core rescales or wants the
   Mac's box.
4. (FYI) `Source::Desktop` here is the primary monitor; `source_rect` and input coordinates are
   physical pixels of the virtual screen (negative on monitors left of/above the primary).
5. (FYI) This backend also rebuilds its converter and encoder when a window's captured size
   changes mid-stream (150 ms settle), so the picture is right before the core's catalog notices
   the resize and restarts the stream.
6. (FYI) A window's ID is its HWND truncated to 32 bits; `windows()` excludes minimized windows
   (as the Mac lists on-screen windows only), so a device minimizing a window from the thumbnail
   menu sees it leave the list.

## Open questions

- Right ⌥ maps to the left Alt (not AltGr) so shortcuts work on every layout; typing AltGr
  characters from a hardware keyboard then needs the software keyboard. Keep?
- Wheel speed: 120 units per ~50 px of device scroll. Needs a feel test (checklist 8).
- Encoded size is capped at 4096 per side (AMD/older GPUs); a 5K/8K desktop at scale 1.0 is
  scaled down. Raise to 8192 for NVIDIA/Intel?
