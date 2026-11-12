// DesktopDisplays (Sources/StreamProtocol/DesktopDisplays.swift) on its own: the Desktop's stops, which of
// the Mac's displays the Desktop streams when it has more than one, and the Desktop button that steps to the
// next (issue #91, Noah's decision: "the tapping method"; addhumal's PR #173, grown by phase 1 of
// docs/virtual-desktop-plan.md).
//
//   Tests/checks/desktop-displays/run.sh
//
// What it checks: the stops (never Sill's own virtual display nor macOS's stand-in; one per mirror set; left
// to right, then top to bottom, as System Settings › Displays arranges them, whatever order macOS lists them
// in, turned so the main display comes first: every arrangement of up to six displays in a row and in a grid
// with the main one anywhere); the stop the Desktop shows (the main display while locked or off console; the
// one chosen by its UUID while it is connected, so the same display back under a new ID after a sleep is
// still the one; else the main display: #345); the choice's span (kept while a device is connected and 30 s
// after the last left); the next stop (wrapping back to the main display; none with one); its number; after a
// step that did not stream; where input lands during a switch; the rate on a stop; the device's button (its
// label, dots, "3/7", VoiceOver's label, value and hint, and whether a tap steps); where the Mac's pointer goes
// after a step. Then 5,000 random arrangements and 5,000 random sessions against the rule's properties:
//   P1 the stops are the displays not Sill's or the stand-in, one per mirror set, each once;
//   P2 they are the arrangement's order turned to the main display's stop (left to right, top to bottom);
//   P3 stepping `next` from any stop visits every stop once and comes back; from none, the main display;
//   P4 the resolved stop is a stop (none only with no stop); the chosen one unless only the main display may
//      show; the main display's stop otherwise;
//   P5 sessions (devices coming and going, steps, a display unplugged and back, a step that does not stream,
//      locks): the shown stop is always the model's: a session after the span starts on the main display;
//   P6 the button: dots only while the Desktop streams on two to six stops, "n/m" only from seven, the label
//      "Desktop n" exactly when the Mac says two stops or more and which, a tap steps exactly then and while
//      the Desktop streams;
//   P7 the rate never exceeds what the devices ask, nor a stop's reported rate (but for the floor of 24), and
//      is what the devices ask on a stop that reports none.
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passes += 1; print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias D = DesktopDisplays
func display(_ id: UInt32, _ uuid: String, x: Double, y: Double = 0, w: Double = 1512, h: Double = 982, role: D.Role = .screen,
             online: Bool = true, mirrors: UInt32? = nil, hz: Double? = nil, name: String? = nil) -> D.Display {
    D.Display(id: id, uuid: uuid, frame: CGRect(x: x, y: y, width: w, height: h), role: role, online: online,
              mirrors: mirrors, refreshHz: hz, name: name)
}

// A MacBook Pro's built-in screen (main, at the origin) with two monitors above it, the left one listed first
// by macOS under the higher ID (marliechorgan's three displays on #173: "(1)" on the left was ID 4).
let builtIn = display(1, "BUILTIN", x: 0, y: 0, hz: 120, name: "Built-in Retina Display")
let left = display(4, "BENQ-L", x: -3840, y: -2160, w: 3840, h: 2160, hz: 60, name: "BenQ PD2705U")
let right = display(2, "BENQ-R", x: 0, y: -2160, w: 3840, h: 2160, hz: 60, name: "BenQ PD2705U")
let sills = display(54, "SILL-VD", x: 1512, y: 0, w: 1366, h: 1024, role: .stage)
let listed = [builtIn, right, sills, left]

// MARK: The stops

let c = D.candidates(listed, main: 1)
eq(c.map(\.id), [1, 4, 2], "three displays: the main one first, then wrapping to the leftmost; never Sill's own")
eq(D.candidates(listed, main: nil).map(\.id), [4, 2, 1], "the main display not known: the arrangement as it is, left to right")
eq(D.candidates(listed, main: 99).map(\.id), [4, 2, 1], "the main display not listed: the arrangement as it is")
eq(D.candidates([sills], main: 1).map(\.id), [], "Sill's own virtual display alone: no stop")
eq(D.candidates([], main: 1).map(\.id), [], "no display: no stop")
eq(D.candidates([display(7, "A", x: 0, y: 0), display(8, "B", x: 0, y: -1080)], main: 7).map(\.id), [7, 8],
   "two displays stacked, the main one below: the main one, then the one above")
eq(D.candidates([display(7, "A", x: 0, y: 0), display(8, "B", x: 0, y: -1080)], main: 8).map(\.id), [8, 7],
   "two displays stacked, the main one on top: the main one, then the one below")
eq(D.candidates([display(3, "B", x: 1920), display(9, "A", x: 0)], main: 3).map(\.id), [3, 9],
   "side by side, the main one on the right: it, then wrapping to the left one")
