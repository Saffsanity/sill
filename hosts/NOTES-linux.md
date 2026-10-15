# Linux backend notes (sill-host-linux)

Owner: the Linux agent. Scope: `hosts/sill-host-linux/**` and this file.

## Status (2026-10-14)

- **The whole `Platform` trait is implemented for X11** (Xorg sessions, and X11/XWayland apps; see
  "Wayland" for what a Wayland session needs) and **runs end to end** with the core's plain home
  door (milestone A): in a Docker container (Xvfb 1920×1080, openbox, xterm, xeyes, xclock,
  Mousepad) it streams to `Scripts/sillclient.py` and to the Mac viewer's Debug build on this Mac,
  and device input (kind 8) lands in X apps. Not run on a real Linux desktop or with VAAPI/NVENC.
- `sill-host-linux [core options] [--encoder=libx265|hevc_vaapi|hevc_nvenc]` is the host (the
  core's `run` with `LinuxPlatform`); `--selftest [DIR]` tests the backend alone (32 checks, all
  passing in Docker, three runs in a row); `--list`, `--launch ID`, `--window CMD ID` are debugging
  aids.
- Pure parts tested anywhere: `cargo test -p sill-host-linux` (22 tests: the HID table against every
  usage the Mac maps, the key state machine with 20,000 random events, text → keysyms and the spare
  keycode plan, wheel accumulation, BGRA downscaling, desktop entries and Exec parsing).
- `cargo check --workspace` on macOS stays green: everything X11 is behind
  `#[cfg(target_os = "linux")]`, and the Linux-only crates are target dependencies.

## Design

| Trait call | X11 |
|---|---|
| `windows` | `_NET_CLIENT_LIST_STACKING` reversed (front to back; else `_NET_CLIENT_LIST`, else the root's children). Kept: viewable (mapped, this desktop, not minimized), `_NET_WM_WINDOW_TYPE` normal/dialog/utility or none, not `_NET_WM_STATE_HIDDEN`, larger than 100×100 (as the Mac), not this process's (`_NET_WM_PID`). Title `_NET_WM_NAME`, else `WM_NAME`. The client window (never the WM frame): its size, its picture without decorations. |
| app id / name | The desktop entry that claims the window's WM_CLASS (StartupWMClass, then a file named after the class or instance, then one whose program is) gives `app_id` = its desktop file ID ("debian-xterm", "org.xfce.mousepad") and the name; else `app_id` = the WM_CLASS class and the name the process's (`/proc/PID/comm` from `_NET_WM_PID`). So a launched app's window has the app's id (the core picks it by that). |
| `apps` | Desktop entries in `$XDG_DATA_HOME/applications` and each `$XDG_DATA_DIRS/applications` (first wins per id), Type=Application; NoDisplay, Hidden, OnlyShowIn/NotShowIn against `$XDG_CURRENT_DESKTOP` and a missing TryExec hide one. Re-read every 30 s at most. |
| `launch` | The entry's Exec, parsed per the spec (quoting, field codes dropped, %i %c %k %%), in a terminal for Terminal=true, `setsid`, stdio to /dev/null, reaped by a thread. |
| `icon` | The entry's Icon: a path, or a name in the icon themes (hicolor first, then any theme, then pixmaps; PNG only: no SVG renderer is linked), else the window's `_NET_WM_ICON`; scaled to 128 px PNG; cached per id. |
| `thumbnail` | The window's own pixmap (below), fitted in 208×132 at JPEG quality 60, as the Mac. The window is redirected once on the platform's connection and stays so (unredirecting makes the app repaint). |
| `start_stream` | A thread with its own X connection reads the source at `fps`: the Desktop is the primary RandR output's rectangle of the root; a window is redirected with Composite (automatic mode: nothing changes on screen) and read from `NameWindowPixmap`, named again before every read (a resize or remap gives it a new pixmap), so a covered window still streams. Reads go through MIT-SHM (`ShmGetImage` into a SysV segment, ~1.5 ms for 1920×1080 in Docker), else plain `GetImage`. An unchanged picture (memcmp) is not encoded; a keyframe request re-sends the last one. Sizes cropped to even; `scale` < 1 is a box-filter downscale here (the core's encoder takes the encoded size). A closed window ends the stream ("The window closed."); a minimized one just sends nothing. |
| encoder | The core's `FfmpegEncoder` (BGRA in, NUT out, one frame in flight), `hevc_vaapi` or `hevc_nvenc` when a one-frame test encode works, else `libx265` (`--encoder=` or `SILL_ENCODER` to force; `SILL_VAAPI_DEVICE` for the render node). |
| cursor | XFixes `SelectCursorInput` on the stream's connection; on each CursorNotify `GetCursorImage` (premultiplied ARGB) → straight RGBA PNG + hotspot, deduplicated by serial. GetImage never includes the cursor, so the device draws this one. |
| `inject` | XTest `FakeInput`: motion absolute on the root; buttons 1 and 3; scrolling as wheel buttons 4/5/6/7, pixel deltas adding up to one click per 48 px (a gesture's end drops the rest); keys by evdev code + 8 (checked at start: if the server's keymap is not evdev's, keys are found by their US keysym instead); chords press their modifiers around the key and release them after (⌘ and ⌃ → Control, ⌥ → Left Alt, never AltGr, ⇧ → Shift); text by keysym from the keymap (level 1, or 2 with Shift), else through up to 8 spare keycodes remapped for the run and given back after (xdotool's way; `é € ж` work on a US keymap). |
| `raise` | `_NET_ACTIVE_WINDOW` (source 2, a pager), after mapping it again if it is iconic; without an EWMH WM a raise and the input focus. |
| `resize` | Un-maximize, then `_NET_MOVERESIZE_WINDOW` with only the size (top-left kept), else a ConfigureWindow; waits up to 0.5 s for the size to settle and returns it. Points × (Xft.dpi / 96) on a HiDPI desktop. |
| `window_command` | Close: `_NET_CLOSE_WINDOW` (else `WM_DELETE_WINDOW`), never a kill. Minimize: `WM_CHANGE_STATE` IconicState. Full screen: `_NET_WM_STATE` toggle of `_NET_WM_STATE_FULLSCREEN`. Every EWMH request ends with a round trip (a request whose sender exits right away was sometimes lost). |
| `pointer_location` | `QueryPointer` on the root (no lock shared with input). |
| `advertise` | Avahi over D-Bus (zbus, blocking): `EntryGroupNew`, `AddService(-1, -1, 0, name, "_sill._tcp", "", "", port, TXT)`, `Commit`; a collision retries as "name (2)"…; the guard `Free`s the group. Fallback: an `avahi-publish -s` subprocess killed with the guard. |
| `machine_name` | `/etc/machine-info` PRETTY_HOSTNAME, else the hostname. |
| `release_all_input` | Every key and button this host pressed goes up. |

