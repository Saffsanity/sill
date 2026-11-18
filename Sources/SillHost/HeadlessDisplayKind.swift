import StreamProtocol

/// What Sill's Desktop display rules (HeadlessDesktopPolicy, VirtualDisplay.swift) make of a display: from its role,
/// as the Desktop's stops judge it (DesktopDisplays.role: its vendor and product, and the IDs the stage made this run),
/// never from its vendor alone. PR #200 took any display of Sill's vendor (0x5111) for Sill's Desktop display, so the
/// stage's display, which holds a picked window alone, could be the Desktop's on a Mac with no screen, and a stage
/// display just removed (its ID reads vendor 0xFFFFFFFF) counted as a real screen (the assessment of 2026-11-18,
/// defect 3). Here because VirtualDisplay.swift imports nothing of StreamProtocol (VirtualDisplayProbe compiles it
/// alone). Pure; checked by Tests/checks/virtual-display-api with VirtualDisplay.swift and DesktopDisplays.swift.
extension HeadlessDesktopPolicy {
    /// `online`: the display is there now (CGDisplayIsOnline); one that has gone is `.gone`, whatever it was.
    static func kind(_ role: DesktopDisplays.Role, online: Bool) -> Kind {
        guard online else { return .gone }
        switch role {
        case .screen: return .real
        case .sillDesktop: return .sills
        case .standIn: return .standIn
        case .stage: return .stage
        }
    }
}