eq(D.candidates([display(3, "B", x: 1920), display(9, "A", x: 0)], main: 9).map(\.id), [9, 3],
   "side by side, the main one on the left: it, then the right one")
// Noah's desk (the plan's list): the MacBook open, the 2560×1440 to its left, the 1920×1080 to its right; the
// main display the built-in screen, then the 2560×1440 as main with the lid closed.
let desk = [display(1, "MBP", x: 0, y: 0, hz: 120), display(5, "QHD", x: -2560, y: -458, w: 2560, h: 1440, hz: 60),
            display(6, "FHD", x: 1512, y: -98, w: 1920, h: 1080, hz: 60)]
eq(D.candidates(desk, main: 1).map(\.id), [1, 6, 5], "the MacBook main: Desktop 1 the MacBook, 2 the one to its right, 3 the left one")
let lidClosed = [display(5, "QHD", x: 0, y: 0, w: 2560, h: 1440, hz: 60), display(6, "FHD", x: 2560, y: 360, w: 1920, h: 1080, hz: 60)]
eq(D.candidates(lidClosed, main: 5).map(\.id), [5, 6], "the lid closed: the 2560×1440 main first, then the 1920×1080")
// Mirror sets: one stop each.
let mirrored = [display(1, "MBP", x: 0, y: 0), display(5, "TV", x: 0, y: 0, w: 1920, h: 1080, mirrors: 1),
                display(6, "FHD", x: 1512, y: 0, w: 1920, h: 1080)]
eq(D.candidates(mirrored, main: 1).map(\.id), [1, 6], "a display mirroring the main one is the main one's stop")
eq(D.candidates(mirrored, main: 5).map(\.id), [1, 6], "the main display a mirror of another: the stop it mirrors comes first")
eq(D.candidates([display(1, "A", x: 0, mirrors: 2), display(2, "B", x: 0, mirrors: 1)], main: 1).map(\.id), [1, 2],
   "two displays each saying they mirror the other: both kept, none lost")
eq(D.candidates([display(1, "A", x: 0), display(2, "B", x: 1512, mirrors: 99)], main: 1).map(\.id), [1, 2],
   "a display mirroring one not listed: a stop of its own")
eq(D.candidates([display(1, "A", x: 0, mirrors: 1), display(2, "B", x: 1512)], main: 1).map(\.id), [1, 2],
   "a display that says it mirrors itself: a stop")
// macOS's stand-in and Sill's own displays.
eq(D.candidates([display(1, "MBP", x: 0), display(9, "STANDIN", x: 1512, w: 1920, h: 1080, role: .standIn)], main: 1).map(\.id), [1],
   "macOS's 1x stand-in beside a real display: never a stop")
eq(D.candidates([display(9, "STANDIN", x: 0, w: 1920, h: 1080, role: .standIn)], main: 9).map(\.id), [],
   "macOS's stand-in alone: no stop (the Desktop falls back to it, as before)")
eq(D.candidates([display(1, "MBP", x: 0), display(54, "SILL-VD", x: -4000, role: .stage), display(55, "SILL-VD2", x: 5000, role: .stage)], main: 1).map(\.id), [1],
   "Sill's own displays, left and right: never stops")

// Noah's test of PR #355 (2026-11-12, 04:30), lid closed: the Lenovo (main) at 0,0 and the Dell to its left. Sill's stage
// display (81, to the right) was removed as the Desktop came back, and a step a second later, from the look before, said
// "Desktop: display 1 of 3": the removed display, its vendor read 0, counted as a screen.
let lenovo = display(0x41, "LENOVO", x: 0, y: 0, w: 2560, h: 1440, hz: 60, name: "LEN P24q-20")
let dell = display(0x40, "DELL", x: -1920, y: 156, w: 1920, h: 1080, hz: 60, name: "DELL P2219H")
let goneStage = display(0x51, "STAGE-81", x: 2560, y: 0, w: 2234, h: 1250, role: .stage, online: false)
eq(D.candidates([lenovo, dell, goneStage], main: 0x41).map(\.id), [0x41, 0x40], "Noah's desk after the stage's display went: two stops, the Lenovo first")
eq(D.candidates([dell, goneStage, lenovo], main: 0x41).count, 2, "listed in any order: two stops")
eq(D.next(after: 0x40, in: D.candidates([lenovo, dell, goneStage], main: 0x41))?.id, 0x41, "a step from the Dell: the Lenovo, display 1 of 2")
eq(D.number(of: 0x41, in: D.candidates([lenovo, dell, goneStage], main: 0x41)), 1, "the Lenovo is display 1")
eq(D.candidates([lenovo, dell, display(0x51, "STAGE-81", x: 2560, w: 2234, h: 1250, role: .stage)], main: 0x41).map(\.id), [0x41, 0x40],
   "the stage's display while it is up: no stop")
