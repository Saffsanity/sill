import CoreGraphics
import Foundation
import StreamProtocol

/// TEST ONLY: `SILL_TEST_DISPLAYS='Built-in Retina Display:1512x982@2:120:0,0;DELL U2723QE:2560x1440@1:60:1512,0'`
/// on a --synthetic host (docs/virtual-desktop-plan.md, "The CLI and the test hooks"): the stops it lists in
/// place of this Mac's displays (DesktopDisplays), the first of them its main display, each a name, its size
/// in points at a scale (1 or 2), its refresh rate in Hz (0: none reported) and its origin in global points.
/// The test pattern then shows the stop the Desktop is on, at its size and scale, with its number and name
/// drawn on it, its rate held to the stop's; kind 47 steps through them; input lands in each one's own
/// space (the dry run's log under SILL_TEST_INPUT_LOG); the window list's fields and the lines are as on a
/// real Mac. Nothing of this Mac's displays is read for it, and nothing is posted or warped. Honoured only by
/// a test host (`--synthetic`, and never Sill.app's own executable: DoorPolicy.isTestHost): anywhere else one
/// line says it is ignored.
enum DesktopDisplaysHook {
    static let variable = "SILL_TEST_DISPLAYS"

    /// A test stop: the display DesktopDisplays judges, and its pixel scale (the test pattern's size).
    struct Stop: Equatable {
        var display: DesktopDisplays.Display
        var scale: CGFloat
    }

    /// The stops a test host takes, and the one line it prints at start (nil when the variable is not set).
    static func read(testHost: Bool, environment: [String: String]) -> (stops: [Stop]?, line: String?) {
        guard let raw = environment[variable], !raw.isEmpty else { return (nil, nil) }
        guard testHost else { return (nil, "\(variable) ignored: only a --synthetic test host takes it, never Sill.app.") }
        guard let stops = parse(raw) else {
            return (nil, "\(variable) ignored: it takes NAME:WxH@SCALE:HZ:X,Y entries separated by ';', the first the main display.")
        }
        let words = stops.enumerated().map { i, s -> String in
            let d = s.display
            return "\(i + 1) \(d.name ?? "unnamed") \(Int(d.frame.width))×\(Int(d.frame.height)) pt @\(Int(s.scale))x, "
                + (d.refreshHz.map { "\(Int($0.rounded())) Hz" } ?? "no rate") + " at \(Int(d.frame.minX)),\(Int(d.frame.minY))"
        }
        return (stops, "Test displays: \(stops.count) in place of this Mac's (\(variable)): " + words.joined(separator: "; ") + ".")
    }

    /// Entries separated by ';', each NAME:WxH@SCALE:HZ:X,Y; IDs 101, 102… and UUIDs TEST-1, TEST-2… in the
    /// order given. Nil when any entry does not parse, a size is under 64 or over 8192 points, a scale is
    /// not 1 or 2, a rate is not 0 to 500, or there are none or more than 16.
    static func parse(_ raw: String) -> [Stop]? {
        var stops: [Stop] = []
        for (i, entry) in raw.split(separator: ";", omittingEmptySubsequences: true).enumerated() {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let sizeScale = parts[1].split(separator: "@")
            guard sizeScale.count == 2, let scale = Double(sizeScale[1]), scale == 1 || scale == 2 else { return nil }
            let wh = sizeScale[0].split(separator: "x")
            guard wh.count == 2, let w = Double(wh[0]), let h = Double(wh[1]), (64...8192).contains(w), (64...8192).contains(h) else { return nil }
            guard let hz = Double(parts[2]), (0...500).contains(hz) else { return nil }
            let xy = parts[3].split(separator: ",")
            guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]), abs(x) <= 65_536, abs(y) <= 65_536 else { return nil }
            let display = DesktopDisplays.Display(id: UInt32(101 + i), uuid: "TEST-\(i + 1)", frame: CGRect(x: x, y: y, width: w, height: h),
                                                  isSills: false, refreshHz: hz > 0 ? hz : nil, name: name.isEmpty ? nil : name)
            stops.append(Stop(display: display, scale: CGFloat(scale)))
        }
        guard !stops.isEmpty, stops.count <= 16 else { return nil }
        return stops
    }
}
