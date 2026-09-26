import Foundation
import ApplicationServices
import StreamProtocol

/// Accessibility reads and presses of one app's menu bar (docs/menu-bar-plan.md §4.3). Every call
/// runs on `queue`, never on the main actor or `sill.net`: an app's answer can take a second
/// (Blender: 6 ms a call; a hung app the whole timeout), and a press waits for the app's action.
/// Every element touched gets `timeout` before its first call (a local call, no IPC); the
/// process-wide default is never changed, as it would change the injector's and the sizer's too.
///
/// The reads, as the probe measured them (2026-09-25): the bar's items are `kAXMenuBarAttribute`'s
/// children, the first the Apple menu (13 of 13 apps), each with one AXMenu child whose children are
/// the items; hidden items are left out. Reading a menu's children makes the app validate it
/// (`menuNeedsUpdate:`, `menuWillOpen:`, `validateMenuItem:` for each item, `menuDidClose:`),
/// throttled by AppKit to about once a second per menu. A missing attribute comes back from
/// `AXUIElementCopyMultipleAttributeValues` as an AXValue holding an AX error, read here as nil
/// (nil title: missing; "" title: a separator's).
final class MenuReader: @unchecked Sendable {
    let queue = DispatchQueue(label: "sill.menus", qos: .userInitiated)
    static let timeout: Float = 1.0
    /// The bar's menus read, the Apple menu not counted.
    static let maxMenus = 32
    /// Items read of one menu; `total` counts the rest.
    static let maxItems = 500

    /// One item (or one of the bar's menus) as read, with its index among its menu's children and
    /// its element, which the mirror keeps for presses and for reading its submenu.
    struct Read: @unchecked Sendable {
        let item: RawMenuItem
        let index: Int
        let element: AXUIElement
    }

    enum Failure: Error, Equatable {
        /// AXIsProcessTrusted() false, or .apiDisabled.
        case notTrusted
        /// No AXMenuBar (a background-only app).
        case noMenuBar
        /// The process exited.
        case gone
        /// .cannotComplete after at least 0.9 × timeout.
        case notAnswering
        /// Any other error, by name (WindowSizer.axErrorName), or an id that names nothing.
        case failed(String)
    }

    struct Menu: @unchecked Sendable {
        let reads: [Read]
        /// All the menu's children, the ones past `maxItems` included.
        let total: Int
        let ms: Double
    }

    struct Pressed: Equatable {
        enum Outcome: Equatable {
            case pressed
            /// AXPress ran into the timeout: the action is running, often a modal dialog.
            case pressedNoAnswer
            case refused(MenuRefusal)
        }
        let outcome: Outcome
        /// The item's title as read at its path, when it was found again that way.
        let foundTitle: String?
    }

    // MARK: The bar

    /// The bar's menus but the Apple menu: [AXTitle, AXEnabled] of each, at most `maxMenus`.
    func topLevel(pid: pid_t) -> Result<(titles: [Read], ms: Double), Failure> {
        dispatchPrecondition(condition: .onQueue(queue))
        guard AXIsProcessTrusted() else { return .failure(.notTrusted) }
        let started = CFAbsoluteTimeGetCurrent()
        let bar: AXUIElement
        switch menuBar(pid: pid) {
        case .success(let b): bar = b
        case .failure(let f): return .failure(f)
        }
        let children: [AXUIElement]
        switch self.children(of: bar, pid: pid) {
        case .success(let c): children = c
        case .failure(let f): return .failure(f)
        }
        var reads: [Read] = []
        for (i, child) in children.enumerated() where i >= 1 && i <= Self.maxMenus {
            switch values(of: child, [kAXTitleAttribute, kAXEnabledAttribute], pid: pid) {
            case .success(let v):
                reads.append(Read(item: RawMenuItem(title: v[0] as? String, enabled: v[1] as? Bool), index: i, element: child))
            case .failure(let f):
                return .failure(f)
            }
        }
        return .success((reads, ms(since: started)))
    }

    // MARK: One menu