eq(D.candidates([lenovo, dell, display(0x51, "STAGE-81", x: 2560, w: 2234, h: 1250, online: false)], main: 0x41).map(\.id), [0x41, 0x40],
   "a display an old look lists after it went, whatever it reads now: no stop")
eq(D.candidates([lenovo, display(0x40, "DELL", x: -1920, y: 156, w: 1920, h: 1080, online: false)], main: 0x41).map(\.id), [0x41],
   "a monitor unplugged since the last look: no stop")
eq(D.candidates([display(0x41, "LENOVO", x: 0, w: 2560, h: 1440, online: false), dell], main: 0x41).map(\.id), [0x40],
   "the main display gone since the last look: the rest, as arranged")
// What a display is, by what it is: the stage's by the IDs it made this run or by its identity; never "Sill's vendor".
eq(D.role(vendor: 0xFFFF_FFFF, product: 0xFFFF_FFFF, madeByStage: true), .stage,
   "a display the stage made, removed (its ID reads 0xFFFFFFFF, as display 81 did on 2026-11-12): the stage's")
eq(D.role(vendor: 0, product: 0, madeByStage: true), .stage, "one that reads vendor 0: the stage's too")
eq(D.role(vendor: 0xFFFF_FFFF, product: 0xFFFF_FFFF, madeByStage: false), .screen, "a gone display the stage did not make: a screen, which online leaves out")
eq(D.noMonitor, 0xFFFF_FFFF, "what CoreGraphics reads of a display that has gone")
eq(D.role(vendor: 0x10AC, product: 0xA0C4, madeByStage: true), .screen, "a monitor given an ID the stage once had (IDs change across a sleep): a screen")
eq(D.role(vendor: 0x5111, product: 0x0001, madeByStage: true), .stage, "the stage's display while it is up")
eq(D.role(vendor: 0x5111, product: 0x0001, madeByStage: false), .stage, "the stage's identity, another Sill's stage on this Mac: the stage's")
eq(D.role(vendor: 0x5111, product: 0x0002, madeByStage: false), .sillDesktop, "Sill's Desktop display (#200's, the Virtual Desktop's): its own role")
eq(D.role(vendor: 0x5111, product: 0x0003, madeByStage: false), .screen, "another display with Sill's vendor is not the stage")
eq(D.role(vendor: 0x756e6b6e, product: 0x76697274, madeByStage: false), .standIn, "macOS's stand-in")
eq(D.role(vendor: 0x756e6b6e, product: 0x0001, madeByStage: false), .screen, "'unkn' alone is no stand-in")
eq(D.role(vendor: 0x10AC, product: 0xA0C4, madeByStage: false), .screen, "a Dell: a screen")
eq(D.role(vendor: 0, product: 0, madeByStage: false), .screen, "a display that reads vendor 0 and the stage did not make: a screen (online decides)")
eq(D.sillVendor, 0x5111, "Sill's vendor, the stage's since 2026-09-22 (VirtualStage.vendorID)")
eq(D.stageProduct, 0x0001, "the stage's product (VirtualStage.productID)")
eq(D.desktopProduct, 0x0002, "the Desktop's product (docs/virtual-desktop-plan.md §7)")
// Phase 1: Sill's Desktop display is no stop. PHASE 2 makes it the Virtual Desktop's last stop (candidates' marked line),
// and this case changes with it.
eq(D.candidates([lenovo, dell, display(0x60, "SILL-DESKTOP", x: 2560, w: 1920, h: 1080, role: .sillDesktop)], main: 0x41).map(\.id),
   [0x41, 0x40], "phase 1: Sill's Desktop display is no stop")
// The same arrangement in any order macOS lists it, and ties by ID.
eq(D.candidates([display(3, "C", x: 0, y: 0), display(2, "B", x: 0, y: 0)], main: nil).map(\.id), [2, 3],
   "two displays at one origin (a mirror macOS did not say): by ID, so the order never flips")