Crates (all MIT or Apache-2.0, Linux-only target dependencies): x11rb 0.13 (pure Rust; shm,
composite, xfixes, xtest, randr), libc, image 0.25 (png, jpeg), zbus 5 (blocking). FFmpeg runs as a
subprocess only.

Files: `src/keymap.rs` (HID → evdev/keysym), `keys.rs` (key state), `text.rs` (characters →
keysyms, spare keycode plan), `scroll.rs`, `scale.rs`, `desktop.rs` (pure); `src/linux/` `x.rs`
(connection, atoms, properties), `windows.rs`, `capture.rs`, `stream.rs`, `cursor.rs`, `input.rs`,
`icons.rs`, `encoder.rs`, `avahi.rs`, `selftest.rs`, `mod.rs` (`LinuxPlatform`). Docker:
`Dockerfile`, `Dockerfile.dockerignore`, `docker/entry.sh`. Tests: `tests/inputclient.py`,
`tests/e2e-input.sh`.

## Running on a real Linux desktop

Needs an X11 session (Xorg; on a Wayland session only XWayland apps are visible, see below),
Rust 1.92, FFmpeg with an HEVC encoder, and for advertising avahi-daemon.

```
sudo apt install ffmpeg avahi-daemon            # Debian/Ubuntu; Fedora: ffmpeg from RPM Fusion
cd hosts && cargo build --release -p sill-host-linux
./target/release/sill-host-linux --list         # the windows and apps a device would see
./target/release/sill-host-linux                # the host; devices on this network find it by Bonjour
```

- Hardware encoding: Intel/AMD need the VAAPI driver (`intel-media-va-driver` or `mesa-va-drivers`)
  and access to `/dev/dri/renderD128` (the `render` group); `vainfo` should list HEVC encode.
  NVIDIA needs the proprietary driver and an FFmpeg built with NVENC. Without either, libx265 runs
  on the CPU (fine for a window; heavy for a 4K desktop: try `--standard` or a lower `--max-fps`).
  The host prints "Encoder: hevc_vaapi through ffmpeg." (or which one it took).
