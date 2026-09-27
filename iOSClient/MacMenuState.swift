import Foundation
import StreamProtocol

/// One connection's view of the Mac's menus (kinds 24, 25 and 27; docs/menu-bar-plan.md §7.2): the
/// top level the Mac last sent, the menus this device asked for and waits on, the choices it sent,
/// and when a wait has lasted too long. Pure logic (Foundation and StreamProtocol, no UIKit), so it
/// is checked on its own (Tests/checks/menu-state, with mutants). StreamClient owns one on the main
/// thread and runs the completions it hands back; MacMenuElements turns what it holds into menus.
///
/// Each open menu is one completion, known here by a key (a UIKit provider's), settled exactly once:
/// by the answer to its fetch, at once when nothing may be asked, by the timeout, or by the end of
/// the connection. A key leaves the state when it is settled.
///
/// The rules:
/// 1. Nothing before the first top level: until one has arrived, for all this device knows, the
///    Mac is an older one. A menu opened then (only ever after a tear-down) is "Not connected.".
/// 2. A top level replaces the one before. A new version settles every waiting fetch of another
///    version with "The menus changed. Open the menu again.".
/// 3. One fetch per menu: opening a menu whose fetch is waiting joins it (UIKit may ask a provider
///    more than once), and one kind 27 goes out. It carries the title the menu was shown under: the
///    Mac reads the menu only while the item at its id still has that title.
/// 4. An answer settles only the fetch with its token. An unknown token is dropped: a late answer
///    after its timeout.
/// 5. An answer whose version is not the fetch's settles it with "The menus changed…". A menu
///    whose row came from another version than the current one is settled so at once, unasked:
///    its id is a place in an older tree.
/// 6. Timeout: `expire` settles a fetch that has waited the caller's timeout (max(4 s, 4 × the
///    worst recent round trip)) with "‹Mac› didn’t answer. Open the menu again.".
/// 7. Stale (the Mac reports the app not answering): no menu is fetched, each settles with the
///    note alone; an answer that is stale shows its rows, every one disabled, under the note.
/// 8. Presses: never for a disabled row, never before a top level; while stale, refused here with
///    the note, unsent. A `pressed: false` answer is a refusal to tell the user; `pressed: true`
///    is nothing: the Mac shows the result.
/// 9. `reset` (every tear-down) settles every waiting completion with "Not connected." and
///    empties everything; `connectionReplaced` (a move's hand-over) settles the waiting fetches,
///    whose answers come on the connection the session left, and keeps the top level.
/// 10. `sections`: separators split the items into sections, leading, trailing and doubled ones
///    dropped; an item without a title is dropped; a mark "-" or "–" is mixed, any other mark on;
///    `more > 0` adds a last disabled row "‹n› more on the Mac"; no rows at all, no note and
///    nothing more gives one disabled row, "No items". A stale answer or a refusal carries its
///    note and no items, and shows the note alone.
/// 11. A menu of the top level asks by what it showed: UIKit rebuilds the iPad's bar lazily (at
///    the next key event or focus change, measured), so a bar menu can have been built from an
///    older top level than the current one, even another session's: versions start again at each
///    launch of the Mac's host, so a reconnect, or another Mac, can reach the version it was built
///    in with other menus. So its own id only while the current top level's menu there has its
///    title; else the id of the current top level's first menu with the same title (the old app's
///    File finds the new app's File); with no such menu, none (`barMenuID`).
///
/// What the Mac sends is cleaned here as any text from the Mac is (SafeText): titles to 100
/// characters, shortcuts to 16, notes to 300. The top level keeps at most 32 menus, each with an id
/// of one part (1–4 digits, no leading zero) that no earlier menu has: the iPad's bar gives each an
/// identifier made from its id, and two equal identifiers in one build throw.
struct MacMenuState: Equatable {
    /// One row of a menu as the device draws it.
    struct Row: Equatable {
        enum Kind: Equatable { case item, submenu, note }
        enum Mark: Equatable { case off, on, mixed }
        var kind: Kind
        /// The Mac's id ("2.9"); nil for a note.
        var id: String?
        var title: String
        /// The Mac's shortcut as text ("⇧⌘S"), shown as the row's subtitle, never a key command.
        var key: String?
        var enabled: Bool
        var mark: Mark
        /// The tree version the row was sent in: its fetch or its choice carries it, so the Mac
        /// refuses one from an older tree instead of acting on whatever sits at that place now.
        var version: Int?