// Every arrangement of up to six displays, in a row and in a grid, with the main one anywhere: the main one,
// then each to its right, then wrapping to the leftmost.
var arrangements = 0
for n in 1...6 {
    for mainAt in 0..<n {
        let row = (0..<n).map { i in display(UInt32(10 + i * 7 % 13), "R\(i)", x: Double(i) * 1600 - 3200, y: Double(i % 2) * -300) }
        let want = Array(row[mainAt...] + row[..<mainAt]).map(\.id)
        for order in [row, row.reversed(), row.shuffled()] {
            arrangements += 1
            if D.candidates(order, main: row[mainAt].id).map(\.id) != want {
                check(false, "a row of \(n) with the main one at \(mainAt + 1), listed \(order.map(\.id)): \(D.candidates(order, main: row[mainAt].id).map(\.id)) (want \(want))")
            }
        }
        // A grid of two rows: columns left to right, each column top to bottom.
        let grid = (0..<n).map { i in display(UInt32(100 + i), "G\(i)", x: Double(i / 2) * 2000, y: Double(i % 2) * 1200 - 1200) }
        let sortedGrid = grid.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        let at = sortedGrid.firstIndex { $0.id == grid[mainAt].id }!
        let wantGrid = Array(sortedGrid[at...] + sortedGrid[..<at]).map(\.id)
        arrangements += 1
        if D.candidates(grid.shuffled(), main: grid[mainAt].id).map(\.id) != wantGrid {
            check(false, "a grid of \(n) with the main one at \(mainAt + 1): \(D.candidates(grid, main: grid[mainAt].id).map(\.id)) (want \(wantGrid))")
        }
    }
}
check(failures == 0, "every arrangement of one to six displays, in a row and a grid, the main one anywhere, any order listed (\(arrangements))")

// MARK: The stop the Desktop shows

eq(D.resolve(chosen: nil, among: c)?.id, 1, "nothing chosen: the main display (#345: never macOS's first, Virtual Display on or off)")
eq(D.resolve(chosen: "BENQ-R", among: c)?.id, 2, "a stop chosen and connected: that one")
eq(D.resolve(chosen: "GONE", among: c)?.id, 1, "a stop chosen and unplugged: the main display")
eq(D.resolve(chosen: "SILL-VD", among: c)?.id, 1, "Sill's own display chosen somehow: never; the main display")
eq(D.resolve(chosen: "BENQ-R", among: c, mainOnly: true)?.id, 1, "locked, or another user on the screen: the main display, whatever was chosen")
eq(D.resolve(chosen: nil, among: c, mainOnly: true)?.id, 1, "locked with nothing chosen: the main display")
let afterSleep = D.candidates([display(53, "BUILTIN", x: 0), display(52, "BENQ-R", x: 0, y: -2160, w: 3840, h: 2160)], main: 53)
eq(D.resolve(chosen: "BENQ-R", among: afterSleep)?.id, 52,
   "the chosen display back under a new ID after a sleep (2026-10-28: 21 → 53 and 52): still the one")
eq(D.resolve(chosen: nil, among: [])?.id, nil, "no stop: none")
eq(D.resolve(chosen: "BENQ-R", among: [], mainOnly: true)?.id, nil, "no stop, locked: none")

// MARK: The choice's span

eq(D.choiceGrace, 30, "the choice lasts 30 s after the last device left")
check(D.keepsChoice(devices: 1, leftAt: 0, now: 3600), "a device connected: kept, however long since one left")
check(D.keepsChoice(devices: 0, leftAt: nil, now: 0), "no device ever left: kept (there is no span to end)")
check(D.keepsChoice(devices: 0, leftAt: 100, now: 100), "the moment the last device left: kept")
check(D.keepsChoice(devices: 0, leftAt: 100, now: 129.9), "29.9 s later: kept (a reconnect, a move to the cable)")
check(!D.keepsChoice(devices: 0, leftAt: 100, now: 130), "30 s later: gone (a later session begins on the main display)")
check(!D.keepsChoice(devices: 0, leftAt: 100, now: 4000), "an hour later: gone")
check(!D.keepsChoice(devices: 0, leftAt: 100, now: 99), "a clock that went back: time passed, gone")

// MARK: The next stop

eq(D.next(after: 1, in: c)?.id, 4, "next after the main display: the leftmost (nothing to its right)")
eq(D.next(after: 4, in: c)?.id, 2, "next after the left monitor: the right one")
eq(D.next(after: 2, in: c)?.id, 1, "next after the last: back to the main display")
eq(D.next(after: 99, in: c)?.id, 1, "next after a display no longer listed: the main display")
eq(D.next(after: nil, in: c)?.id, 1, "next after none: the main display")
eq(D.next(after: 1, in: [builtIn])?.id, nil, "one stop: no next")
eq(D.next(after: nil, in: [])?.id, nil, "no stop: no next")
eq(D.next(after: 54, in: c)?.id, 1, "next after Sill's own display (no stop): the main display")
let deskStops = D.candidates(desk, main: 1)
eq([1, 6, 5].map { D.next(after: $0, in: deskStops)!.id }, [6, 5, 1], "Noah's desk: the MacBook, the right one, the left one, the MacBook")

// MARK: After a step

eq(D.afterStep(stepped: "BENQ-R", previous: "BENQ-L", streamed: true), "BENQ-R", "the stepped-to stop streams: kept")
eq(D.afterStep(stepped: "BENQ-R", previous: "BENQ-L", streamed: false), "BENQ-L",
   "it does not stream (ScreenCaptureKit refused it): back to the choice before, which streamed")
