import CoreGraphics
import Foundation

/// A Virtual Desktop of the size and refresh rate a person types (part B of 2026-11-25; Sill for Mac's Settings › Displays,
/// Resolution's "Custom…", and the CLI's --virtual-desktop=WxH@S:HZ). Noah, 2026-11-24, whole: "For Virtual Desktop, I
/// would also like to allow users to be able to set custom resolutions/refresh rates up to 2x native resolution of device
/// panel and 120Hz. So for an iPad Pro 13" for example, max would be 5504 × 4128 at 120Hz or any resolution/refresh rate
/// that is less than 2726461440 pixels per second (so 4K at same refresh would work, ultra wide, higher res at 60Hz,
/// etc)." The design he agreed to: (1) that budget is the ceiling for what can be typed in, anything above it refused with
/// a plain sentence; (2) Sill says what this Mac can carry (`encoderNote`); (3) a desktop larger than the encoder takes
/// still works, the picture scaled down to fit the encoder (EncoderLimit, #295); (4) Match the device stays the default;
/// and since the setting is the Mac's and the budget a device's, the display keeps its size and a device with a smaller
/// budget gets the picture scaled for it (`view`). His answer: "I agree with your assessment on the custom sizes,
/// implement it. Make it work depending on the device (iPhone, iPad, etc as you described)."
///
/// - **A device's budget** (`budget`): (2 × its screen's pixels wide) × (2 × its screen's pixels high) × 120 pixels a
///   second, "at most" including the number itself: an iPad Pro 13-inch's 2064 × 2752 is 5504 × 4128 at 120 Hz,
///   2,726,461,440. The screen is the one its viewport names (Viewport.screen, part A); `current` lists every current
///   iPhone's and iPad's.
/// - **The ceiling a person may type** (`ceiling`): the largest budget among the devices this Mac knows (Sill for Mac
///   keeps each device that showed it its screen), or the largest current iPad's (`largestIPad`) when it knows none: a size
///   chosen for an iPad Pro can be over an iPhone's budget, and that iPhone then gets it scaled.
/// - **What can be a display at all** (`VirtualDesktopSize.custom`): each side 640 to 8192 pixels; a Retina desktop (2x,
///   half as many points each way) an even number of pixels each way and one side of 1600 pixels or more; a rate a whole
///   number of 24 to 120 Hz.
/// - **What a device gets** (`view`): its own rate (the display's, held to what the device shows), and the display's
///   picture as it is while its pixels a second are within the device's budget, else scaled down evenly to it, its shape
///   kept. Sill streams one picture to every connected device, so the picture is the smallest of theirs.
///
/// Pure (Foundation, CoreGraphics; `VirtualDesktopSize.Size`); checked by Tests/checks/virtual-desktop.
package enum VirtualDesktopBudget {
    /// A device as the budget counts it: its name, its screen's pixels held upright, whether it is an iPhone's, and the
    /// rate its viewport asks (120 on ProMotion, 60 otherwise; 60 when it never said).
    package struct Device: Equatable, Codable {
        package var name: String
        package var pixelWidth: Int
        package var pixelHeight: Int
        package var phone: Bool
        package var fps: Int

        package init(name: String, pixelWidth: Int, pixelHeight: Int, phone: Bool, fps: Int) {
            self.name = name; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.phone = phone; self.fps = fps
        }
    }

    /// The most a device takes: twice its screen each way at 120 Hz, in pixels a second.
    package static func budget(pixelWidth: Int, pixelHeight: Int) -> Int { (2 * pixelWidth) * (2 * pixelHeight) * 120 }
    package static func budget(_ d: Device) -> Int { budget(pixelWidth: d.pixelWidth, pixelHeight: d.pixelHeight) }

    /// The largest current iPad, whose budget is the ceiling while this Mac knows no device: 2,726,461,440.
    package static let largestIPad = Device(name: "iPad Pro 13-inch", pixelWidth: 2064, pixelHeight: 2752, phone: false, fps: 120)

    /// Every current iPhone's and iPad's screen in pixels, held upright: Xcode 27.1's simulator profiles of each
    /// (CoreSimulator's DeviceTypes, each one's ScreenDimensionsCapability), which are Apple's own; the iPhone Duo's both
    /// screens (its outer one the profile's main screen, its inner one its third). Noah's iPad mini and iPhone 15 Pro
    /// print theirs in their consoles alike. The rate is each one's panel's (120 on ProMotion).
    package static let current: [Device] = [
        Device(name: "iPhone 15 Pro", pixelWidth: 1179, pixelHeight: 2556, phone: true, fps: 120),
        Device(name: "iPhone 16", pixelWidth: 1179, pixelHeight: 2556, phone: true, fps: 60),
        Device(name: "iPhone 16 Plus", pixelWidth: 1290, pixelHeight: 2796, phone: true, fps: 60),
        Device(name: "iPhone 16e", pixelWidth: 1170, pixelHeight: 2532, phone: true, fps: 60),
        Device(name: "iPhone 17e", pixelWidth: 1170, pixelHeight: 2532, phone: true, fps: 60),
        Device(name: "iPhone 17", pixelWidth: 1206, pixelHeight: 2622, phone: true, fps: 120),
        Device(name: "iPhone Air", pixelWidth: 1260, pixelHeight: 2736, phone: true, fps: 120),
        Device(name: "iPhone 17 Pro", pixelWidth: 1206, pixelHeight: 2622, phone: true, fps: 120),
        Device(name: "iPhone 17 Pro Max", pixelWidth: 1320, pixelHeight: 2868, phone: true, fps: 120),
        Device(name: "iPhone 18 Pro", pixelWidth: 1206, pixelHeight: 2622, phone: true, fps: 120),
        Device(name: "iPhone 18 Pro Max", pixelWidth: 1320, pixelHeight: 2868, phone: true, fps: 120),
        Device(name: "iPhone SE", pixelWidth: 750, pixelHeight: 1334, phone: true, fps: 60),
        Device(name: "iPhone Duo, outer screen", pixelWidth: 1398, pixelHeight: 2034, phone: true, fps: 120),
        Device(name: "iPhone Duo, inner screen", pixelWidth: 2007, pixelHeight: 2853, phone: true, fps: 120),
        Device(name: "iPad mini", pixelWidth: 1488, pixelHeight: 2266, phone: false, fps: 60),
        Device(name: "iPad", pixelWidth: 1640, pixelHeight: 2360, phone: false, fps: 60),
        Device(name: "iPad Air 11-inch", pixelWidth: 1640, pixelHeight: 2360, phone: false, fps: 60),
        Device(name: "iPad Air 13-inch", pixelWidth: 2048, pixelHeight: 2732, phone: false, fps: 60),
        Device(name: "iPad Pro 11-inch", pixelWidth: 1668, pixelHeight: 2420, phone: false, fps: 120),
        largestIPad,
    ]

    /// The device whose budget is the ceiling of what may be typed: the largest budget among `known` (the devices this Mac
    /// knows), else the largest current iPad.
    package static func ceiling(known: [Device]) -> Device {
        known.max { budget($0) < budget($1) } ?? largestIPad
    }

    /// How Settings and a refusal name a device. A device of Sill's calls itself by its kind and its model identifier,
    /// "iPad (iPad16,6)" (UIDevice's name, which since iOS 16 is the kind alone, ClientStatsReporter.deviceName), which the
    /// status menu shows as "iPad": so it is "your iPad", and "your iPad (iPad16,6)" while another device of `known` is of
    /// its kind too, so the two read apart. A name with no identifier (the table's, a test's) as it is. `start`: the name
    /// begins a line ("Your iPad").
    package static func shownName(_ d: Device, among known: [Device], start: Bool = false) -> String {
        guard d.name.hasSuffix(")"), let cut = d.name.range(of: " ("), cut.lowerBound > d.name.startIndex else { return d.name }
        let kind = String(d.name[..<cut.lowerBound])
        let twin = known.contains { $0.name != d.name && $0.name.hasPrefix(kind + " (") }
        return (start ? "Your " : "your ") + (twin ? d.name : kind)
    }

    // MARK: What may be typed (VirtualDesktopSize.custom holds what can be a display; this, what a device takes)

    /// The least side, in pixels (VirtualDesktopSize.customSides).
    package static var minSide: Int { VirtualDesktopSize.customSides.lowerBound }
    /// The most, in pixels.
    package static var maxSide: Int { VirtualDesktopSize.customSides.upperBound }
    /// A Retina desktop's longer side at least, in pixels (VirtualDesktopSize.customRetinaLong).
    package static var retinaLong: Int { VirtualDesktopSize.customRetinaLong }
    /// The rates that may be typed (VirtualDesktopSize.customRates).
    package static var rates: ClosedRange<Int> { VirtualDesktopSize.customRates }

    /// Why a typed size or rate is refused.
    package enum Refusal: Error, Equatable {
        /// A side not typed, or not a whole number.
        case missing
        /// A side under `minSide`.
        case small
        /// A side over `maxSide`.
        case large
        /// A Retina desktop with an odd number of pixels a side.
        case odd
        /// A Retina desktop with both sides under `retinaLong`.
        case retinaSmall
        /// A rate not typed, or out of `rates`.
        case rate
        /// More pixels a second than the ceiling's device takes (`device`: it).
        case ceiling(Device)
    }

    /// A typed entry: `width` × `height` pixels, Retina or not, at `hz` (0: the device's rate, as Match the device's), within
    /// the ceiling of `ceilingDevice`: the size (points and scale, VirtualDesktopSize's form) and the rate, or why not. The
    /// ceiling counts the rate asked, or 120 for the device's rate (the most it may be).
    package static func entry(width: Int?, height: Int?, retina: Bool, hz: Int?, ceiling ceilingDevice: Device) -> Result<(size: VirtualDesktopSize.Size, hz: Int), Refusal> {
        guard let w = width, let h = height else { return .failure(.missing) }
        guard w >= minSide, h >= minSide else { return .failure(.small) }
        guard w <= maxSide, h <= maxSide else { return .failure(.large) }
        if retina {
            guard w % 2 == 0, h % 2 == 0 else { return .failure(.odd) }
            guard max(w, h) >= retinaLong else { return .failure(.retinaSmall) }
        }
        guard let rate = hz, rate == 0 || rates.contains(rate) else { return .failure(.rate) }
        guard w * h * (rate == 0 ? rates.upperBound : rate) <= budget(ceilingDevice) else { return .failure(.ceiling(ceilingDevice)) }
        let size = retina ? VirtualDesktopSize.Size(widthPt: w / 2, heightPt: h / 2, scale: 2) : VirtualDesktopSize.Size(widthPt: w, heightPt: h, scale: 1)
        // What can be a display is VirtualDesktopSize's (the saved value's) rule: the two agree.
        guard VirtualDesktopSize.custom(VirtualDesktopSize.id(size)) == size else { return .failure(.small) }
        return .success((size, rate))
    }

    /// The pixels each way and whether it is Retina, of a size's id the person typed or chose ("2752x2064@2" → 5504, 4128,
    /// Retina), for the entry's fields; nil for This device and the main display.
    package static func fields(_ id: String) -> (width: Int, height: Int, retina: Bool)? {
        guard case .fixed(let s)? = VirtualDesktopSize.choice(id) else { return nil }
        return (s.widthPt * s.scale, s.heightPt * s.scale, s.scale == 2)
    }

    /// The CLI's refusal of `--virtual-desktop=VALUE` (it knows no device: the ceiling is the largest current iPad's), nil
    /// when it takes it: a value of no form it knows says the forms; a typed size over the ceiling, its sentence.
    package static func flagRefusal(_ value: String) -> String? {
        guard let chosen = VirtualDesktopSize.flag(value) else {
            // A size of its own written right whose pixels or rate cannot be: the entry's own sentence.
            let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let at = parts[0].split(separator: "@").map(String.init), wh = at.first?.split(separator: "x").map(String.init) ?? []
            if parts.count <= 2, at.count == 2, let s = Int(at[1]), s == 1 || s == 2, wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]),
               w > 0, h > 0, case .failure(let r) = entry(width: w * s, height: h * s, retina: s == 2, hz: parts.count == 2 ? Int(parts[1]) : 0,
                                                          ceiling: ceiling(known: [])) {
                return sentence(r)
            }
            return "--virtual-desktop=… takes device, main, a size of Sill for Mac's list (" + VirtualDesktopSize.offered.map(VirtualDesktopSize.id)
                .joined(separator: ", ") + ") or one of your own as WxH@1 or WxH@2 in points (each side \(minSide) to \(maxSide) pixels), "
                + "then :\(rates.lowerBound) to :\(rates.upperBound) for its rate."
        }
        guard case .fixed(let s)? = VirtualDesktopSize.choice(chosen.size) else { return nil }
        if case .failure(let r) = entry(width: s.widthPt * s.scale, height: s.heightPt * s.scale, retina: s.scale == 2, hz: chosen.hz,
                                       ceiling: ceiling(known: [])) {
            return sentence(r)
        }
        return nil
    }

    /// The one plain sentence a refusal shows, beside the entry (and the CLI's refusal): the ceiling named as the device
    /// it is (`shownName` among `known`) and its size at 120 Hz, the longer side first ("5504 × 4128").
    package static func sentence(_ r: Refusal, known: [Device] = []) -> String {
        switch r {
        case .missing: return "Type a width and a height in pixels."
        case .small: return "Each side needs at least \(minSide) pixels."
        case .large: return "Each side can be at most \(maxSide) pixels."
        case .odd: return "A Retina desktop needs an even number of pixels each way."
        case .retinaSmall: return "A Retina desktop needs one side of \(retinaLong) pixels or more: macOS shows a smaller one at standard resolution."
        case .rate: return "The refresh rate can be \(rates.lowerBound) to \(rates.upperBound) Hz."
        case .ceiling(let d):
            let long = 2 * max(d.pixelWidth, d.pixelHeight), short = 2 * min(d.pixelWidth, d.pixelHeight)
            return "That’s more than Sill sends to \(shownName(d, among: known)): up to \(long) × \(short) at 120 Hz, or as many pixels a second at a lower rate."
        }
    }

    /// What may be typed, beside an empty entry (and while no device is known): "Up to 5504 × 4128 at 120 Hz for your iPad,
    /// or as many pixels a second at a lower rate." (`d` the ceiling among `known`, the devices this Mac knows), or with
    /// none known, "No device has connected yet: up to …, the largest current iPad's, …".
    package static func upTo(_ d: Device, known: [Device]) -> String {
        let long = 2 * max(d.pixelWidth, d.pixelHeight), short = 2 * min(d.pixelWidth, d.pixelHeight)
        let size = "\(long) × \(short) at 120 Hz"
        return !known.isEmpty ? "Up to \(size) for \(shownName(d, among: known)), or as many pixels a second at a lower rate."
                              : "No device has connected yet: up to \(size), the largest current iPad’s, or as many pixels a second at a lower rate."
    }

    // MARK: What a device gets

    /// What a device gets of a display of `width` × `height` pixels at `hz`: its own rate (the display's, held to
    /// `device.fps`), and the picture as it is when its pixels a second at that rate are within the device's budget, else
    /// scaled down evenly to it (its shape kept, each side even, at least 2).
    package struct View: Equatable {
        package var width: Int
        package var height: Int
        package var hz: Int
        package var scaled: Bool
    }

    package static func view(width: Int, height: Int, hz: Int, device: Device) -> View {
        let rate = max(1, min(hz, device.fps))
        guard let held = fitted(width: width, height: height, fps: rate, budget: budget(device)) else {
            return View(width: width, height: height, hz: rate, scaled: false)
        }
        return View(width: held.width, height: held.height, hz: rate, scaled: true)
    }

    /// `width` × `height` at `fps`, scaled down evenly until its pixels a second are within `budget`: the largest such size
    /// of its shape with even sides; nil when it is within already.
    package static func fitted(width: Int, height: Int, fps: Int, budget: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0, fps > 0, width * height * fps > budget else { return nil }
        let f = (Double(budget) / Double(width * height * fps)).squareRoot()
        var w = max(2, Int(Double(width) * f) & ~1), h = max(2, Int(Double(height) * f) & ~1)
        while w * h * fps > budget, w > 2, h > 2 { w -= 2; h = max(2, Int(Double(w) * Double(height) / Double(width)) & ~1) }
        return (w, h)
    }

    /// Settings' lines beside a typed size: each device this Mac knows (`known`), as it gets it ("Your iPad shows it at
    /// full size, 120 Hz." or "Your iPhone shows it scaled down to 4008 × 3006, 120 Hz."; `shownName`). Noah's words,
    /// 2026-11-26, shown these two for "Your iPad: as it is, at 60 Hz.", which he asked the meaning of: "use those".
    package static func deviceLine(width: Int, height: Int, hz: Int, device: Device, among known: [Device] = []) -> String {
        let v = view(width: width, height: height, hz: hz == 0 ? device.fps : hz, device: device)
        let name = shownName(device, among: known, start: true)
        return v.scaled ? "\(name) shows it scaled down to \(v.width) × \(v.height), \(v.hz) Hz."
                        : "\(name) shows it at full size, \(v.hz) Hz."
    }

    // MARK: What this Mac can carry (Noah's agreed point 2: "Sill says what this Mac can carry")

    /// What Sill knows of this Mac's video encoder for a size: the widest picture its hardware encoder takes when it took
    /// none of this size (`widest`: EncoderLimit.side, from #295's check, HEVCEncoder.hardwareTakes; nil when it took it or
    /// was not asked), the frames a second it encoded at this size when Sill measured it (`fps`: EncoderProbe.throughput
    /// with no device connected; nil before), and whether it streams on its software encoder now.
    package struct Encoder: Equatable {
        package var widest: Int?
        package var fps: Double?
        package var software: Bool

        package init(widest: Int? = nil, fps: Double? = nil, software: Bool = false) {
            self.widest = widest; self.fps = fps; self.software = software
        }
    }

    /// TEST ONLY: `SILL_TEST_ENCODER=widest=4096,fps=31` on a test host (`--synthetic`, never Sill.app): what its encoder
    /// is said to carry (the widest picture its hardware takes, the frames a second it encodes the chosen size at), so
    /// the gates see the encoder's hold (EncoderLimit, #295) and its note on the software encoder a test host streams
    /// with, never this Mac's hardware. Its line at start; anywhere else, or a word it does not know, a line and nothing.
    package static let testEncoderVariable = "SILL_TEST_ENCODER"

    package static func testEncoder(environment: [String: String], testHost: Bool) -> (encoder: Encoder?, line: String?) {
        guard let raw = environment[testEncoderVariable], !raw.isEmpty else { return (nil, nil) }
        guard testHost else { return (nil, "\(testEncoderVariable) ignored: only a --synthetic test host takes it, never Sill.app.") }
        var e = Encoder()
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "widest", let w = Int(kv[1]), w >= 2 { e.widest = w; continue }
            if kv.count == 2, kv[0] == "fps", let f = Double(kv[1]), f > 0, f.isFinite { e.fps = f; continue }
            return (nil, "\(testEncoderVariable)=\(raw) ignored: it takes widest=PIXELS and fps=N, separated by commas.")
        }
        return (e, "Test encoder: \(raw) (\(testEncoderVariable)): the widest picture its hardware takes and the rate it carries the chosen size at, said, never measured.")
    }

    /// The one line beside a typed size and rate that this Mac cannot run at full size or full rate, nil when it can (or
    /// nothing is known): "This Mac’s video encoder takes at most 4096 pixels a side: Sill streams this scaled down to
    /// 4096 × 3072.", "This Mac streams this at about 48 frames a second.", or both in one sentence.
    package static func encoderNote(width: Int, height: Int, hz: Int, encoder e: Encoder) -> String? {
        if e.software { return "This Mac streams on its software encoder for now: at most 60 frames a second, at standard resolution." }
        var held: (width: Int, height: Int)?
        if let widest = e.widest, max(width, height) > widest { held = EncoderLimit.held(width: width, height: height, side: widest) }
        let slow = e.fps.flatMap { fps -> Int? in
            let shown = Int(fps.rounded(.down))
            return shown < min(hz == 0 ? 120 : hz, 120) - 2 ? shown : nil
        }
        switch (held, slow) {
        case let (h?, s?): return "This Mac’s video encoder takes at most \(e.widest ?? EncoderLimit.side) pixels a side: Sill streams this scaled down to \(h.width) × \(h.height), at about \(s) frames a second."
        case let (h?, nil): return "This Mac’s video encoder takes at most \(e.widest ?? EncoderLimit.side) pixels a side: Sill streams this scaled down to \(h.width) × \(h.height)."
        case let (nil, s?): return "This Mac streams this at about \(s) frames a second."
        default: return nil
        }
    }
}
