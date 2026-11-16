**Apple Pencil tablet input with hardware timestamp synchronization, pressure mapping, and 1€ filter jitter rejection (2026-11-16, branch `feat-pencil-tablet-input` from main at v0.6.2).**

- **The problem:** Apple Pencil handwriting over streamed Mac windows exhibited wavy ripple jitter and periodic beaded stroke blobs ("candies on a string"). Investigation revealed two separate root causes:
  1. Low-frequency capacitive digitizer ripple (~8–12 Hz) when moving slowly across the iPad display.
  2. Burst packet arrival over Wi-Fi. When the host synthesized `CGEvent` timestamps from packet arrival time, coalesced Pencil samples received identical or bunched host timestamps, creating artificial velocity spikes and pressure drops that drawing apps interpreted as periodic ink blobs.
- **The protocol (kind 45, `PenBatch`):**
  - Added device-side hardware timestamp `t: Double?` (`UITouch.timestamp`) to `PenSample`.
  - Added `PenCapability` carried in `WindowList.pen` so client knows host accepts kind 45.
- **Host timestamp synchronization (`PenInjector.swift`):**
  - Locks a clock offset (`strokeClockOffsetNs`) between the iPad hardware monotonic timestamp and the Mac host's monotonic clock (`CLOCK_UPTIME_RAW`) at stroke initiation (`PenPhase.down`).
  - Preserves exact ~4.167 ms intervals (240 Hz Pencil digitizer rate) across network jitter, preventing velocity spikes.
  - Generates standard Quartz `CGEvent` mouse drag events with `mouseEventSubtype = 1` (`kCFNumberTabletPointEventType`) along with companion `.tabletPointer` / `.tabletProximity` events carrying pressure and tilt (altitude/azimuth).
- **Adaptive 1€ filter (`PenFilter`):**
  - Casiez et al. (CHI 2012) dual-cutoff adaptive filter: low cutoff at low speed to eliminate capacitive jitter, transitioning smoothly to high cutoff at high speed.
  - Dynamically computes sampling rate from hardware timestamps.
  - Fast stroke tracking lag stays under 20 ms while 10 Hz ripple is suppressed by over 80%.
- **UIKit touch force estimation damping:**
  - Damps pressure updates when `touch.estimatedPropertiesExpectingUpdates.contains(.force)` to eliminate frame-boundary pressure step jumps.
- **Verified:**
  - `Tests/checks/pen`: 48 of 48 checks pass (wire round-trip, host filtering, tilt/azimuth mapping, timestamp validation, 1€ filter lag and ripple rejection).
  - `Tests/checks/compatibility`: 166 of 166 pass.
  - `Tests/checks/pointer-control`: 161 of 161 pass.
  - `Tests/checks/display-wake`: 273 of 273 pass.
  - `Tests/checks/repo-rules`: 10 of 10 pass.
  - `swift build -c release`: clean build.