eq(D.afterStep(stepped: "BENQ-R", previous: nil, streamed: false), nil, "it does not stream, nothing chosen before: none (the main display)")

// MARK: Its number

eq(D.number(of: 1, in: c), 1, "the main display is Desktop 1")
eq(D.number(of: 4, in: c), 2, "the left monitor is Desktop 2")
eq(D.number(of: 2, in: c), 3, "the right monitor is Desktop 3")
eq(D.number(of: 54, in: c), nil, "Sill's own display has no number")
eq(D.number(of: nil, in: c), nil, "none has no number")

// MARK: Where input lands

// A device stepped to the right monitor: the catalog's display is the right one at once, but the capture still
// runs on the left one until the restart, and that is what the device shows.
eq(D.landing(streaming: 4, among: c), left.frame, "input lands on the stop the capture was built on, not the one just chosen")
let moved = D.candidates([display(4, "BENQ-L", x: 3840, y: 0, w: 3840, h: 2160), builtIn], main: 1)
eq(D.landing(streaming: 4, among: moved), CGRect(x: 3840, y: 0, width: 3840, height: 2160),
   "the same display moved in System Settings › Displays: where the newest look has it")
eq(D.landing(streaming: 99, among: c), nil, "the streamed display gone: none (the catalog's display then)")
eq(D.landing(streaming: nil, among: c), nil, "no Desktop capture yet: none (the catalog's display then)")
eq(D.landing(streaming: 54, among: c), nil, "Sill's own display is no stop: none")

// MARK: The rate on a stop

eq(D.rate(120, refreshHz: 60), 60, "a 60 Hz monitor, a 120 Hz iPad: 60 (its capture gives no more)")
eq(D.rate(60, refreshHz: 120), 60, "a 120 Hz display, a 60 Hz iPad: 60")
eq(D.rate(120, refreshHz: 120), 120, "ProMotion both ends: 120")
eq(D.rate(120, refreshHz: 144), 120, "a 144 Hz monitor: what the devices ask")
eq(D.rate(120, refreshHz: nil), 120, "a display that reports no rate (a built-in panel's 0): what the devices ask")
eq(D.rate(120, refreshHz: 0), 120, "a rate of 0: none")
eq(D.rate(120, refreshHz: 59.94), 60, "59.94 Hz: 60")
eq(D.rate(120, refreshHz: 119.88), 120, "119.88 Hz: 120")
eq(D.rate(60, refreshHz: 30), 30, "a 30 Hz monitor: 30")
eq(D.rate(60, refreshHz: 23.976), 24, "a 23.976 Hz mode: 24")
eq(D.rate(60, refreshHz: 15), 24, "a 15 Hz mode: never under 24")
eq(D.rate(24, refreshHz: 60), 24, "the devices at 24: 24")
eq(D.rate(120, refreshHz: -60), 120, "a negative rate: none")
eq(D.rate(120, refreshHz: .nan), 120, "no number: none")
eq(D.rate(120, refreshHz: .infinity), 120, "an infinite rate: none")
eq(D.rate(120, refreshHz: 1e300), 120, "a rate no display has: none (and no trap)")

// MARK: The device's button

let today = D.button(displays: nil, current: nil, names: nil, desktopStreams: true)
eq(today.label, "Desktop", "a Mac before this build: Desktop")
eq(today.accessibilityLabel, "Show the full Mac desktop", "a Mac before this build: today's VoiceOver label")
check(today.accessibilityValue == nil && today.accessibilityHint == nil && today.dots == 0 && today.counter == nil && !today.steps,
      "a Mac before this build: no value, hint, dots or step: today's button")
eq(D.button(displays: 1, current: 1, names: ["Built-in Retina Display"], desktopStreams: true),
   today, "one stop: today's button, whatever it is named")
