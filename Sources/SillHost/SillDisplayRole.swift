import StreamProtocol

/// What a display Sill makes is for, and who it is to macOS (docs/virtual-desktop-plan.md §1 and §9 as revised
/// 2026-11-18). Every display Sill makes has one of these roles, and SillDisplays holds at most one of each:
/// - `stage`: a picked window's own display (VirtualStage, Virtual Display). It holds that window alone, and is never one
///   of the Desktop's stops.
/// - `desktop`: the Desktop's own display. Today a Mac with no working screen's (PR #200, the "Headless display" lines);
///   phase 2b's Virtual Desktop is the same display, so there are never two.
///
/// macOS remembers a display's arrangement and mode by its vendor, product and serial, and DesktopDisplays.role tells
/// Sill's two displays apart by them, so a role's identity never changes: the stage's since milestone 3 ("Sill", vendor
/// 0x5111, product 0x0001, serial 1), the Desktop's since #200 ("Sill Desktop", product 0x0002, serial 2). The raw value
/// is the word DisplayMakeGuard's marker gives the role. Pure; checked by Tests/checks/sill-displays.
enum SillDisplayRole: String, CaseIterable {
    case stage
    case desktop

    /// The name System Settings › Displays shows for it.
    var name: String {
        switch self {
        case .stage: return "Sill"
        case .desktop: return "Sill Desktop"
        }
    }

    var vendor: UInt32 { DesktopDisplays.sillVendor }

    var product: UInt32 {
        switch self {
        case .stage: return DesktopDisplays.stageProduct
        case .desktop: return DesktopDisplays.desktopProduct
        }
    }

    var serial: UInt32 {
        switch self {
        case .stage: return 1
        case .desktop: return 2
        }
    }
}
