import Foundation

/// The Home Screen icon of Sill for iPhone and iPad, the person's choice in Settings, beside the app's version
/// (Noah, 2026-11-18; docs/app-icons-plan.md). Every icon is compiled into the app, an Icon Composer document
/// in Packaging/ that the system draws in Liquid Glass: iOS changes an app's icon only to one its bundle
/// declares (`UIApplication.setAlternateIconName`), so a choice is one of these cases, never a picture from
/// anywhere else.
///
/// - `original`: design/AppIcon.svg's iMac with the iPad tilted in front, `Packaging/AppIcon.icon`, the app's
///   primary icon (ASSETCATALOG_COMPILER_APPICON_NAME, Sill for Mac's too): what a new install shows, first in
///   Settings and always there, so the original is one tap away.
/// - `community`: grub-basket's design from pull request #386, `Packaging/AppIconCommunity.icon`, an alternate
///   icon (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES), credited to its author by login.
///
/// A later icon is one more case, its document, its preview (Scripts/app-icon-previews.sh) and its name in the
/// project's alternates; Tests/checks/app-icon says which of them is missing. Sill for Mac keeps the original
/// alone: macOS gives an app no way to change its own icon.
///
/// iOS keeps the alternate's name across launches and updates (`UIApplication.alternateIconName`). A name this
/// build does not ship reads as the original, which iOS shows then, and choosing the original clears it. Each
/// change is the person's own tap, which iOS confirms with its alert; nothing here changes the icon by itself
/// (App Review guideline 4.6).
///
/// Pure: Foundation only, checked in Tests/checks/app-icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case original
    case community

    var id: String { rawValue }

    /// What a new install shows, and what a name this build does not know reads as: the primary icon.
    static let standard = AppIconChoice.original

    /// The icon's name in the build, its document's in Packaging (`<iconName>.icon`) and the name iOS knows it by.
    var iconName: String {
        switch self {
        case .original: return "AppIcon"
        case .community: return "AppIconCommunity"
        }
    }

    /// What `UIApplication.setAlternateIconName` takes for it: nil for the primary icon (the original), the
    /// icon's name for an alternate.
    var alternateIconName: String? { self == Self.standard ? nil : iconName }

    /// The alternates, in Settings' order: exactly what the project's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES
    /// lists (Tests/checks/app-icon reads it), so each one can be set and none ships unseen.
    static var alternateIconNames: [String] { allCases.compactMap(\.alternateIconName) }

    /// The image set in Assets.xcassets that Settings shows it with: its document's Default look, rendered by
    /// Scripts/app-icon-previews.sh.
    var previewImageName: String { iconName + "Preview" }

    /// Who made it, by GitHub login, for its credit; nil for Sill's own.
    var author: String? {
        switch self {
        case .original: return nil
        case .community: return "grub-basket"
        }
    }

    /// Settings' word for it, under its picture.
    var title: String {
        switch self {
        case .original: return "Original"
        case .community: return "Community"
        }
    }

    /// The credit under its word, "by grub-basket"; nil for Sill's own.
    var credit: String? { author.map { "by \($0)" } }

    /// VoiceOver's words for it: "Original icon", "Community icon, by grub-basket".
    var spoken: String { "\(title) icon" + (credit.map { ", \($0)" } ?? "") }

    // MARK: Which icon shows, and what a tap asks of iOS

    /// The choice the Home Screen shows, from iOS's alternate icon name (nil: the primary). A name none of these
    /// choices has (an icon a later build added and this one lacks, or a test build's) reads as the original:
    /// iOS shows the primary icon when the alternate is not in the bundle.
    static func current(alternateIconName name: String?) -> AppIconChoice {
        guard let name else { return standard }
        return allCases.first { $0.alternateIconName == name } ?? standard
    }

    /// What a tap on a choice asks of iOS.
    enum Request: Equatable {
        /// Nothing: that icon is set already (no call, no alert).
        case none
        /// `setAlternateIconName` with this name (nil: the primary icon).
        case set(String?)
    }

    /// What a tap on `choice` asks of iOS while its alternate icon name is `name`: nothing when that very icon is
    /// set, else its name. Judged against the name itself, not the choice it reads as, so Original clears a name
    /// this build does not ship.
    static func request(_ choice: AppIconChoice, from name: String?) -> Request {
        choice.alternateIconName == name ? .none : .set(choice.alternateIconName)
    }

    /// Whether Settings shows the App Icon group: only where iOS can change this app's icon
    /// (`UIApplication.supportsAlternateIcons`, false when the bundle declares no alternate) and there is more
    /// than one icon to choose from.
    static func offered(supportsAlternateIcons: Bool) -> Bool {
        supportsAlternateIcons && allCases.count > 1
    }

    // MARK: Words

    enum Copy {
        /// The group's title, over the pictures.
        static let title = "App Icon"

        /// Under the pictures: what the choice changes, and the way back.
        static func footnote(device: String) -> String {
            "The icon Sill shows on this \(device)’s Home Screen. \(AppIconChoice.standard.title) is always here to switch back to."
        }

        /// A tile's hint for VoiceOver: what choosing it does, or that it shows already.
        static func hint(selected: Bool) -> String {
            selected ? "Sill’s icon now." : "Changes Sill’s icon on the Home Screen to this one."
        }

        /// Under the pictures, orange, when iOS did not change the icon.
        static let failed = "Sill’s icon didn’t change. Try again in a moment."
    }
}