let two = D.button(displays: 2, current: 2, names: ["Built-in Retina Display", "DELL U2723QE"], desktopStreams: true)
eq(two.label, "Desktop 2", "two stops, the second shown: Desktop 2")
check(two.dots == 2 && two.lit == 2 && two.counter == nil, "two stops, the Desktop streaming: two dots, the second filled")
eq(two.accessibilityLabel, "Desktop", "two stops: VoiceOver's label Desktop")
eq(two.accessibilityValue, "Display 2 of 2, DELL U2723QE", "two stops: VoiceOver's value names the stop")
eq(two.accessibilityHint, "Shows the next display.", "the Desktop streaming: the hint says a tap moves on")
check(two.steps, "the Desktop streaming on two stops: a tap steps")
let fromWindow = D.button(displays: 3, current: 2, names: ["A", "B", "C"], desktopStreams: false)
eq(fromWindow.label, "Desktop 2", "a window streaming: the label names the stop a tap brings back")
check(fromWindow.dots == 0 && fromWindow.counter == nil && !fromWindow.steps, "a window streaming: no dots, and a tap picks the Desktop")
eq(fromWindow.accessibilityHint, "Shows the Mac’s desktop.", "a window streaming: the hint says a tap shows the desktop")
let six = D.button(displays: 6, current: 4, names: nil, desktopStreams: true)
check(six.dots == 6 && six.lit == 4 && six.counter == nil, "six stops: six dots, the fourth filled")
eq(six.accessibilityValue, "Display 4 of 6", "no names: Display 4 of 6")
let seven = D.button(displays: 7, current: 3, names: nil, desktopStreams: true)
check(seven.dots == 0 && seven.lit == 0 && seven.counter == "3/7", "seven stops: 3/7 in place of the dots")
check(D.button(displays: 7, current: 3, names: nil, desktopStreams: false).counter == nil, "seven stops, a window streaming: no 3/7")
eq(D.button(displays: 2, current: nil, names: nil, desktopStreams: true), today, "two stops, which one unknown: today's button")
eq(D.button(displays: 2, current: 3, names: nil, desktopStreams: true), today, "a number past the count: today's button")
eq(D.button(displays: 2, current: 0, names: nil, desktopStreams: true), today, "a number of 0: today's button")
eq(D.value(2, of: 3, names: ["A", "B"]), "Display 2 of 3", "names not one per stop: no name")
eq(D.value(2, of: 2, names: ["A", "  "]), "Display 2 of 2", "an empty name: none")
eq(D.value(1, of: 2, names: [" LG HDR 4K\n", "B"]), "Display 1 of 2, LG HDR 4K", "a name trimmed")
eq(D.value(3, of: 2, names: ["A", "B"]), "Display 3 of 2", "a number past the names: no name, no trap")
eq(D.label(displays: 3, current: 3), "Desktop 3", "the label alone: Desktop 3")
check(D.tapSendsNext(desktopStreams: true, displays: 2, current: 1), "a tap steps: the Desktop streaming on two stops")
check(!D.tapSendsNext(desktopStreams: true, displays: 1, current: 1), "one stop: a tap picks the Desktop, as today")
check(!D.tapSendsNext(desktopStreams: true, displays: nil, current: nil), "a Mac before this build: a tap picks the Desktop")
check(!D.tapSendsNext(desktopStreams: false, displays: 3, current: 1), "a window streaming: a tap picks the Desktop")
check(!D.tapSendsNext(desktopStreams: true, displays: 0, current: nil), "no stop: a tap picks the Desktop")

// MARK: The pointer after a step

eq(D.pointerTarget(pointer: CGPoint(x: 100, y: 100), on: right.frame), CGPoint(x: 1920, y: -1080),
   "the pointer on the built-in screen, the Desktop now on the right monitor: its centre")
eq(D.pointerTarget(pointer: CGPoint(x: 100, y: -100), on: right.frame), nil, "the pointer already on it: left where it is")
eq(D.pointerTarget(pointer: nil, on: left.frame), CGPoint(x: -1920, y: -1080), "the pointer unknown: the centre")
eq(D.pointerTarget(pointer: CGPoint(x: 0, y: 0), on: right.frame), CGPoint(x: 1920, y: -1080),
   "the pointer on the shared edge, the right monitor's bottom (its rectangle ends there): the centre")

// MARK: Random arrangements

