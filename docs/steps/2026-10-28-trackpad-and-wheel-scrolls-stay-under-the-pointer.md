**Trackpad and wheel scrolls stay under the pointer (2026-10-28, PR #217 from andrewgribben's
`trackpad-scroll`, maintainer edits on it, main at 6c5b5d24 merged in; issue #130; the findings in
docs/hardware-keyboard-plan.md, "#130 and PR #217").** #217 read each scroll pan's reading as that event's
own movement on a Magic Keyboard, so that main's diff of a running total (#80) "sent almost nothing", and
added three stats keys. Checked on a private iPad simulator (iOS 27.0) with keyrig, a probe app of pans
side by side and Sill's own build against a loopback synthetic host with `SILL_TEST_INPUT_LOG=1`: the
translation is a running total, as a finger's (a wheel's notches 3, 6, 9 pt), and main's build and #217's
posted the same wheel scroll event for event. The issue's reports were of 0.5.1, whose finger pan had no
scroll mask (a pan's default is 0, read there): no trackpad scroll reached it at all. Device only but for
a TEST ONLY log line; no wire change.
- What was wrong: UIKit moves a scroll pan's location on by its translation while the pointer stays put
  (the pointer at y 308.8, the pan at 311.8, 314.8, 317.8), and InputOverlayView posted the scroll, its
  end and its coast at that location: on the host ten notches walked from y 447 to 497 of the test
  pattern's 949 and a phased scroll from 459 to 636, so the Mac scrolled the window under the pointer at
  first, then whatever the point reached. `PointerScroll` (pure, in HardwareKeyboardPolicy.swift): every
  event of a trackpad's or a wheel's scroll goes where the pointer was as it began, the pan's first
  location less its first reading (on the host at y 442 throughout, the amounts unchanged). A finger's
  pan is as it was.
- Kept from #217: each reading taken and the pan's translation zeroed (the movement since the last event
  whether UIKit adds them up or not); `PointerScroll.total` adds the readings up for the scroll path's
  diff, so the shared path, the DEBUG input script and `scriptScroll` are main's. Gone:
  `minimumNumberOfTouches = 0` (the trackpad's pan began without it through Universal Control on
  2026-10-15), `in.scrollMiss` (could not count for a Sill device: both ends hold a scroll inside the
  picture), `in.scroll0` (every coast's sub-point tail), `in.scrollY` (a sum among counts, for amounts that
  were never lost) and `Stats.add`.
- TEST ONLY: the input log's scroll line says where it lands ("Test input: scroll dy 6 dx 0, wheel (none)
  at 833,442"). DEBUG: one `scroll:` console line a pointer scroll: how far, where, and how far UIKit's own
  location for the pan had run from there ("scroll: wheel ended by 0.0,102.7 pt at 450.8,268.8; the pan's
  own location ended 0.0,102.7 pt from it").
- Verified: `hardware-keyboard` 62 checks (11 new) and 37 of 37 mutants (6 new); the touch rig 72 of 72
  against main; `run-all.sh`, all 55; `swift build -c release`, only the CaptureProbe warning; the
  iOS app Debug and Release for the simulator and Debug for a device, only the known `StreamClient`
  capture warning. Not seen: a real trackpad's events in the continuous pan (none reached it in the
  simulator: keyrig's mouse and its phased events go to the discrete pan, and a virtual touch pad's
  digitizer frames came as touch events).
- **Untested, for Noah** (the iPad with the Magic Keyboard, a Debug build from the branch): two fingers on
  the trackpad scroll a window and the Desktop the whole way, under the pointer (a long scroll down and up
  in Safari and in Finder's list); a flick coasts once (note a double coast: the content running on twice
  as far, or a second stretch after the first ends); a mouse's wheel, one notch and a spin; the console's
  `scroll:` lines say whether the pan's own location runs on there too.