        init(kind: Kind, id: String? = nil, title: String, key: String? = nil, enabled: Bool = true,
             mark: Mark = .off, version: Int? = nil) {
            self.kind = kind; self.id = id; self.title = title; self.key = key
            self.enabled = enabled; self.mark = mark; self.version = version
        }

        /// A disabled row of words: a note, "No items", "‹n› more on the Mac".
        static func note(_ text: String) -> Row { Row(kind: .note, title: text, enabled: false) }
    }

    typealias Section = [Row]

    /// What an opened menu gets: its sections (`more`: how many items the Mac left out), or words
    /// of the device's own (a timeout, the menus changed, not connected).
    enum Content: Equatable {
        case sections([Section], more: Int)
        case message(String)
    }

    /// A completion's key, and what it gets.
    struct Done: Equatable {
        let key: Int
        let content: Content
    }

    /// A choice that was not made: the warning, the announcement and the console line.
    struct Refusal: Equatable {
        let title: String
        let id: String
        let note: String
        /// The Mac refused it (a `pressed: false` answer); false: never sent (stale here).
        let byMac: Bool
        var announcement: String { "Couldn’t choose \(title). \(note)" }
    }

    /// What `fetch` makes of an opened menu.
    enum Fetch: Equatable {
        /// A kind 27 to send; the completion waits for its answer.
        case send(FetchMenu)
        /// A fetch of the same menu waits already; the completion waits with it.
        case joined
        /// Settled at once, nothing sent.
        case settled(Content)
    }

    /// What `press` makes of a chosen row.
    enum Press: Equatable {
        case send(PressMenuItem)
        case refused(Refusal)
    }

    /// The top level as the bar and the Menus button draw it: a change here rebuilds the bar and
    /// replaces the button's menu.
    struct Top: Equatable {
        var version: Int?
        var app: String?
        var menus: [Row]
        var stale: Bool
        var note: String?
    }

    static let changedNote = "The menus changed. Open the menu again."
    static let notConnected = "Not connected."
    static let noItems = "No items"
    static func noAnswer(mac: String) -> String { "\(mac.isEmpty ? "The Mac" : mac) didn’t answer. Open the menu again." }
    static func moreOnTheMac(_ count: Int) -> String { "\(count) more on the Mac" }
    static let maxMenus = 32
    static let titleLimit = 100, keyLimit = 16, noteLimit = 300
    /// Choices waiting for their answer, at most (each is answered, or the connection ends).
    static let maxChoices = 16

    private(set) var version: Int?
    private(set) var app: String?
    /// The top level, each a `.submenu` row, in the Mac's order.
    private(set) var menus: [Row] = []
    private(set) var stale = false
    private(set) var note: String?

    /// Whether the Menus button shows: menus, or a note to show (no Accessibility on the Mac).
    var hasMenus: Bool { !menus.isEmpty || note != nil }
    var top: Top { Top(version: version, app: app, menus: menus, stale: stale, note: note) }

    private struct Waiting: Equatable {
        let id: String
        let title: String
        let version: Int
        let token: Int
        var keys: [Int]
        let sentAt: Double
    }
    /// The fetches sent and not answered yet, oldest first.
    private var waiting: [Waiting] = []

    private struct Choice: Equatable {
        let token: Int
        let id: String
        let title: String
    }
    /// The choices sent and not answered yet, oldest first.
    private var choices: [Choice] = []

    /// When the oldest waiting fetch was sent: the timeout's next look.
    var oldestWait: Double? { waiting.map(\.sentAt).min() }
    /// The completions waiting, joined ones included.
    var waitingKeys: [Int] { waiting.flatMap(\.keys) }