let before = failures
var rng = SystemRandomNumberGenerator()
var stepped = 0, mirrorsSeen = 0
for _ in 0..<5_000 {
    let n = Int.random(in: 0...6, using: &rng)
    var all: [D.Display] = []
    var used = Set<UInt32>()
    for i in 0..<n {
        var id: UInt32
        repeat { id = UInt32.random(in: 1...200, using: &rng) } while used.contains(id)
        used.insert(id)
        let kind = Int.random(in: 0..<10, using: &rng)
        let mirrorOf = kind == 9 && !all.isEmpty ? all.randomElement(using: &rng)?.id : nil
        if mirrorOf != nil { mirrorsSeen += 1 }
        all.append(display(id, "U\(id)", x: Double(Int.random(in: -4...4, using: &rng)) * 1000 + Double(i),
                           y: Double(Int.random(in: -2...2, using: &rng)) * 1000,
                           role: kind == 7 ? .stage : kind == 8 ? .standIn : kind == 6 && i % 2 == 0 ? .sillDesktop : .screen,
                           online: !(kind == 5 && i % 3 == 0), mirrors: mirrorOf, hz: [nil, 60, 120, 59.94].randomElement(using: &rng)!))
    }
    let main = Bool.random(using: &rng) ? all.randomElement(using: &rng)?.id : UInt32.random(in: 0...200, using: &rng)
    let stops = D.candidates(all.shuffled(using: &rng), main: main)
    // P1
    let real = all.filter { $0.role == .screen && $0.online }
    let byID = Dictionary(real.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let expected = real.filter { d in
        guard let m = d.mirrors, m != d.id, let p = byID[m] else { return true }
        return p.mirrors == d.id
    }
    if Set(stops.map(\.id)) != Set(expected.map(\.id)) || stops.count != expected.count {
        check(false, "P1 the stops are the screens on now, one per mirror set: \(stops.map(\.id)) of \(all.map(\.id))")
    }
    // P2
    let arranged = expected.sorted { ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id) }
    let mainStop = arranged.firstIndex { $0.id == main } ?? all.first { $0.id == main }?.mirrors.flatMap { m in arranged.firstIndex { $0.id == m } }
    let wantOrder = mainStop.map { Array(arranged[$0...] + arranged[..<$0]) } ?? arranged
    if stops.map(\.id) != wantOrder.map(\.id) { check(false, "P2 the arrangement turned to the main display: \(stops.map(\.id)) (want \(wantOrder.map(\.id)))") }
    // P3
    if stops.count > 1, let start = stops.randomElement(using: &rng) {
        var seen = [start.id]
        var at = start.id
        for _ in 0..<stops.count { at = D.next(after: at, in: stops)!.id; seen.append(at) }
        if seen.last != start.id || Set(seen).count != stops.count { check(false, "P3 next visits every stop once: \(seen)") }
        if D.next(after: 0, in: stops)?.id != stops[0].id { check(false, "P3 next from no stop: the main display's") }
        stepped += 1
    } else if D.next(after: stops.first?.id, in: stops) != nil {
        check(false, "P3 one stop or none: no next")
    }
    // P4
    let chosen = Bool.random(using: &rng) ? stops.randomElement(using: &rng)?.uuid : (Bool.random(using: &rng) ? "GONE" : nil)
    let mainOnly = Bool.random(using: &rng)
    let r = D.resolve(chosen: chosen, among: stops, mainOnly: mainOnly)
    let wantR = stops.isEmpty ? nil : (!mainOnly ? stops.first { $0.uuid == chosen } ?? stops[0] : stops[0])
    if r != wantR { check(false, "P4 resolved \(String(describing: r?.id)) (want \(String(describing: wantR?.id)))") }
}
check(stepped > 1000 && mirrorsSeen > 500, "the random arrangements stepped through \(stepped) with two stops or more, \(mirrorsSeen) mirrors")
check(failures == before, "5,000 random arrangements: P1 to P4 held")

// MARK: Random sessions (P5)
//
// A model of the host's catalog (WindowCatalog): the displays plugged in, the choice by UUID, when the last
// device left, the lock; driven by events at random times; after each, the stop the Desktop shows must be
// the model's.
struct Session {
    var plugged: [D.Display]
    var choice: String?
    var devices = 0
    var leftAt: Double?
    var locked = false
    var stops: [D.Display] { D.candidates(plugged, main: plugged.first?.id) }
    var shown: UInt32? { D.resolve(chosen: choice, among: stops, mainOnly: locked)?.id }
}
let pool = [display(1, "MAIN", x: 0, hz: 120), display(2, "RIGHT", x: 1512, w: 2560, h: 1440, hz: 60),
            display(3, "LEFT", x: -1920, w: 1920, h: 1080, hz: 60), display(4, "ABOVE", x: 0, y: -1440, w: 2560, h: 1440, hz: 144),
            display(5, "SIDECAR", x: 4072, w: 1366, h: 1024, hz: 60)]
