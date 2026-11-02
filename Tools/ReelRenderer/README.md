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

This copy differs from the recovered v3.1 in three places (and since 2026-11-02 in its type, drawn as glyph outlines on
its exact path, The type below, so frames with type no longer match v3.1's bit for bit):
- `Clip.swift`: `reelDir`, the folder the inputs are read from, is `REEL_DIR` when set, else `work/` beside
  `Package.swift`. v3.1 named the scratch folder.
- `Timeline.swift`: one comment no longer lists the names of the files a privacy blur covered in a clip.
- `Package.swift`: its comment says where the package lives now.

## Proof of reproduction

On 2026-10-29 every clip and still the reel reads was reconstituted from the delivered v3.1 film itself (the
originals are gone) and the whole reel rendered again by `Scripts/pipeline.sh`, unchanged, with the software
encoder: 1,729 of its 4,992 frames decode identically to the delivered film's (every frame of S01–S05, S20 and
S29–S35, and S21's first; the drawn frames of S22 and S28, coded after footage, differ by at most 11 and 3 levels),
the poster and the score are the delivered ones byte for byte and sample for sample, and the footage, solved back out
of the delivered H.264, comes to 44.7 dB, for 50.8 dB mean PSNR over the 3,263 frames that are not identical (49.8 dB
pooled over all 4,992; 36.4 dB at the worst frame). A second check the same day, with tools of its own, recomputed
every frame's numbers and the score and rendered two shots again from this branch: S02 bit for bit, and S10, from its
input rebuilt bit for bit, within 1 dB of the reproduced film on every frame. The method, every shot's numbers, the
check, side-by-side sheets and the reproduced films are on Noah's Mac in
`~/Downloads/sill-handoff/reel/reproduction/REPRODUCTION.md`, kept there like the delivered reel, which shows his own
windows.

## Build and run

```
cd Tools/ReelRenderer
swift build -c release                     # about 30 s; one deprecation warning (CIColorKernel)
swift Scripts/placeholders.swift work      # stand-in inputs, so any shot renders (below)
taskpolicy -c utility .build/release/ReelRenderer stills /tmp/reel 1.0 75.2 80.5     # PNG frames at reel times
taskpolicy -c utility .build/release/ReelRenderer render --from 78.4 --to 82.0 --out /tmp/reel/duo.mp4
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
| `typecheck [--from s] [--to s] [--every n] [--threshold px] [--report f] [--dump f.tsv] [--verbose]` | every glyph of the frames measured against its path (The type); exit 1 if one strays more than 0.1 px |
| `render … --typecheck [n]` | the same check on every n-th frame of a render, which then fails (exit 1) if it fails |
| `typetest [--out f.mp4] [--seconds 3] [--typecheck] [--frames dir] [--no-video]` | two moving lines on the reel's stage, rendered and checked |
| `assets <dir> [prefix …]`, `assets --report`, `assets --motion` | the 0.6.0 drawn assets as PNG stills at their key times (with `index.png`), the cutaway's numbers, its motion check |
| `clearance [--from s] [--to s] [--every n] [--min px]` | how close each line of type comes to what is drawn beside it (a device, a macro), per shot; exit 1 under `--min` (80 px, v2 S23's rule) |
| `derived <dir> <name>…` | 0.6.0's derived stills (`L0w`, `N1x`, `D1x`, `qtv`, …: Reel060.swift, Retouch060.swift) as PNG |

`Scripts/pipeline.sh` runs the delivery steps v3.1 ran (score, render, mux, the poster still at 75.2 s, finalize,
verify, sheet) into `work/v31/out/` (with `REEL=060`, the 0.6.0 video into `work/060/out/`, its poster at 77.2 s),
under `taskpolicy -c utility`, encoding only while no device is connected to Sill.app (the repository's
`Scripts/encoder-check/no-device.sh`: it waits for one to leave, and pauses a running step while one connects), and
since 0.6.0 its render type-checks every frame (The type). A whole v3.1 render takes about 4 minutes on an M2 Pro
(20.9 fps for 4,992 frames), and the check about 7 minutes more (11.9 frames/s); the 0.6.0 film with its check takes
about 650 s (646 s at 7.4 fps for 4,800 frames in its last delivery run).

### Inputs

Everything the film shows that is not drawn is read from `reelDir`. The renderer loads the stills when it
starts, and each clip when a shot first reads it:

| Path under `reelDir` | What it is | Shots |
|---|---|---|
| `real-captures/01-connect-desktop.mov`, `02-drawer-launch.mov`, `04-pick-vscode.mov`, `05-pick-blender.mov`, `08-settings-panel.mov` | R01, R02, R04, R05, R08: the client streaming real Mac apps | S06–S12, S14, S21, S23 |
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
It also writes S18's finger path, `v3tools/pointer-path.txt`, which is no stand-in: the stroke the capture played
while clip 13 was recorded (its own script wrote it), byte for byte the file v3.1 read. S18 does not render
without it.

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

## The type

0.6.0 fixed what Noah called "the floating point issues with the text". v3.1 drew each line as SwiftUI `Text`, which
`ImageRenderer` replays into the frame's 8-bit Core Graphics context, and there every glyph landed on a whole pixel:
under the +1.2 % hold a glyph held still, then jumped a pixel, each glyph on its own frame, so the gaps between letters
flickered. Measured on the delivered `Sill-sizzle-v3.1-silent.mp4` (decoded, with the storyboard's centroid trackers):
"No subscription." (66.35–67.2 s), 42 whole-pixel jumps and 705 held steps of 750, up to 0.99 px off its path; the
legal line after its snap (76.8–78.3 s), 36 jumps, its baseline stepping a whole pixel twice (+1.98 px where the hold
moves it +1.26).

The context's subpixel flags alone (subpixel positioning on, quantisation off; `Render.swift` sets them, for anything
Core Text still draws itself, such as an emoji's bitmap) fixed the 128 px line but not the 24 px one (62 jumps
through its snap, 0.30 px off after it), and SwiftUI's layout still rounds each word's place. So `GlyphText.swift`
draws the type as glyph outlines: Core Text shapes each string once in its style (each run in its own font, so
fallback fonts carry Chinese, Japanese and Korean; a line names its `language` to get that language's fonts, as S13's
greetings should: "ja" sets こんにちは in Hiragino, where untagged kana fall to a Chinese font), and the outlines are filled with anti-aliasing at the exact
positions the motion gives them, in floating point up to the fill. `TypeViews.swift` lays a line out with v3.1's
recipes (the snap, the hold, the ease-out, the haptic jitter), composing by hand every transform v3.1's view tree
applied. A line at rest sits on whole pixels: its left edge or centre, each word's origin and its baseline are rounded
where it lands, and every motion is computed from there, so nothing jumps when it stops. It keeps v3.1's look: each word
takes its Text frame's width (rounded up to a whole pixel, as v3.1's HStack spaced them), and the outlines are grown by
the stem thickening Core Graphics' font smoothing gave v3.1's text (`ShapedText.smoothing`: 0.21 px at 24 px, 0.25 at
28, 0.32 from 34 px up, measured by fitting the outlines to v3.1's own drawing). Against v3.1's drawing at rest the
glyphs sit within ±0.04 px horizontally and 0.2–0.3 px lower (v3.1 rounded the frame's top, not the baseline), with
their ink within 0.4 %. The same passages after the fix, rendered to H.264 and decoded: "No subscription." 0 jumps,
worst 0.05 px; the legal line 0 jumps, its baseline moving +1.26 px exactly (worst 0.02 px).

The rules for a shot's type:
- Draw it only with `TypeLayer`, `TypeLine`, `StaticLine` or `GlyphCanvas` (a tree of `TypeNode`s of `PlacedRun`s for
  anything custom, as `RollingFPS` and S20's title are), never with SwiftUI `Text`.
- Move a type layer with its `transform:` (canvas to canvas: a card's hold, S05's lift) and fade it with `.opacity`;
  never `.offset`, `.scaleEffect`, `.rotationEffect` or a device's tilt around it, so the path recorded is the path drawn.
- Declare where the shot masks or covers its type (`covered:`, as S20's wipe does), and mark text that belongs to a
  picture (`checked: false`), such as words drawn on a device's screen, which move with the picture.
- Every number on screen is a fixed string in `Copy`, never a computed value printed.

### typecheck

`typecheck` renders each frame twice without the finish (the grain, vignette and dither move nothing): with its type,
recording every glyph's outline and transform as it is drawn (`TypeProbe`), and with the type canvases empty. In the
luma difference it measures each glyph: the recorded outline, rasterised where its path puts it, is fitted to it by
Gauss–Newton (Lucas–Kanade), with a gain for the glyph's opacity and the background behind it, a damped slope of that
gain across it, and a shift, all of a line's glyphs together so that touching neighbours share their pixels. A glyph
more than 0.1 px off its path fails the check (exit 1), and `render --typecheck` fails the render. Fitted for their
neighbours' sake but not judged, only counted: glyphs below 25 % of their own opacity or faded below 20 % in the frame
(a parent's opacity, a mask), `covered` or `checked: false`, or whose fit leaves over 8 % unexplained (something
covers them); left out with a fence around them: glyphs blurred more than 0.5 px (a snap's first frames, a rack) and
glyphs at the frame's edge. It also fails a number printed raw (more than two decimals, an exponent, nan, inf,
`Optional(`). Both renders are on compositors of the check's own, never the film's: one that has just drawn the
same frame may have SwiftUI reuse a subtree's drawing without running its canvases (0.6.0's masked fix column), and
the probe then records nothing there. The summary names any shot checked with no glyph measured.

Its own proof: on `typetest`'s two moving lines (a T1 line gliding 0.11 px a frame under the hold; a 44 px line with
Chinese, Japanese and Korean scrolling up 0.62 px a frame), 5,916 glyph measurements, median 0.0008 px, worst
0.0055 px; with every glyph drawn 0.25 px off its path (`REEL_TYPE_OFFSET=0.25,0`) it measured 0.2494 px and failed,
at 0.094 px off it measured 0.0941 and passed, 0.15 px down measured 0.1499 and failed; v3.1's own SwiftUI Text
(`REEL_TYPE_LEGACY=1`) failed, median 0.87 px off, worst 2.4 px. Over the whole v3.1 timeline (every frame, on the
placeholders' stand-in footage): 4,992 frames, 119,297 glyph measurements, median 0.0009 px, 99th percentile
0.0040 px, worst 0.0167 px (the 24 px legal line); not judged, 7,500 blurred, 5,341 faded by a parent or covered, 26
under 25 % of their own opacity and 7 under S20's wipe. The two test switches are never set for a
delivered render (`pipeline.sh` refuses them).

The 0.6.0 assets draw some type of their own (`Assets060Text.swift`'s `Outline060`: the lock screen's clock, the
keycaps), with the same outlines and smoothing but in their own canvases, which the probe does not record: `typecheck`
leaves that type alone (it is in both of its renders), and `assets --motion` checks its motion. The film's cutaway
draws its fix lines with `FixesType060` (`Shots060Mac.swift`) on `GlyphCanvas`, so `typecheck` measures them; the
previews' `FixesColumn060` still draws them itself.

## The 0.6.0 update video (`REEL=060`)

`REEL=060` selects the 0.6.0 update video (80.0 s, 4,800 frames, 23 shots on 50 bars) in place of v3.1, which stays
the default and renders as before (`ReelCut`, `Look.swift`). `Stage`, `Timeline.shots`, the score (`Score060.swift`),
the sheet's tiles and title, `verify`'s silence window (71.40–72.00) and true-black frame (4790), and the movie's
title follow it. Its shot list is `design/reel/v4/SHOTLIST-0.6.0.md`.

| File | What it holds |
|---|---|
| `Reel060.swift` | the inputs (`Footage060`: stills, pictures and the stills derived from them), the copy (`Copy060`), the timeline (`Timeline060`) and the sheet's times |
| `Shots060Open.swift` | S01–S03, the open, and S21–S23, the close |
| `Shots060Clip.swift` | S04–S08: the clipboard both ways, sound, a locked Mac and unlocking it |
| `Shots060Device.swift` | S09–S17: pinch, Larger Picture, a keyboard, scrolling, composition, tiles, Aa, the hold, the tour |
| `Shots060Mac.swift` | S18, Intel, and the cutaway, S19–S20, its type on `GlyphCanvas` |
| `Score060.swift` | the cue sheet and the voices, on v3's engine |
| `Assets060*.swift` | the drawn assets (the bug, the lock screen, the keyboards, the arcs, the iPhone, the iMac) and `assets` |
| `Retouch060.swift` | the stills' retouches (Weather's places, the iPhone's "This iPhone" and Aa "1×") and QuickTime Player's window, drawn |
| `Clearance060.swift` | `clearance`: the words' distance from the devices beside them |

Its inputs under `reelDir` are `stills/`, `pictures/` and `thumbs/`, the footage stand-ins (harness screenshots and
drawn Mac pictures, each made as their own README says), and `v31film/Sill-sizzle-v3.1-silent.mp4`, the delivered
v3.1 film, of which S06's movie (1.6–6.4 s), the picture in QuickTime's thumbnails and S14's tile (5.2 s) and the
Weather frame behind S07–S08 (15.9 s, its saved places retouched: `Retouch060.weather`) are read
(`ClipID.v31film`). Eight scenes stand in for Noah's takes A–F: each builder is marked `SWAP-IN` with the take's path
and the times it must meet, and the shot list's §7 has the steps.

```
cd Tools/ReelRenderer && swift build -c release
REEL=060 REEL_DIR=<inputs> Scripts/pipeline.sh     # encodes only while no device is connected to Sill.app
```

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
- **The type is glyph outlines on its path** (The type): drawn by `GlyphText.swift`, moved only by its layer's
  `transform:`, and checked by `typecheck` (`pipeline.sh` renders with `--typecheck`).
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
   a beat; moved by its `transform:`, The type), `Backdrop`, `rackState` or `dimState`. New copy goes in `Copy`
   (`Look.swift`), numbers as fixed strings.
4. **Put it in the timeline:** a `Shot` in `Timeline.shots`. Later shots move by whole bars, keeping their
   builders and handed the time they had (as v3 did for Act IV with `ActIV.shift`).
5. **Lengthen the film:** `Stage.frames` and `Stage.duration` (`Look.swift`); the score's `END`, its stops and
   its cues (`Score.swift`); the sheet's tiles and title and `verify`'s silence window and true-black frame
   (`Deliver.swift`).
6. **Check it:** `stills` at its key times, `typecheck --from --to` over it, a short `render --from --to`, then
   `pipeline.sh` (which type-checks the render) and a frame review.

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