    // MARK: From the Mac

    /// A kind 24: a top level (it has `menus`), or the answer to one of this device's fetches or
    /// choices (by `answering`). Returns the completions it settles, whether the top level changed,
    /// and a refused choice.
    mutating func receive(_ m: MacMenu, now: Double) -> (done: [Done], topChanged: Bool, refusal: Refusal?) {
        if let items = m.menus {
            // Every kind 24 has its version; a top level without one says nothing this device can use.
            guard let v = m.version else { return ([], false, nil) }
            let before = top
            version = v
            app = Self.clean(m.app, limit: SafeText.labelLimit)
            stale = m.stale == true
            note = Self.clean(m.note, limit: Self.noteLimit)
            if stale, note == nil { note = "\(app ?? "The app") isn’t responding." }
            menus = Self.topRows(items, version: v)
            // Rule 2: what was asked of another tree is answered here.
            var done: [Done] = []
            waiting.removeAll { w in
                guard w.version != version else { return false }
                done += w.keys.map { Done(key: $0, content: .message(Self.changedNote)) }
                return true
            }
            return (done, top != before, nil)
        }
        guard let token = m.answering else { return ([], false, nil) }
        if let i = waiting.firstIndex(where: { $0.token == token }) {
            let w = waiting.remove(at: i)
            let content: Content
            if m.version != w.version {
                content = .message(Self.changedNote)          // rule 5
            } else {
                let more = max(0, m.more ?? 0)
                content = .sections(Self.sections(m.items ?? [], stale: m.stale == true, note: m.note, more: more,
                                                  version: w.version), more: more)
            }
            return (w.keys.map { Done(key: $0, content: content) }, false, nil)
        }
        if let i = choices.firstIndex(where: { $0.token == token }) {
            let c = choices.remove(at: i)
            guard m.pressed == false else { return ([], false, nil) }
            let note = Self.clean(m.note, limit: Self.noteLimit) ?? Self.changedNote
            return ([], false, Refusal(title: c.title, id: c.id, note: note, byMac: true))
        }
        return ([], false, nil)   // rule 4: a late answer, or a token this device never sent
    }

    // MARK: From the device

    /// A menu opened: the row's id and title, in the version the row came from. The kind 27 to
    /// send, a completion that joins one waiting, or what it gets at once (rules 1, 3, 5 and 7).
    mutating func fetch(_ id: String, title: String, version asked: Int?, key: Int, token: Int, now: Double) -> Fetch {
        guard let current = version else { return .settled(.message(Self.notConnected)) }
        guard asked == current else { return .settled(.message(Self.changedNote)) }
        if stale {
            return .settled(.sections(Self.sections([], stale: true, note: note, more: 0, version: current), more: 0))
        }
        if let i = waiting.firstIndex(where: { $0.id == id && $0.title == title && $0.version == current }) {
            waiting[i].keys.append(key)
            return .joined
        }
        waiting.append(Waiting(id: id, title: title, version: current, token: token, keys: [key], sentAt: now))
        return .send(FetchMenu(version: current, id: id, title: title, token: token))
    }

    /// Rule 11: the id a menu of the top level built as `builtID` under `title` asks for now: its
    /// own while the current top level's menu there has that title, else the current top level's
    /// first menu of that title; nil when there is none (or no top level).
    func barMenuID(builtID: String, title: String) -> String? {
        guard version != nil else { return nil }
        if menus.contains(where: { $0.id == builtID && $0.title == title }) { return builtID }
        return menus.first { $0.title == title }?.id
    }