- The plain door admits only this machine's own networks (the core's rule) and the apps' Release
  builds need `--pairing` (milestone B, not built yet): use the apps' Debug builds for now.
- Never run `--selftest` on a desktop someone uses: it moves the pointer, types, and opens and
  closes windows.

## Docker test

Build context is `hosts/` (the workspace); publish ports to 127.0.0.1 only.

```
cd hosts
docker build -f sill-host-linux/Dockerfile -t sill-linux-test .
docker run --rm --name sill-linux-selftest -v "$PWD/selftest-out:/out" sill-linux-test     # the self-test
docker run -d --rm --name sill-linux-host -p 127.0.0.1:47123:47123 sill-linux-test host --port=47123
#   wait for "Home door: plain TCP on port 47123" in `docker logs sill-linux-host` (~5 s: the
#   entry script waits for the apps' windows first), then from the Mac:
python3 ../Scripts/sillclient.py 47123 8 desktop --stats
"../.build/viewer-dd/Build/Products/Debug/Sill Viewer.app/Contents/MacOS/Sill Viewer" \
    -ApplePersistenceIgnoreState YES -SillOpenAddresses 127.0.0.1:47123
sill-host-linux/tests/e2e-input.sh sill-linux-host 47123    # input through the door, checked by xev
docker rm -f sill-linux-host
```

