# ReelRenderer

The renderer of Sill's sizzle reel. It draws every frame of the film in code (devices, type, the app icon, the
sill line, the glow, a drawn pointer and touch dots) around clips and stills of the real app, writes a 1080p60
H.264 MP4 with Apple's software encoder, synthesises the score, and checks what it delivers. Apple frameworks
only: SwiftUI's `ImageRenderer`, Core Graphics, Core Image, AVFoundation and AVAudioEngine. No ffmpeg, no
Homebrew, no downloaded music or artwork.

Its last render is v3.1 (2026-09-27): `design/reel/v3/Sill-sizzle-v3.1.mp4`, 83.2 s, 35 shots on a 150 BPM grid.
`design/reel/` is not in git; its shot lists are the reel's design documents (below).

## Where it came from

The renderer was built in September 2026 by agent workflows in a scratch folder (v1 on 2026-09-24, then v2, v3
and v3.1), and that folder was later wiped. On 2026-10-29 it was rebuilt from the tool calls that wrote it, which
the sessions' transcripts keep, replayed in order: every `Write` and `Edit`, and every `Bash` heredoc, `sed`,
`perl`, copy and Python edit script. The result is v3.1 byte for byte: its Swift sources have the checksum the
transcript recorded for them right after the delivery render (`md5 -q Sources/ReelRenderer/*.swift | md5` =
`bf9fc2b0546adf8c84832cbfcfb3b9c2` before the three changes below), it builds unchanged, and frames it renders
match the delivered film's to within the encoder's noise (PSNR 51–53 dB). The record of the recovery, file by
file, is kept outside the repository with the rest of the reel's working files.

This copy differs from the recovered v3.1 in three places:
- `Clip.swift`: `reelDir`, the folder the inputs are read from, is `REEL_DIR` when set, else `work/` beside
  `Package.swift`. v3.1 named the scratch folder.
- `Timeline.swift`: one comment no longer lists the names of the files a privacy blur covered in a clip.
- `Package.swift`: its comment says where the package lives now.

## Build and run

```
cd Tools/ReelRenderer
swift build -c release                     # about 30 s; one deprecation warning (CIColorKernel)
swift Scripts/placeholders.swift work      # stand-in inputs, so any shot renders (below)
.build/release/ReelRenderer stills /tmp/reel 1.0 75.2 80.5     # PNG frames at reel times
.build/release/ReelRenderer render --from 78.4 --to 82.0 --out /tmp/reel/duo.mp4
swift Scripts/check.swift info /tmp/reel/duo.mp4                 # duration, size, rate, frames
```

The commands (`main.swift` has them all):

| Command | What it does |
|---|---|
| `render [--out f.mp4] [--from s] [--to s] [--frames dir --every n] [--no-video]` | the silent film, or a part of it; prints each clip's reads |
| `stills <dir> <t>…` | full frames at reel times, as PNG, with the film's grain and dither |
| `score <out.m4a> [--wav out.wav]` | the score, synthesised (two passes, normalised) |
| `mux <silent.mp4> <score.wav> <out.mp4>` | the film with its score |
| `finalize [--cover p.png [--poster-out p.jpg]] <movie>…` | no video edit list, cover art, `moov` first |
| `verify <movie> [<silent>]` | format, colour, frame timing, edit lists, audio levels and the silence, the true-black frame and the hero frame |
| `sheet <movie> <out.png>` | the contact sheet, one tile per shot |
| `icon-check <reference.png> <out.png>` | the drawn icon against a render of `design/AppIcon.svg` |

`Scripts/pipeline.sh` runs the delivery steps v3.1 ran (score, render, mux, the poster still at 75.2 s, finalize,
verify, sheet) into `work/v31/out/`, under `taskpolicy -c utility`. A whole render takes about 4 minutes on an
M2 Pro (20.9 fps for 4,992 frames).

### Inputs

Everything the film shows that is not drawn is read from `reelDir`. The renderer loads the stills when it
starts, and each clip when a shot first reads it:

| Path under `reelDir` | What it is | Shots |
|---|---|---|
| `real-captures/01-connect-desktop.mov`, `02-drawer-launch.mov`, `04-pick-vscode.mov`, `05-pick-blender.mov`, `08-settings-panel.mov` | R01, R02, R04, R05, R08: the client streaming real Mac apps | S06–S14, S21, S23 |
| `real-captures/11-window-to-desktop.mov`, `12-aa-resize-weather.mov`, `13-trackpad-pointer.mov` | N1, N2, N3 | S13, S16, S18 |
| `capture/final-aa.mov`, `capture/final-lights.mov` | HT-B, HT-D: the layout harness with mock data | S15, S19 |
| `capture/final-portrait.png` | HT-C, the portrait layout | S17 |
| `v3/shots/c0…c4.png`, `p-addmac.png`, `p-paired.png`, `s-remote.png` | harness screenshots of the connect screen, Add a Mac and the Settings panel | S24–S27 |
| `v3/mac-previews/pairing-waiting-dark.png`, `pairing-paired-dark.png` | the Mac's pairing window (`SillMenuBar -SillRenderPreviews`) | S26 |
| `v31/s18/arrow-56x80.png`, `plate-band.png`, `recorded-arrow-subpx.csv`; `v3tools/pointer-path.txt` | S18's drawn pointer: AppKit's arrow, clip 13's row without its arrow, and the finger's path | S18 |

Every recording is the iPad Pro 13" simulator's whole portrait screen, 2064×2752 px, as `xcrun simctl io
recordVideo` writes it. The landscape layout's interior is the rectangle at x 32, y 666, 2000×1420 px; the
portrait one's at x 322, y 376, 1420×2000. A clip may only be read inside the segments `ClipID.approved` lists.
`work/` is ignored by git: real footage and stills never go in the repository.

`Scripts/placeholders.swift <dir> [--clips all|none|r01,n3,…] [--fps 4]` writes a stand-in for every input:
test-pattern stills and clips of the same sizes, with the clip and clip time burned in, covering each clip's
approved segments. With them every shot renders, so a new cut's timing can be watched before any footage exists.

The Mac's previews (S26's pairing window) come from the bare `SillMenuBar` binary, never from a built `Sill.app` or
the executable inside it: macOS registers such a copy in place of the installed app, and its permissions and login
item go with it. The bare binary records the deployment target as its SDK, so it draws the look of macOS before 26;
v3's previews came from a copy with the current SDK recorded:

```
swift build -c release                                        # at the repository's root
xcrun vtool -set-build-version macos 14.0 "$(xcrun --sdk macosx --show-sdk-version)" \
    -output /tmp/SillMenuBar .build/release/SillMenuBar && codesign -s - -f /tmp/SillMenuBar
/tmp/SillMenuBar -SillRenderPreviews /tmp/previews            # no permission needed; defaults domain SillMenuBar
```

## How the v3.1 reel was made

The shot list came first: `design/reel/SHOTLIST.md` (v1), `v2/SHOTLIST-v2.md` (Noah's notes applied) and
`v3/SHOTLIST-v3.md` (the remote beats, then v3.1's smooth pointer in its §11). Each version of the renderer
implements its shot list; the code names the shot list's sections in its comments.

- `Timeline.swift` is the timeline table in code: one `Shot(id:start:end:source:clip:build:)` per row, the reel
  in four acts on bar lines (0, 9.6, 28.8, 65.6 s), every cut on a beat (0.4 s), and the clips' in-points set so
  each recorded event lands on its beat (`Events`).
- `ShotsI.swift` (Acts I and IV: the icon, the type, the lockup), `ShotsII.swift` (Acts II and III: the clips in
  drawn devices and macros), `V3.swift` (the remote beats, S24–S27), `Duo.swift` (the iPhone Duo card) and
  `V31.swift` (S18's pointer) hold one builder per shot: a function of the reel time that returns the frame's
  layers.
- `Look.swift` has the canvas (1920×1080, 60 fps, 4,992 frames), the palette, the easings, the type styles and
  every line of copy. `TypeViews.swift` snaps words in on their beat; `Device.swift` draws the devices, touch
  dots, the glow and the sill line; `Icon.swift` draws the app icon from `design/AppIcon.svg`'s shapes;
  `Stacks.swift` places devices in 3D; `Pending.swift` is v2's placeholder card for shots waiting on a capture.
- `Render.swift` composes each frame (SwiftUI into IOSurface buffers, then Core Image for the rack focus, the dim,
  the grain, the vignette and the dither, all seeded, so a frame renders the same every time) and writes the
  H.264. `Clip.swift` reads the clips (the latest sample at or before each frame, never retimed), crops them and
  applies the privacy treatments. `Score.swift` synthesises the score from the cue sheet (`Cues`), timed to the
  picture's events. `Deliver.swift` muxes, finalises, verifies and makes the contact sheet.

Then: `pipeline.sh`, `verify`, the contact sheet, a frame review of the MP4 (copy, privacy, motion, blacks), and
the shot list's as-built section with every number.

## The shot list

A shot list (`design/reel/v3/SHOTLIST-v3.md` is the model) has:
- the request and how the cut answers it (§0), and the global spec: canvas, codec, audio, the grid, the sources
  (§1);
- the timeline (§2): one row per shot, `# | Reel (s) | Frames | Bar | On screen | Source | Copy`, the acts in
  bars, and how the shots map from the previous version;
