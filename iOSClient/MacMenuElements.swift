import UIKit
import StreamProtocol

/// The one builder of the Mac's menus as UIKit menu elements (docs/menu-bar-plan.md §7.3), for the
/// iPad's menu bar (SillAppDelegate, MacMenuBar) and for the Menus button's pull-down
/// (MacMenuButton): both run the same deferred elements, so a menu is fetched from the Mac when it
/// opens, and fresh every time. Main thread.
///
/// The probe measured what breaks the main menu: an inserted element whose shortcut, identifier or
/// action and property list equals one the root holds makes UIKit drop the whole insertion
/// silently, and duplicates among the inserted elements throw. So:
/// 1. No `UIKeyCommand` and no `UICommand`, ever: the leaves are `UIAction`s, and the Mac's
///    shortcut is only their subtitle. Nothing can then clash with the root's shortcuts or repeat,
///    and no key a user presses with nothing first responder (the keyboard down, the Settings panel
///    open) can reach a Mac menu. The Mac's shortcuts reach the Mac as keys, through InputOverlay.
/// 2. Identifiers only on the menus inserted in the bar (`barIdentifier`, from the Mac menu's id,
///    which MacMenuState keeps unique): every nested menu, action and deferred element, and the
///    pull-down's menus, get none, and UIKit makes unique ones. MacMenuBar inserts at most once per
///    build.
/// 3. Leaves press through the client, which sends the version the row came from. Handlers and
///    providers hold the client weakly: a window closed with its menu open leaves nothing behind.
/// 4. A disabled submenu is a disabled action without children: a disabled Mac menu cannot open.
/// 5. Every submenu holds exactly one uncached deferred element, whose provider asks the client
///    for the menu's current items (the placeholder covers the round trip) and is completed once,
///    on the main queue. A menu of the top level asks by the title it was built with when the top
///    level has moved since (MacMenuState rule 11): the bar is rebuilt lazily.
/// 6. Sections are untitled inline menus; a note, "No items" or "‹n› more on the Mac" is one
///    disabled action.
/// 7. Nothing here needs iOS 26.
enum MacMenuElements {
    /// The top level: one menu per Mac menu, each holding one deferred element. `barIdentifiers`:
    /// the iPad's bar, whose menus carry `barIdentifier`s and never change shape while stale (each
    /// then holds the note, from its deferred element). The pull-down (false) draws a stale or a
    /// disabled Mac menu as a disabled row, after the note, which is a section of its own: a dimmed
    /// line of words just above the dimmed menus would read as one more of them.
    static func topMenus(_ client: StreamClient, barIdentifiers: Bool) -> [UIMenuElement] {
        let state = client.menus
        guard let version = state.version else { return [] }
        var out: [UIMenuElement] = []
        if !barIdentifiers, let note = state.note {
            out.append(UIMenu(title: "", options: .displayInline, children: [noteAction(note)]))
        }
        for row in state.menus {
            guard let id = row.id else { continue }
            if !barIdentifiers, state.stale || !row.enabled {
                out.append(UIAction(title: row.title, attributes: .disabled) { _ in })
                continue
            }
            out.append(UIMenu(title: row.title, identifier: barIdentifiers ? barIdentifier(id) : nil,
                              children: [deferred(for: row, topLevelVersion: version, client: client)]))
        }
        return out
    }

    /// The one deferred element of the menu `row` opens: uncached, so its provider runs each time
    /// the menu opens, and asks the client for the menu's current items. `topLevelVersion`: the
    /// version of the top level `row` belongs to, when it is one of the Mac's menus (it asks by its
    /// title if the top level has moved since: rule 11); nil for a submenu of a fetched menu (it
    /// asks in the version its row came in).
    static func deferred(for row: MacMenuState.Row, topLevelVersion: Int?, client: StreamClient) -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { [weak client] completion in
            guard let client else { completion([noteAction(MacMenuState.notConnected)]); return }
            let done: (MacMenuState.Content) -> Void = { [weak client] content in
                completion(client.map { elements(content, client: $0) } ?? [noteAction(MacMenuState.notConnected)])
            }
            if let version = topLevelVersion, let id = row.id {
                client.fetchTopMenu(id: id, title: row.title, builtVersion: version, completion: done)
            } else {
                client.fetchMenu(row, completion: done)
            }
        }
    }

    /// A menu's contents once its fetch is settled.
    static func elements(_ content: MacMenuState.Content, client: StreamClient) -> [UIMenuElement] {
        switch content {
        case .message(let text):
            return [noteAction(text)]
        case .sections(let sections, _):
            return sections.map { section in
                UIMenu(title: "", options: .displayInline, children: section.map { element($0, client: client) })
            }
        }
    }

    /// The identifier of the bar's menu for the Mac menu `id` ("2"): unique within a build, since
    /// MacMenuState keeps each id of the top level once.
    static func barIdentifier(_ id: String) -> UIMenu.Identifier { UIMenu.Identifier("me.saffer.sill.macmenu.\(id)") }

    /// The `.one` layout's menu, which holds the Mac's menus (MacMenuBar).
    static let barWrapper = UIMenu.Identifier("me.saffer.sill.macmenu")

    /// Words in a menu: disabled, so they can never be chosen. A note that ends in a parenthesis,
    /// as the Mac's "Allow Accessibility for Sill on the Mac (System Settings › Privacy & Security ›
    /// Accessibility)." does, shows it as the subtitle: a menu cuts a long title short at its third
    /// line, and the part cut would be where to look.
    static func noteAction(_ text: String) -> UIAction {
        let body = text.hasSuffix(").") ? String(text.dropLast()) : text
        if body.hasSuffix(")"), let open = body.range(of: " (", options: .backwards) {
            let title = String(body[..<open.lowerBound])
            let subtitle = String(body[open.upperBound..<body.index(before: body.endIndex)])
            if !title.isEmpty, !subtitle.isEmpty {
                return UIAction(title: title + (text.hasSuffix(").") ? "." : ""), subtitle: subtitle, attributes: .disabled) { _ in }
            }
        }
        return UIAction(title: text, attributes: .disabled) { _ in }
    }

    private static func element(_ row: MacMenuState.Row, client: StreamClient) -> UIMenuElement {
        switch row.kind {
        case .note:
            return noteAction(row.title)
        case .item:
            let state: UIMenuElement.State
            switch row.mark {
            case .off: state = .off
            case .on: state = .on
            case .mixed: state = .mixed
            }
            return UIAction(title: row.title, subtitle: row.key, attributes: row.enabled ? [] : .disabled,
                            state: state) { [weak client] _ in client?.pressMenuItem(row) }
        case .submenu:
            guard row.enabled, row.id != nil else { return UIAction(title: row.title, attributes: .disabled) { _ in } }
            return UIMenu(title: row.title, children: [deferred(for: row, topLevelVersion: nil, client: client)])
        }
    }
}
