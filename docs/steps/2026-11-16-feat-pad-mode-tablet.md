**Pad Mode: screenless drawing tablet surface with Mac display mapping, touch gestures, and landing overlay (2026-11-16, branch `feat-pad-mode-tablet` from `feat-pencil-tablet-input`).**

- **What:** Adds a screenless drawing tablet mode ("Tablet" / Pad Mode) turning iPad into an external graphics tablet for Mac:
  1. `PadCanvasView.swift`: Aspect-fitted active region matching the Mac's main display dimensions. Accepts Apple Pencil exclusively for drawing/cursor input while mapping single-finger sliding to Mac page scrolling and two-finger pinch to canvas zoom (⌘+ / ⌘-).
  2. `PenLandingOverlay`: A lightweight non-activating floating overlay on macOS showing the artist where their Pencil tip hovers or lands on the Mac screen before touching down. Throttled per batch to prevent AppKit animation thrashing.
  3. Video capture is paused (`select(.none)`) while in Pad Mode to save battery and network bandwidth, returning smoothly to the previous window or desktop upon exiting.
- **The decisions:**
  - `PenTarget.display` routes coordinates directly across the Mac's entire desktop rather than individual window frames.
  - Palm and finger direct touches are strictly filtered from stylus input, avoiding accidental brush marks.
  - Single-finger pan routes to `.scroll` / `.scrollGesture` with momentum coasting, and two-finger pinch routes to discrete zoom keystrokes.
- **Verified:**
  - `Tests/checks/pen`: 48 of 48 checks pass.
  - `Tests/checks/repo-rules`: 10 of 10 pass.
  - `swift build -c release`: clean build.