- each new or changed shot in detail (§3): its timing, camera, device, type with baselines and snap times, sources
  and audio;
- the copy deck with what backs every claim (§4): each line traced to the README or the code, with its caveat;
- honesty and privacy (§5): where each picture comes from, and what is blurred or cleared;
- the audio (§6): the harmony and the cue sheet;
- the contact sheet (§7), what was built and checked (§8), the decisions and deviations, each with a one-line
  undo (§9), and the frame review (§10).

## The rules every cut keeps

- **Plain bezels.** No camera, lens, notch or sensor on any drawn device, the app icon's iPad included (Noah,
  2026-09-26). The devices are drawn, never Apple's artwork.
- **The pointer is drawn.** A cursor or pointer in motion is drawn by the renderer on an eased path at
  sub-pixel positions, never taken from a recording (v3.1, after a recorded one stuttered: a simulator
  recording writes a sample only when the screen changes, with holes and jitter). Its motion must be even at
  60 fps: no repeated or skipped positions.
- **The software encoder while Sill streams.** Sill.app shares the Mac's one hardware video encoder, and a
  render or a simulator recording on it costs Sill frames, or stalls it. The renderer uses Apple's software
  H.264 encoder unless `SILL_HW_ENCODER` is set, to any value, `0` and an empty one included (`pipeline.sh`
  refuses it), renders run at utility priority, and nothing encodes the simulator's screen while Sill.app is
  streaming: no `simctl io recordVideo`, no UI test run (Xcode records its screen) and no live view of the
  simulator left attached. A screenshot (`simctl io screenshot`) encodes no video.
- **No downloaded music.** The score is synthesised in code; no samples, no stock tracks.
- **Every claim is backed** by the README or the code, in the shot list's copy deck. Real footage shows the real
  app; mock data appears only in harness stills, which the shot list says.
- **Privacy.** Anything personal in a clip (names, files, places, faces, messages) is blurred or cleared with
  the person whose screen it is, and the shot list records each treatment.

## Adding a beat for a new feature

1. **Write it in the shot list.** Where it goes on the grid (a beat is 0.4 s, a bar 1.6 s; cuts on beats, acts
   on bar lines), what is on screen, its source, its copy and what backs the copy.
2. **Get its pictures.** A still (a harness screenshot of the client, or a Mac preview, made as in Inputs) or a
   clip (a recording of the client). Put it under `work/`, and name it:
   a case of `ClipID` with its file and approved segments (`Clip.swift`), or a still beside `V3Still` and
   `MacPreview` (`V3.swift`), loaded in `makeEnv` (`main.swift`). Add it to `Scripts/placeholders.swift`.
3. **Write its builder:** `@MainActor func sNN(_ t: Double, _ e: Env) throws -> FrameLayers`, from
   `deviceShot` (a whole device), `macroShot` (a crop of one), `TypeLayer` with `LineSpec`s (copy that snaps on
   a beat), `Backdrop`, `rackState` or `dimState`. New copy goes in `Copy` (`Look.swift`).
4. **Put it in the timeline:** a `Shot` in `Timeline.shots`. Later shots move by whole bars, keeping their
   builders and handed the time they had (as v3 did for Act IV with `ActIV.shift`).
5. **Lengthen the film:** `Stage.frames` and `Stage.duration` (`Look.swift`); the score's `END`, its stops and
   its cues (`Score.swift`); the sheet's tiles and title and `verify`'s silence window and true-black frame
   (`Deliver.swift`).
6. **Check it:** `stills` at its key times, a short `render --from --to`, then `pipeline.sh` and a frame review.

## What it needs from a person

- **Real clips.** Recordings of the client streaming real apps from a real Mac, with the apps chosen and their
  contents cleared for privacy by the person whose Mac it is. An agent cannot make them: they need the person's
  Mac and its permissions, and a time when Sill.app is not streaming.
- **Approval** of the shot list's copy, the privacy treatments and the cut.

## Not part of the app

`Tools/ReelRenderer` is a Swift package of its own. The root `Package.swift` names its targets' folders under
`Sources/`, so `swift build` in the repository, Xcode's iOS project and every workflow leave this one alone. CI's
`paths-ignore` lists `Tools/ReelRenderer/**` too, so a change here alone starts no CI run. Its `.build/` and
`work/` are ignored by git.

The license is the repository's, Apache-2.0.
