// Look.swift — SHOTLIST §3: palette, type styles, easings and the motion recipes.
import AppKit
import SwiftUI

// MARK: - Canvas

enum Stage {
    static let width = 1920
    static let height = 1080
    static let size = CGSize(width: 1920, height: 1080)
    static let fps = 60
    static let frames = 4992                 // 83.2 s (v3: 52 bars at 150 BPM; v2 was 47 bars, 75.2 s)
    static let duration = 83.2
}

// MARK: - Easing (CSS cubic-bézier, solved per frame)

struct CubicBezier {
    let x1, y1, x2, y2: Double
    static let appleOut = CubicBezier(x1: 0.16, y1: 1, x2: 0.3, y2: 1)       // landings, snaps
    static let appleIn = CubicBezier(x1: 0.7, y1: 0, x2: 0.84, y2: 0)        // exits
    static let inOut = CubicBezier(x1: 0.45, y1: 0, x2: 0.2, y2: 1)          // glints, streak, fades
    static let push = CubicBezier(x1: 0.55, y1: 0, x2: 0.85, y2: 0.35)       // the accelerating dolly in S03
    static let linear = CubicBezier(x1: 0, y1: 0, x2: 1, y2: 1)

    private func sample(_ a1: Double, _ a2: Double, _ t: Double) -> Double {
        let c = 3 * a1, b = 3 * (a2 - a1) - c, a = 1 - c - b
        return ((a * t + b) * t + c) * t
    }
    private func slope(_ a1: Double, _ a2: Double, _ t: Double) -> Double {
        let c = 3 * a1, b = 3 * (a2 - a1) - c, a = 1 - c - b
        return (3 * a * t + 2 * b) * t + c
    }
    func callAsFunction(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x == 0 || x == 1 { return x }
        var t = x
        for _ in 0..<10 {
            let err = sample(x1, x2, t) - x
            if abs(err) < 1e-7 { return sample(y1, y2, t) }
            let d = slope(x1, x2, t)
            if abs(d) < 1e-7 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<60 {
            let v = sample(x1, x2, t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sample(y1, y2, t)
    }
}

@inline(__always) func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
@inline(__always) func lerp<T: BinaryFloatingPoint>(_ a: T, _ b: T, _ p: Double) -> T { a + (b - a) * T(p) }
/// 0→1 progress of an animation that starts at `start` and lasts `duration`, eased.
func ease(_ t: Double, _ start: Double, _ duration: Double, _ curve: CubicBezier = .appleOut) -> Double {
    guard duration > 0 else { return t >= start ? 1 : 0 }
    return curve((t - start) / duration)
}
/// Linear 0→1 over [a, b].
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { b <= a ? (t >= b ? 1 : 0) : clamp01((t - a) / (b - a)) }

// MARK: - Palette (§3.1)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}
extension CGColor {
    static func hex(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Palette {
    static let bg0: UInt32 = 0x000000
    static let bg1: UInt32 = 0x07080A
    static let accent: UInt32 = 0x9BB7FF
    static let text1: UInt32 = 0xF5F5F7
    static let text2: UInt32 = 0xA1A1A6
    static let text3: UInt32 = 0x6E6E73
    static let text4: UInt32 = 0x48484A
    static let lockSmall: UInt32 = 0x8E8E93
    static let deviceBody: UInt32 = 0x0C0D10
    static let rimLight: UInt32 = 0x6A6E76
    static let rimDark: UInt32 = 0x1C1E22
    static let cameraDot: UInt32 = 0x1E2024
    static let winLightBody: UInt32 = 0xF7F8FA
    static let winLightBars: UInt32 = 0x5A5F6B
    static let winDarkBody: UInt32 = 0x2A2F3A
    static let winDarkStrip: UInt32 = 0x3A3F4A
}

// MARK: - Type (§3.2)

struct TypeStyle {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let color: UInt32
    var monoDigits = false

    static let T0 = TypeStyle(size: 168, weight: .bold, tracking: -5.0, color: Palette.text1)
    // Proportional figures: SF's tabular "1" opens a visible gap in "120" at this size (as-built note).
    static let T0r = TypeStyle(size: 150, weight: .bold, tracking: -4.0, color: Palette.text1, monoDigits: false)
    static let T1 = TypeStyle(size: 128, weight: .bold, tracking: -3.2, color: Palette.text1)
    static let T1s = TypeStyle(size: 112, weight: .bold, tracking: -2.6, color: Palette.text1)
    static let T1c = TypeStyle(size: 100, weight: .bold, tracking: -2.2, color: Palette.text1)
    static let T2 = TypeStyle(size: 34, weight: .medium, tracking: -0.2, color: Palette.text2)
    /// Footnotes: 28 px in text.2 (they carry the off-by-default qualifiers, so they must read in 2 s).
    static let T3 = TypeStyle(size: 28, weight: .regular, tracking: 0, color: Palette.text2)
    static let W = TypeStyle(size: 148, weight: .semibold, tracking: -3.0, color: Palette.text1)
    static let T4 = TypeStyle(size: 56, weight: .medium, tracking: -0.8, color: Palette.text1)
    static let T5 = TypeStyle(size: 26, weight: .regular, tracking: 0, color: Palette.lockSmall)
    /// The legal line: 24 px (18 pt, "large" text) in text.3, 4.1:1 on black.
    static let T6 = TypeStyle(size: 24, weight: .regular, tracking: 0.1, color: Palette.text3)

    var font: Font {
        let f = Font.system(size: size, weight: weight)
        return monoDigits ? f.monospacedDigit() : f
    }
}

/// Copy. Typographic apostrophe (U+2019) and the non-breaking hyphen (U+2011) as the app spells "Wi‑Fi".
/// v2 (Noah's notes, 2026-09-25): his new lines keep his words and capitalisation; statements end with a
/// period as every statement in the reel does, and the lowercase continuation "with haptic trackpad" has none.
enum Copy {
    static let yourMacApps = "Your Mac apps."
    static let windowSill = ["On", "the", "window", "sill."]      // "sill." in accent
    static let anyWindow = "Any Mac window."
    static let oneTap = "One tap to switch."
    static let wholeDesktop = "Or the whole desktop."
    static let appDrawer = "App drawer", fromAfar = "from afar."
    static let textSize = "Text at the size you choose."
    static let click = "Click.", scroll = "Scroll.", type = "Type."
    static let haptic = ["with", "haptic", "trackpad"]              // "haptic" vibrates
    static let hapticFootnote = "Haptics on iPhone."
    /// "Full Screen." in title case, as the lights' own label spells it (the shot shows both side by side).
    static let close = "Close.", minimize = "Minimize.", fullScreen = "Full Screen."
    static let latency = "Latency you don\u{2019}t notice."
    static let latencySub = "Hardware\u{2011}encoded HEVC, straight to your iPad."
    static let upTo = "Up to "
    static let fps = " fps."
    static let proMotion = "On ProMotion displays."
    static let hidden = "Hidden on your Mac."
    static let stillLive = "Still live", onYourIPad = "on your iPad."
    /// The first cut's footnote with Noah's one change ("invisible display." → "invisible virtual display."),
    /// set on two lines so it clears the device.
    static let vdFootnote = ["With Virtual Display on, Sill streams the window", "from an invisible virtual display."]
    static let wifi = "Wi\u{2011}Fi.", wired = "Wired.", direct = "Direct."
    static let directSub = "Direct needs no shared network."
    static let directFootnote = "With Direct Wireless Connection on in Sill."
    /// v3 (Noah, 2026-09-25: "add the Tailscale connectivity and the Remote option"): the list goes on past
    /// "Direct." Remote Access is off by default (README L63), hence the footnote, as Direct's has one.
    static let orRemote = "Or remote,", throughVPN = "through your own VPN."
    static let remoteFootnote = "With Remote Access on in Sill."
    /// The pairing moment: the app's own words ("Pair once, and Sill reaches your Mac…", AddMacCard.swift;
    /// "lets in only the devices you pair", README L63–64).
    static let pairOnce = "Pair once."
    static let pairSub = "Remote Access lets in only the devices you pair."
    static let noSubscription = "No subscription."
    static let noServers = "No servers."
    static let wordmark = "Sill"
    static let freeOpen = "Free. Open source."
    static let small = "For iPhone and iPad, with a free Mac companion."
    static let duo = "Designed for iPhone Duo."
    static let duoSub = "Both screens. Coming soon."
    /// "Apple Pencil" left with S16; "iPhone Duo" joined with the tease card.
    static let legal = ["Mac, Mac mini, Mac Studio, MacBook Air, MacBook Pro, iPad, iPhone, iPhone Duo and ProMotion",
                        "are trademarks of Apple Inc., registered in the U.S. and other countries. Other names and apps shown belong to their owners."]
}