let sessionsBefore = failures
var spansEnded = 0, unplugs = 0, refusedSteps = 0, lockedChecks = 0
for _ in 0..<5_000 {
    var s = Session(plugged: [pool[0]] + pool.dropFirst().filter { _ in Bool.random(using: &rng) })
    var now = 0.0
    // The person's view, kept apart from the rule: the stop they last stepped to and saw, forgotten once a
    // session starts more than 30 s after the last one ended.
    var seen: String? = nil
    var endedAt: Double? = nil
    for _ in 0..<40 {
        now += [0.5, 5, 20, 29.9, 30, 45, 3600].randomElement(using: &rng)!
        switch Int.random(in: 0..<8, using: &rng) {
        case 0:   // a device connects (WindowCatalog.devicesArrived)
            if s.devices == 0 {
                if s.choice != nil, let left = s.leftAt, !D.keepsChoice(devices: 0, leftAt: left, now: now) { s.choice = nil; spansEnded += 1 }
                s.leftAt = nil
                if let ended = endedAt, now - ended >= 30 { seen = nil }
                endedAt = nil
            }
            s.devices += 1
        case 1:   // a device leaves
            guard s.devices > 0 else { continue }
            s.devices -= 1
            if s.devices == 0 { s.leftAt = now; endedAt = now }
        case 2, 3:   // a tap steps: a device connected, unlocked (kind 47 is refused locked), two stops or more
            guard s.devices > 0, !s.locked, let next = D.next(after: s.shown, in: s.stops) else { continue }
            let streams = Int.random(in: 0..<10, using: &rng) > 0
            s.choice = D.afterStep(stepped: next.uuid, previous: s.choice, streamed: streams)
            if streams { seen = next.uuid } else { refusedSteps += 1 }
            if streams, s.shown != next.id { check(false, "P5 a step that streamed shows the stepped-to stop") }
        case 4:   // a monitor unplugged (never the main one)
            if s.plugged.count > 1 { s.plugged.remove(at: Int.random(in: 1..<s.plugged.count, using: &rng)); unplugs += 1 }
        case 5:   // a monitor plugged back in
            if let back = pool.dropFirst().filter({ d in !s.plugged.contains { $0.id == d.id } }).randomElement(using: &rng) { s.plugged.append(back) }
        case 6:
            s.locked.toggle()
        default:
            break
        }
        // What the person should see: locked, the main display (its lock screen); else the stop they last
        // stepped to while it is plugged in and its session's span lasts; else the main display.
        guard s.devices > 0 else { continue }
        let want: UInt32? = s.locked ? s.stops.first?.id : (s.stops.first { $0.uuid == seen }?.id ?? s.stops.first?.id)
        if s.shown != want { check(false, "P5 shown \(String(describing: s.shown)) (want \(String(describing: want)))") }
        if s.locked { lockedChecks += 1; if s.shown != 1 { check(false, "P5 locked: the main display, whatever was chosen") } }
    }
}
check(spansEnded > 500 && unplugs > 1000 && refusedSteps > 1000 && lockedChecks > 1000,
      "the random sessions ended \(spansEnded) spans, unplugged \(unplugs) monitors, \(refusedSteps) steps that did not stream, \(lockedChecks) looks while locked")
check(failures == sessionsBefore, "5,000 random sessions: P5 held")

// MARK: Random buttons (P6) and rates (P7)

let buttonsBefore = failures
for _ in 0..<20_000 {
    let displays: Int? = Bool.random(using: &rng) ? Int.random(in: -1...9, using: &rng) : nil
    let current: Int? = Bool.random(using: &rng) ? Int.random(in: -1...10, using: &rng) : nil
    let streams = Bool.random(using: &rng)
    let names: [String]? = displays.flatMap { d in Bool.random(using: &rng) && d > 0 ? (0..<d).map { "N\($0)" } : nil }
    let b = D.button(displays: displays, current: current, names: names, desktopStreams: streams)
    let multi = (displays ?? 0) > 1 && current.map { (1...max(1, displays ?? 1)).contains($0) } == true && (displays ?? 0) >= (current ?? 0)
    if multi {
        if b.label != "Desktop \(current!)" || b.accessibilityLabel != "Desktop" || b.accessibilityValue == nil {
            check(false, "P6 \(String(describing: displays)) \(String(describing: current)): the stop's label and value")
        }
        if b.steps != streams { check(false, "P6 a tap steps exactly while the Desktop streams") }
        let wantDots = streams && displays! <= D.maxDots ? displays! : 0
        if b.dots != wantDots || (b.dots > 0 && b.lit != current) || (b.dots == 0 && b.lit != 0) { check(false, "P6 the dots: \(b)") }
        if (b.counter != nil) != (streams && displays! > D.maxDots) || (b.counter != nil && b.counter != "\(current!)/\(displays!)") {
            check(false, "P6 the counter: \(b)")
        }
        if b.steps != D.tapSendsNext(desktopStreams: streams, displays: displays, current: current) { check(false, "P6 tapSendsNext is the button's") }
    } else if b != today {
        check(false, "P6 \(String(describing: displays)) \(String(describing: current)): today's button")
    }
    let wanted = Int.random(in: 24...240, using: &rng)
    let hz: Double? = [nil, 0, -1, 23.976, 30, 47.95, 59.94, 60, 75, 119.88, 120, 144, 165, 240, .nan, 1e9].randomElement(using: &rng)!
    let rate = D.rate(wanted, refreshHz: hz)
    let reports = hz.map { $0.isFinite && $0 > 0 && $0 < 1000 } ?? false
    if rate > wanted || rate < 24 || (reports && rate > max(24, Int(hz!.rounded()))) || (!reports && rate != wanted) {
        check(false, "P7 rate(\(wanted), \(String(describing: hz))) = \(rate)")
    }
}
check(failures == buttonsBefore, "20,000 random buttons and rates: P6 and P7 held")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
