import SwiftUI
import UIKit

/// The bars' Menus button (docs/menu-bar-plan.md §7.5): the Mac's menus of the streamed app (the
/// Desktop's: the frontmost app's) as a pull-down, in every bar and every layout, whenever the Mac
/// sent menus (`MacMenuState.hasMenus`). The iPad's own menu bar shows the same menus on iPadOS 26
/// (SillAppDelegate); this is the way in everywhere else, on iPhone, on the Duo's outer display,
/// before iPadOS 26, and with the bar hidden.
///
/// The look is the bar's own BarButton, only drawn; the touch, the menu and VoiceOver belong to a
/// clear UIKit button over it (`MacMenuTrigger`). UIKit rather than SwiftUI's `Menu`, which has no
/// lazy element and no callback when a submenu opens: every Mac menu would have to be fetched ahead,
/// each validated by the app on the Mac, a round trip each, at every change of the tree. The UIKit
/// pull-down runs the same deferred elements as the iPad's bar (MacMenuElements).
struct MacMenuButton: View {
    @ObservedObject var client: StreamClient
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 16
    var iconSize: CGFloat = 22
    var spacing: CGFloat = 4
    /// Opening the pull-down puts the drawer, the Settings panel and a thumbnail's lights away: one
    /// thing open at a time. (While the Aa ruler is open the button is faded out and takes no touch.)
    let onOpen: () -> Void

    /// The pull-down shows: the button is drawn open (the accent), as the bar's buttons are.
    @State private var open = false

    /// The SF Symbol, where the system has it (SF Symbols 4); the plain menu glyph otherwise.
    static let symbol: String = UIImage(systemName: "filemenu.and.selection") != nil ? "filemenu.and.selection" : "menubar.rectangle"

    var body: some View {
        BarButton(open: open, width: width, height: height, radius: radius, accessibilityLabel: "", action: {}) {
            VStack(spacing: spacing) {
                Image(systemName: Self.symbol)
                    .font(.system(size: iconSize))
                    .foregroundStyle(open ? Palette.accent : Palette.text)
                Text("Menus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(open ? Palette.accent : Palette.barLabel)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            MacMenuTrigger(client: client, open: $open, onOpen: onOpen)
                .frame(width: width, height: height)
        }
    }
}

/// The clear UIKit button over the Menus button's look: `showsMenuAsPrimaryAction`, its menu the
/// Mac's top level (MacMenuElements, without the bar's identifiers), replaced whenever the top level
/// changes, and the accessible element, "‹App› menus".
struct MacMenuTrigger: UIViewRepresentable {
    @ObservedObject var client: StreamClient
    @Binding var open: Bool
    let onOpen: () -> Void

    final class Coordinator {
        /// The top level the button's menu was last built from.
        var built: MacMenuState.Top?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MacMenuTriggerButton {
        let button = MacMenuTriggerButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.backgroundColor = .clear
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        update(button, context: context)
        #if DEBUG
        button.openFromLaunchArguments(client: client)
        #endif
        return button
    }

    func updateUIView(_ button: MacMenuTriggerButton, context: Context) {
        update(button, context: context)
    }

    private func update(_ button: MacMenuTriggerButton, context: Context) {
        let binding = $open
        let onOpen = self.onOpen
        button.onOpenChange = { isOpen in
            // After the view update that UIKit's callback may land in.
            DispatchQueue.main.async {
                binding.wrappedValue = isOpen
                if isOpen { onOpen() }
            }
        }
        button.accessibilityLabel = "\(client.menus.app ?? "Mac") menus"
        let top = client.menus.top
        guard context.coordinator.built != top else { return }
        context.coordinator.built = top
        button.menu = UIMenu(children: MacMenuElements.topMenus(client, barIdentifiers: false))
    }
}

/// Reports when its pull-down shows and goes (UIButton is its own context-menu interaction's
/// delegate).
final class MacMenuTriggerButton: UIButton {
    var onOpenChange: ((Bool) -> Void)?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onOpenChange?(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onOpenChange?(false)
    }

    #if DEBUG
    /// The harness opens the pull-down once per launch.
    private static var opened = false

    /// `-SillMenusOpen 1`: the pull-down opens after launch, as a tap would open it
    /// (`performPrimaryAction`, iOS 17.4). `-SillMenusOpen 'File'` or `'Code/Settings'`: it opens on
    /// that menu's own items instead, each level fetched on the way as a tap on it would, so a
    /// photo shows what a tap on File shows (a headless run cannot tap).
    func openFromLaunchArguments(client: StreamClient) {
        guard !Self.opened, let raw = UserDefaults.standard.string(forKey: "SillMenusOpen"), !raw.isEmpty, raw != "0" else { return }
        Self.opened = true
        let path = raw == "1" ? [] : raw.split(separator: "/").map { String($0) }
        func open(after delay: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak client] in
                guard let self, let client else { return }
                guard let window = self.window, client.menus.version != nil else { open(after: 0.25); return }
                guard #available(iOS 17.4, *) else { print("menus: harness: -SillMenusOpen needs iOS 17.4"); return }
                // What a finger on the button's centre would reach: this button, unless something
                // drawn over it takes the touch (the harness cannot tap; this is the hit test a tap runs).
                let centre = self.convert(CGPoint(x: self.bounds.midX, y: self.bounds.midY), to: window)
                let hit = window.hitTest(centre, with: nil)
                print("menus: harness: a tap on the Menus button's centre reaches "
                      + (hit === self ? "the button" : hit.map { "a \(type(of: $0))" } ?? "nothing"))
                if path.isEmpty {
                    print("menus: harness: opening the pull-down")
                    self.performPrimaryAction()
                    return
                }
                client.resolveMenuPath(path) { [weak self, weak client] found in
                    guard let self, let client else { return }
                    guard let found, found.row.kind == .submenu else { print("menus: harness: no menu at \(path.joined(separator: " › "))"); return }
                    print("menus: harness: opening the pull-down on \(path.joined(separator: " › "))")
                    self.menu = UIMenu(title: found.row.title,
                                       children: [MacMenuElements.deferred(for: found.row, topLevelVersion: found.topLevelVersion, client: client)])
                    self.performPrimaryAction()
                }
            }
        }
        open(after: 0.8)
    }
    #endif
}
