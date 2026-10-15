import Foundation

// StreamRate (Sources/SillHost/StreamRate.swift): the hardware stream's rate at its size.
var checks = 0, failures = 0
func check(_ what: String, _ ok: Bool) { checks += 1; if !ok { failures += 1; print("FAIL \(what)") } else { print("ok   \(what)") } }
let r = StreamRate.capped

check("a Retina 4K-sized window (3930×2188) at 120 fps: 60", r(120, 3930 * 2188, false) == 60)
check("3840×2100 at 120: 60", r(120, 3840 * 2100, false) == 60)
check("a Retina laptop window (3024×1964) at 120: 60 (5.9 MP: 87 fps fit, so 60, not 90)", r(120, 3024 * 1964, false) == 60)
check("3024×1600 at 120: 90 (4.8 MP: 107 fit)", r(120, 3024 * 1600, false) == 90)
check("a Standard window (1920×1050) at 120: 120", r(120, 1920 * 1050, false) == 120)
check("2560×1600 at 120: 120 (4.1 MP: 127 fit)", r(120, 2560 * 1600, false) == 120)
check("60 asked where 60 fits: 60", r(60, 3930 * 2188, false) == 60)
check("60 asked where 90 would fit: 60, never more than asked", r(60, 3024 * 1600, false) == 60)
check("48 asked where 60 fits: 48", r(48, 3930 * 2188, false) == 48)
check("an 8K frame (7680×4320) at 120: 30 at least, never under", r(120, 7680 * 4320, false) == 30)
check("an 8K frame asked at 24: 24 (under the floor, as asked)", r(24, 7680 * 4320, false) == 24)
check("the software encoder: as asked (it has its own cap)", r(120, 3930 * 2188, true) == 120)
check("no picture yet: as asked", r(120, 0, false) == 120)
check("exactly at the budget (100 fps of 5.2 MP): as asked", r(100, 5_200_000, false) == 100)
check("one pixel over the budget at 120: 90", r(120, Int(StreamRate.hardwareBudget / 120) + 1, false) == 90)
print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
