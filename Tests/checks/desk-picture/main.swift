// The desk's picture check (Sources/SillHost/DeskPicture.swift): whether a hidden display's picture
// of a window is the window. Compiled with DeskPicture.swift alone (run.sh).
import CoreGraphics
import CoreVideo
import Foundation

var failures = 0, passed = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passed += 1 } else { failures += 1; print("FAIL \(what)") }
}
let n = DeskPicture.columns * DeskPicture.rows

// differs: the middle cell difference against the tolerance.
let bright = [UInt8](repeating: 230, count: n), black = [UInt8](repeating: 0, count: n)
check(!DeskPicture.differs(bright, bright), "the same picture is the window")
check(DeskPicture.differs(black, bright), "black against a bright window differs")
check(DeskPicture.differs(bright, black), "a bright picture against a black window differs")
check(!DeskPicture.differs(black, black), "a black window shown black is the window")
func covered(_ fraction: Double, by value: UInt8) -> [UInt8] {
    var g = bright
    for i in 0..<Int(Double(n) * fraction) { g[i] = value }
    return g
}
check(!DeskPicture.differs(covered(0.4, by: 20), bright), "a sheet over 40% of the window is still the window")
check(!DeskPicture.differs(covered(0.49, by: 20), bright), "49% covered is still the window")
check(DeskPicture.differs(covered(0.55, by: 20), bright), "55% of the cells changed differs")
var middle = bright
for i in (n / 2 - 30)..<(n / 2 + 30) { middle[i] = 20 }   // a sheet over the middle 60 cells of 160
check(!DeskPicture.differs(middle, bright), "a sheet over the middle cells is still the window")
check(DeskPicture.differs(covered(0.8, by: 20), bright), "80% of the cells changed differs")
check(!DeskPicture.differs(bright.map { $0 - UInt8(DeskPicture.cellTolerance) }, bright), "every cell off by the tolerance is the window")
check(DeskPicture.differs(bright.map { $0 - UInt8(DeskPicture.cellTolerance + 1) }, bright), "every cell off by more than the tolerance differs")
check(!DeskPicture.differs(bright.map { $0 - 30 }, bright), "a slightly darker picture (a video's frame later) is the window")
check(!DeskPicture.differs([], []), "no cells: no verdict")
// A dark window (a dark theme: cells 20-60, text a little brighter) against a black or flat picture.
let dark = (0..<160).map { UInt8(20 + ($0 * 7) % 41) }
check(DeskPicture.differs(black, dark), "black against a dark window with detail differs")
check(DeskPicture.differs([UInt8](repeating: 16, count: 160), dark), "video-range black against a dark window differs")
check(DeskPicture.differs([UInt8](repeating: 30, count: 160), dark), "a flat grey against a dark window differs")
check(!DeskPicture.differs(dark, dark), "a dark window shown as itself is the window")
check(!DeskPicture.differs(dark.map { $0 + 4 }, dark), "a dark window a little brighter is the window")
let flatDark = [UInt8](repeating: 25, count: 160)
check(!DeskPicture.differs(black, flatDark), "black against a dark window with no detail: no verdict either way, kept")
check(!DeskPicture.differs(flatDark, flatDark), "a flat window shown flat is the window")
let justDetail = (0..<160).map { UInt8(20 + ($0 % 2) * DeskPicture.detailSpread) }
let justUnder = (0..<160).map { UInt8(20 + ($0 % 2) * (DeskPicture.detailSpread - 1)) }
check(DeskPicture.differs(black, justDetail), "a window spanning exactly the detail spread counts as detail")
check(!DeskPicture.differs(black, justUnder), "a window spanning just under it does not")
let justFlat = (0..<160).map { UInt8(($0 % 2) * DeskPicture.flatSpread) }
let justNotFlat = (0..<160).map { UInt8(($0 % 2) * (DeskPicture.flatSpread + 1)) }
check(DeskPicture.differs(justFlat, dark), "a picture spanning exactly the flat spread is flat")
check(!DeskPicture.differs(justNotFlat, dark), "a picture spanning just over it is not flat")
check(!DeskPicture.differs(black, Array(bright.prefix(10))), "cells of another count: no verdict")
var someNoise = bright
for i in stride(from: 0, to: n, by: 3) { someNoise[i] = 10 }   // a third of the cells far off
check(!DeskPicture.differs(someNoise, bright), "a third of the cells far off (a caret, a spinner, text) is the window")
check(DeskPicture.cellTolerance == 48, "the tolerance is 48 of 255")

// grid of an image: cells in reading order, the top row first, over black.
func image(_ w: Int, _ h: Int, alpha: Bool = false, _ fill: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    fill(ctx)
    return ctx.makeImage()!
}
let white = image(160, 100) { $0.setFillColor(CGColor(gray: 1, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 160, height: 100)) }
let gw = DeskPicture.grid(white)
check(gw?.count == n && gw!.allSatisfy { $0 > 245 }, "a white image's cells are all white")
// CGContext's origin is at the bottom: the top half black is y 50…100.
let topBlack = image(160, 100) { c in
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 50, width: 160, height: 50))
}
let gt = DeskPicture.grid(topBlack)!
check(gt[0] < 10 && gt[n - 1] > 245, "an image's top row is the grid's first (\(gt[0]), \(gt[n - 1]))")
let leftBlack = image(160, 100) { c in
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
}
let gl = DeskPicture.grid(leftBlack)!
check(gl[0] < 10 && gl[DeskPicture.columns - 1] > 245, "an image's left column is each row's first")
let clear = image(160, 100, alpha: true) { $0.clear(CGRect(x: 0, y: 0, width: 160, height: 100)) }
check(DeskPicture.grid(clear)!.allSatisfy { $0 < 5 }, "a transparent image is black (the frame's background behind rounded corners)")

// grid of a 420f frame: the Y plane, the top row first, like the image's.
func frame(_ w: Int, _ h: Int, _ luma: (Int, Int) -> UInt8) -> CVPixelBuffer {
    var px: CVPixelBuffer?
    CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &px)
    CVPixelBufferLockBaseAddress(px!, [])
    let y = CVPixelBufferGetBaseAddressOfPlane(px!, 0)!.assumingMemoryBound(to: UInt8.self)
    let bpr = CVPixelBufferGetBytesPerRowOfPlane(px!, 0)
    for r in 0..<h { for c in 0..<w { y[r * bpr + c] = luma(c, r) } }
    CVPixelBufferUnlockBaseAddress(px!, [])
    return px!
}
let f200 = DeskPicture.grid(frame(320, 200) { _, _ in 200 })
check(f200?.count == n && f200!.allSatisfy { $0 == 200 }, "a flat frame's cells are its luma")
let fTop = DeskPicture.grid(frame(320, 200) { _, r in r < 100 ? 0 : 255 })!
check(fTop[0] == 0 && fTop[n - 1] == 255, "a frame's top row is the grid's first, as an image's")
check(!DeskPicture.differs(fTop, gt), "a frame and a screenshot of one picture (top half black) agree")
check(DeskPicture.differs(fTop, DeskPicture.grid(frame(320, 200) { _, r in r < 100 ? 255 : 0 })!), "a frame upside down differs")
let fLeft = DeskPicture.grid(frame(320, 200) { c, _ in c < 160 ? 0 : 255 })!
check(fLeft[0] == 0 && fLeft[DeskPicture.columns - 1] == 255, "a frame's left column is each row's first")
check(DeskPicture.grid(frame(8, 8) { _, _ in 100 }) == nil, "a frame smaller than the grid: no cells")

print(failures == 0 ? "\(passed) checks, 0 failed" : "\(passed) passed, \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