`docker run -it … sill-linux-test shell` gives a shell on the container's desktop (DISPLAY=:99);
`SILL_SCREEN=2560x1440x24` changes the screen. The image is Debian 13 (FFmpeg 7.1.5 with libx265,
openbox, Avahi and D-Bus started by `docker/entry.sh`). Docker Desktop's published port arrives
from 172.17.0.1, which the plain door admits (the container's own subnet).

## Results (2026-10-14, Docker Desktop on this Mac, arm64, libx265)

- Self-test: 32 of 32 (three runs in a row, and again on the final build). Highlights: windows with app ids from desktop entries
  (`debian-xterm`, `org.xfce.mousepad`) and from WM_CLASS (`XEyes`); MIT-SHM reads of 1920×1080 in
  1.5 ms and of a 640×480 window in 0.3–0.9 ms; a red xterm covered by Mousepad: 99 % red in its
  capture, 2 % on the screen there; the stream loop sends 1–4 pictures in a still second and 30
  while the pointer moves, one keyframe per request, the cursor's shapes; the core's encoder via
  this backend: one keyframe at the start and one per request (1280×720 at half scale 640×360,
  544×394 at 30 and 60 fps, a captured busy xterm); 4 s of the desktop to an HEVC file that ffprobe
  reads back frame for frame (hevc 1920×1080, 104 frames, 113 P after 1 I); xev saw the click,
  right click, wheel (120 px = 2 clicks each way), keys in exact order (a, ⇧a, ⌘C as Control+c, ⌥x
  as Alt+x, Up, F5, ⌘ held around V, nothing left down) and text "Hi é€ж⏎" (é € ж through spare
  keycodes); typing `echo Sill-Ä€ > file` into a shell in an xterm wrote the file; resize 520×410
  exact, 10×10 → 78×78 (xev's minimum); full screen 1920×1080; minimize, raise back, close; launch
  of the XTerm entry opened a window listed with app id `debian-xterm`; the Avahi advertisement was
  seen by `avahi-browse` with port and TXT and gone after the guard dropped.
- End to end through the core (`sill-host-linux host --port=47123` in the container):
  sillclient gets the catalog (4–5 windows, thumbnails, the Mousepad icon, 4 apps), the cursor
  and HEVC frames; a busy xterm window streamed at 58.8 fps with keyframes only at 0.14 s and the
  4 s safety interval, 1.9 ms frame age; the whole 1920×1080 desktop at 120 fps asked: ~32 fps (x265
  on the container's CPU is the limit; the mailbox drops frames rather than queue them).
- Mac viewer (Debug build, `-SillOpenAddresses 127.0.0.1:47123`): shows the container's desktop
  sharp at 33 fps with 1–3 ms frame age and 1 ms RTT, the window list with thumbnails, the
  Mousepad icon, the app list and the X cursor drawn by the device (`screencapture -l` of the
  viewer's own window only).
- `tests/e2e-input.sh`: 15 of 15 (pointer at exactly the fraction of the picked window — checked
  against `xwininfo`; `xdotool getwindowgeometry` is off by the frame under openbox — clicks,
  wheel, keys, chords, text with spare keycodes).
- `--standard`: "Streaming the whole desktop at half scale … Encoding 960×540". A streamed xterm
  closed mid-stream: frames stop, "Stream ended: The window closed.", the host goes on.
- Last full pass (the image built from `hosts/` as documented, against the core at the time):
  self-test 32/32, sillclient streaming with one keyframe, e2e input 15/15; `cargo clippy -p
  sill-host-linux --all-targets` clean and `cargo test -p sill-host-linux` 22/22 on Linux (in
  `rust:1.92-trixie`); `cargo check --workspace` green on macOS.

## Untested

- A real Xorg desktop (GNOME/KDE/Xfce on Xorg), multi-monitor setups (the Desktop is the primary
  output only), HiDPI (Xft.dpi scaling of `resize` is written, not run), XWayland.
- hevc_vaapi and hevc_nvenc (no such hardware here; the core's command lines are written but
  untested too).
- Avahi on a real network (only inside the container's bridge), and the apps finding the host by
  Bonjour (the Mac viewer was given the address).
- Compositing window managers (Mutter, KWin, picom with xfwm4): redirecting a client window while a
  compositor redirects the root's children is allowed by Composite, but not tried.
- The Mac viewer's own input (picks, typing) into the container: input was driven by
  `tests/inputclient.py` instead (no UI automation of the viewer here).

## Wayland plan (not built)

A Wayland session gives no global window list, capture or input injection to clients; the portals
do, with the user's consent:
- Capture: `org.freedesktop.portal.ScreenCast` (CreateSession, SelectSources with
  `types` = MONITOR | WINDOW, `cursor_mode` = METADATA so the cursor comes as PipeWire metadata, and
  `persist_mode` = 2 with the restore token kept in the config directory so the consent dialog shows
  once), Start → a PipeWire node; read it with the `pipewire` crate (MIT) as DMA-BUF or SHM BGRx
  frames (DMA-BUF straight into VAAPI later) into the same encoder path.
- Input: `org.freedesktop.portal.RemoteDesktop` on the same session (devices KEYBOARD | POINTER):
  NotifyPointerMotionAbsolute on the stream's node, NotifyPointerButton (BTN_LEFT 0x110,
  BTN_RIGHT 0x111), NotifyPointerAxis (pixel scrolling, no wheel emulation needed) and
  NotifyKeyboardKeycode with the same evdev codes as `keymap.rs`; text by keysym
  (NotifyKeyboardKeysym). libei (via the portal's ConnectToEIS) is the newer route.
- Windows: no portal lists windows. The picker is the portal's own dialog (one window per
  session), so the device's window list would be "the window shared" plus the Desktop; KDE and
  GNOME have private D-Bus APIs (KWin scripting, GNOME Shell's introspection, which is restricted)
  that could list windows later. Raise/resize/close have no portal either.
- All of it over zbus (already a dependency). Detect with `$WAYLAND_DISPLAY` / `$XDG_SESSION_TYPE`;
  until then the host on a Wayland session sees XWayland windows only and its Desktop capture is
  black (XWayland's root is not the compositor's screen).

## Requests to core

1. **Every frame came out a keyframe** when a keyframe was asked for before the encoder's first
   frame (fixed on my side by never asking on a new encoder's first frame, `stream.rs`). Cause: the
   writer gives a requested keyframe an odd timestamp; on the first frame that makes the input's
   start time odd, FFmpeg's CLI shifts every timestamp by the start time, so every later (even)
   timestamp turns odd and `-force_key_frames expr:…` fires on all of them. Seen with Debian 13's
   FFmpeg 7.1.5 + libx265: 232 of 232 frames IDR at 15 Mbps (all the bitrate on IDRs, a soft
   picture); the self-test's "core encoder, a captured xterm" check reproduced it before the
   workaround. The core can hit it too (a device connecting while a stream starts makes the
   coordinator call `request_keyframe` before the first frame): suggestion, never mark the first
   frame (it is IDR anyway), or `-copyts`.
2. X window ids are reused: a new client can get the id range of one that just exited, so a new
   window can have the id of a window that closed a moment ago (seen in the self-test). If the
   catalog caches thumbnails, icons or app ids by window id, invalidate an id when it leaves the
   list (the window list's title/app change will also differ).
3. `resize` returns the size in the same logical points it was given (Linux: pixels ÷ Xft.dpi/96,
   1:1 on a normal-DPI desktop). Please confirm that is what the core expects back.