    /// A row chosen: the kind 25 to send, carrying the version the row came from, or a refusal
    /// made here (stale). Nil for a row that cannot be chosen (disabled, not an item, before a top
    /// level): nothing happens.
    mutating func press(_ row: Row, token: Int) -> Press? {
        guard version != nil, row.kind == .item, row.enabled, let id = row.id, let v = row.version else { return nil }
        if stale { return .refused(Refusal(title: row.title, id: id, note: note ?? Self.changedNote, byMac: false)) }
        choices.append(Choice(token: token, id: id, title: row.title))
        if choices.count > Self.maxChoices { choices.removeFirst(choices.count - Self.maxChoices) }
        return .send(PressMenuItem(version: v, id: id, title: row.title, token: token))
    }

    /// Rule 6: every fetch that has waited `timeout` seconds or more.
    mutating func expire(now: Double, timeout: Double, mac: String) -> [Done] {
        var done: [Done] = []
        waiting.removeAll { w in
            guard now - w.sentAt >= timeout else { return false }
            done += w.keys.map { Done(key: $0, content: .message(Self.noAnswer(mac: mac))) }
            return true
        }
        return done
    }

    /// The connection ended: every waiting completion settles with "Not connected.", and nothing of
    /// the connection is kept.
    mutating func reset() -> [Done] {
        let done = waitingKeys.map { Done(key: $0, content: .message(Self.notConnected)) }
        self = MacMenuState()
        return done
    }

    /// A move handed the session to a new connection: what was asked on the old one is answered on
    /// the old one, which the session no longer reads. The waiting fetches settle with "The menus
    /// changed…", the choices' answers are gone (the Mac acts on them either way), and the top
    /// level stays (the same Mac; the new connection's subscription sends it again).
    mutating func connectionReplaced() -> [Done] {
        let done = waitingKeys.map { Done(key: $0, content: .message(Self.changedNote)) }
        waiting = []
        choices = []
        return done
    }

    // MARK: Rows

    /// A menu's items as rows in sections (rule 10), every row disabled when `stale`, each carrying
    /// `version`.
    static func sections(_ items: [MacMenuItem], stale: Bool, note: String?, more: Int, version: Int?) -> [Section] {
        var out: [Section] = []
        if let note = clean(note, limit: noteLimit) { out.append([.note(note)]) }
        var section: Section = []
        for item in items {
            if item.separator == true {
                if !section.isEmpty { out.append(section) }
                section = []
                continue
            }
            guard let title = clean(item.title, limit: titleLimit) else { continue }
            let kind: Row.Kind = item.submenu == true ? .submenu : .item
            section.append(Row(kind: kind, id: item.id, title: title,
                               key: kind == .item ? clean(item.key, limit: keyLimit) : nil,
                               enabled: item.enabled != false && !stale && item.id != nil,
                               mark: mark(item.mark), version: version))
        }
        if !section.isEmpty { out.append(section) }
        if more > 0 { out.append([.note(moreOnTheMac(more))]) }
        if out.isEmpty { out = [[.note(noItems)]] }
        return out
    }

    /// The Mac's mark: "-" or "–" mixed, any other on, none off.
    static func mark(_ raw: String?) -> Row.Mark {
        guard let m = clean(raw, limit: 1) else { return .off }
        return m == "-" || m == "–" ? .mixed : .on
    }

    /// The top level's rows: those with a title and an id of one part that no earlier menu has,
    /// at most 32.
    static func topRows(_ items: [MacMenuItem], version: Int?) -> [Row] {
        var rows: [Row] = []
        var ids = Set<String>()
        for item in items where rows.count < maxMenus {
            guard let id = item.id, isTopID(id), !ids.contains(id),
                  let title = clean(item.title, limit: titleLimit) else { continue }
            ids.insert(id)
            rows.append(Row(kind: .submenu, id: id, title: title, enabled: item.enabled != false, version: version))
        }
        return rows
    }

    /// One of the bar's menus: 1–4 ASCII digits, no leading zero (the Apple menu, 0, is never sent).
    static func isTopID(_ id: String) -> Bool {
        guard (1...4).contains(id.count), id.first != "0" else { return false }
        return id.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `text` as one line (SafeText) of at most `limit` characters; nil when nothing is left.
    static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let s = SafeText.label(text, limit: limit)
        return s.isEmpty ? nil : s
    }
}