    private static let itemAttributes = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute,
                                         "AXMenuItemMarkChar", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers",
                                         "AXMenuItemCmdVirtualKey", "AXMenuItemCmdGlyph", kAXChildrenAttribute]

    /// The items of the menu at `path`: `parent` is its bar item or submenu item as kept from an
    /// earlier read, else (or when that one no longer answers) the path is walked from the bar. One
    /// `AXUIElementCopyMultipleAttributeValues` per item, no action names (every AXMenuItem has
    /// AXPress), and one more AXRole read of a titled item's first child.
    func items(pid: pid_t, of parent: AXUIElement?, path: MenuPath) -> Result<Menu, Failure> {
        dispatchPrecondition(condition: .onQueue(queue))
        guard AXIsProcessTrusted() else { return .failure(.notTrusted) }
        let started = CFAbsoluteTimeGetCurrent()
        var kids: [AXUIElement]? = nil
        if let parent {
            switch submenuItems(of: parent, pid: pid) {
            case .success(let k): kids = k
            case .failure(.failed): kids = nil          // no longer answering as it was (rebuilt): walk the path
            case .failure(let f): return .failure(f)
            }
        }
        if kids == nil {
            let element: AXUIElement
            switch walk(pid: pid, to: path) {
            case .success(let e): element = e
            case .failure(let f): return .failure(f)
            }
            switch submenuItems(of: element, pid: pid) {
            case .success(let k): kids = k
            case .failure(let f): return .failure(f)
            }
        }
        let all = kids ?? []
        var reads: [Read] = []
        for (i, item) in all.prefix(Self.maxItems).enumerated() {
            switch values(of: item, Self.itemAttributes, pid: pid) {
            case .failure(let f): return .failure(f)
            case .success(let v):
                guard (v[0] as? String) == kAXMenuItemRole else { continue }    // a menu lists only items; anything else is not one
                let children = (v[9] as? [AXUIElement]) ?? []
                var raw = RawMenuItem(title: v[1] as? String, description: v[2] as? String, enabled: v[3] as? Bool,
                                      mark: v[4] as? String, char: v[5] as? String, modifiers: (v[6] as? NSNumber)?.intValue,
                                      virtualKey: (v[7] as? NSNumber)?.intValue, glyph: (v[8] as? NSNumber)?.intValue,
                                      childCount: children.count)
                if let first = children.first, !MenuFormat.displayTitle(title: raw.title, description: raw.description).isEmpty {
                    AXUIElementSetMessagingTimeout(first, Self.timeout)
                    switch value(of: first, kAXRoleAttribute, pid: pid) {
                    case .success(let role): raw.firstChildRole = role as? String
                    case .failure(let f): return .failure(f)
                    }
                }
                reads.append(Read(item: raw, index: i, element: item))
            }
        }
        return .success(Menu(reads: reads, total: all.count, ms: ms(since: started)))
    }

    // MARK: Pressing

    /// AXPress on the kept element; when it is gone (the app built its menu again), the item at
    /// `path`, only if its title there is `shownTitle`. `PressDecision` decides. AXPress returns
    /// once the app has run the action: one that runs a modal loop holds it until the timeout,
    /// which counts as pressed.
    func press(pid: pid_t, element: AXUIElement?, path: MenuPath, shownTitle: String?) -> Pressed {
        dispatchPrecondition(condition: .onQueue(queue))
        guard AXIsProcessTrusted() else { return Pressed(outcome: .refused(.notTrusted), foundTitle: nil) }
        var target = element
        var elementValid = false
        var enabled: Bool? = nil
        var found: String? = nil
        if let element {
            AXUIElementSetMessagingTimeout(element, Self.timeout)
            switch value(of: element, kAXEnabledAttribute, pid: pid) {
            case .success(let v): elementValid = true; enabled = v as? Bool
            case .failure(.failed): elementValid = false            // no longer answering (rebuilt): found again below
            case .failure(let f): return Pressed(outcome: .refused(Self.refusal(f)), foundTitle: nil)
            }
        }
        if !elementValid {
            target = nil
            switch walk(pid: pid, to: path) {
            case .success(let e):
                switch values(of: e, [kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute], pid: pid) {
                case .success(let v):
                    target = e
                    found = MenuFormat.displayTitle(title: v[0] as? String, description: v[1] as? String)
                    enabled = v[2] as? Bool
                case .failure(.failed): break
                case .failure(let f): return Pressed(outcome: .refused(Self.refusal(f)), foundTitle: nil)
                }
            case .failure(.failed): break                           // nothing at that path now
            case .failure(let f): return Pressed(outcome: .refused(Self.refusal(f)), foundTitle: nil)
            }
        }
        switch PressDecision.decide(elementValid: elementValid, found: found, shown: shownTitle, enabled: enabled) {
        case .refuse(let why):
            return Pressed(outcome: .refused(why), foundTitle: found)
        case .press, .pressFound:
            guard let target else { return Pressed(outcome: .refused(.changed), foundTitle: found) }
            let started = CFAbsoluteTimeGetCurrent()
            let e = AXUIElementPerformAction(target, kAXPressAction as CFString)
            if e == .success { return Pressed(outcome: .pressed, foundTitle: found) }
            if e == .cannotComplete, CFAbsoluteTimeGetCurrent() - started >= Double(Self.timeout) * 0.9 {
                return Pressed(outcome: .pressedNoAnswer, foundTitle: found)
            }
            return Pressed(outcome: .refused(Self.refusal(failure(e, started: started, pid: pid))), foundTitle: found)
        }
    }

    static func refusal(_ f: Failure) -> MenuRefusal {
        switch f {
        case .notTrusted: .notTrusted
        case .noMenuBar: .changed
        case .gone: .gone
        case .notAnswering: .notAnswering
        case .failed(let name): .failed(name)
        }
    }

    // MARK: Accessibility, typed

    private func menuBar(pid: pid_t) -> Result<AXUIElement, Failure> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let started = CFAbsoluteTimeGetCurrent()
        var value: CFTypeRef?
        let e = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value)
        if e == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            let bar = value as! AXUIElement
            AXUIElementSetMessagingTimeout(bar, Self.timeout)
            return .success(bar)
        }
        if e == .success || e == .noValue || e == .attributeUnsupported {
            return .failure(Self.alive(pid) ? .noMenuBar : .gone)
        }
        return .failure(failure(e, started: started, pid: pid))
    }

    /// The bar item's or submenu item's menu (its first AXMenu child), and that menu's children.
    /// Reading them makes the app validate the menu.
    private func submenuItems(of element: AXUIElement, pid: pid_t) -> Result<[AXUIElement], Failure> {
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        let kids: [AXUIElement]
        switch children(of: element, pid: pid) {
        case .success(let k): kids = k
        case .failure(let f): return .failure(f)
        }
        for kid in kids {
            AXUIElementSetMessagingTimeout(kid, Self.timeout)
            switch value(of: kid, kAXRoleAttribute, pid: pid) {
            case .success(let role) where (role as? String) == kAXMenuRole:
                return children(of: kid, pid: pid)
            case .success: continue
            case .failure(let f): return .failure(f)
            }
        }
        return .failure(.failed("no menu"))
    }

    /// The element at `path`, from the bar: the bar's child at the first index, then each next index
    /// among the items of the one before's menu.
    private func walk(pid: pid_t, to path: MenuPath) -> Result<AXUIElement, Failure> {
        let bar: AXUIElement
        switch menuBar(pid: pid) {
        case .success(let b): bar = b
        case .failure(let f): return .failure(f)
        }
        var level: [AXUIElement]
        switch children(of: bar, pid: pid) {
        case .success(let c): level = c
        case .failure(let f): return .failure(f)
        }
        var element: AXUIElement? = nil
        for (depth, index) in path.indexes.enumerated() {
            if depth > 0, let parent = element {
                switch submenuItems(of: parent, pid: pid) {
                case .success(let k): level = k
                case .failure(let f): return .failure(f)
                }
            }
            guard index < level.count else { return .failure(.failed("no item at \(path.id)")) }
            element = level[index]
            AXUIElementSetMessagingTimeout(level[index], Self.timeout)
        }
        guard let element else { return .failure(.failed("no item at \(path.id)")) }
        return .success(element)
    }

    private func children(of element: AXUIElement, pid: pid_t) -> Result<[AXUIElement], Failure> {
        switch value(of: element, kAXChildrenAttribute, pid: pid) {
        case .success(let v): return .success((v as? [AXUIElement]) ?? [])
        case .failure(let f): return .failure(f)
        }
    }

    /// One attribute; nil for a missing one (NoValue, unsupported).
    private func value(of element: AXUIElement, _ attribute: String, pid: pid_t) -> Result<CFTypeRef?, Failure> {
        let started = CFAbsoluteTimeGetCurrent()
        var value: CFTypeRef?
        let e = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        switch e {
        case .success: return .success(value)
        case .noValue, .attributeUnsupported: return .success(nil)
        default: return .failure(failure(e, started: started, pid: pid))
        }
    }

    /// Several attributes in one call; a missing one (an AXValue holding an AX error, or CFNull) is nil.
    private func values(of element: AXUIElement, _ attributes: [String], pid: pid_t) -> Result<[CFTypeRef?], Failure> {
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        let started = CFAbsoluteTimeGetCurrent()
        var array: CFArray?
        let e = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &array)
        guard e == .success, let list = array as [AnyObject]? else { return .failure(failure(e, started: started, pid: pid)) }
        var out: [CFTypeRef?] = []
        for i in 0..<attributes.count {
            guard i < list.count else { out.append(nil); continue }
            let v = list[i] as CFTypeRef
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError {
                var error = AXError.success
                _ = AXValueGetValue(v as! AXValue, .axError, &error)
                // A timed-out app answers the whole call with .cannotComplete; an error inside the
                // array is one attribute's: missing (NoValue), or an element gone meanwhile.
                if error == .invalidUIElement { return .failure(failure(error, started: started, pid: pid)) }
                out.append(nil)
            } else if CFGetTypeID(v) == CFNullGetTypeID() {
                out.append(nil)
            } else {
                out.append(v)
            }
        }
        return .success(out)
    }

    /// An AX error as a Failure. A timeout is `.cannotComplete` after at least 0.9 × `timeout`; a quick
    /// one, or an invalid element, from a process that has exited is `.gone`.
    private func failure(_ e: AXError, started: CFAbsoluteTime, pid: pid_t) -> Failure {
        switch e {
        case .apiDisabled: return .notTrusted
        case .cannotComplete where CFAbsoluteTimeGetCurrent() - started >= Double(Self.timeout) * 0.9: return .notAnswering
        default: return Self.alive(pid) ? .failed(WindowSizer.axErrorName(e)) : .gone
        }
    }

    static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    private func ms(since started: CFAbsoluteTime) -> Double { (CFAbsoluteTimeGetCurrent() - started) * 1000 }
}
