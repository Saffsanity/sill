import Foundation
// MacMenuState (iOSClient/MacMenuState.swift), docs/menu-bar-plan.md §7.2: its eleven rules case by
// case, then a random model of a session's events in which every completion must be settled exactly
// once. Compiled with Sources/StreamProtocol and the file (its `import StreamProtocol` dropped) by
// build.sh.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

typealias S = MacMenuState
typealias Row = MacMenuState.Row
let changed = "The menus changed. Open the menu again."

func top(_ v: Int?, _ titles: [String], app: String? = "Code", stale: Bool? = nil, note: String? = nil,
         answering: Int? = nil, disabled: Set<Int> = []) -> MacMenu {
    MacMenu(version: v, app: app, bundleID: "com.microsoft.VSCode",
            menus: titles.enumerated().map { MacMenuItem(id: "\($0.offset + 1)", title: $0.element,
                                                        enabled: disabled.contains($0.offset + 1) ? false : nil, submenu: true) },
            answering: answering, stale: stale, note: note)
}
func answer(_ v: Int, token: Int, menu: String = "2", _ items: [MacMenuItem], more: Int? = nil, stale: Bool? = nil,
            note: String? = nil) -> MacMenu {
    MacMenu(version: v, answering: token, menu: menu, items: items, more: more, stale: stale, note: note)
}
func pressed(_ v: Int, token: Int, _ ok: Bool, note: String? = nil) -> MacMenu {
    MacMenu(version: v, answering: token, pressed: ok, note: note)
}
func item(_ id: String, _ title: String?, key: String? = nil, enabled: Bool? = nil, mark: String? = nil,
          submenu: Bool? = nil) -> MacMenuItem {
    MacMenuItem(id: id, title: title, enabled: enabled, mark: mark, key: key, submenu: submenu)
}
let sep = MacMenuItem(separator: true)
let code = ["Code", "File", "Edit", "Selection", "View", "Go", "Run", "Terminal", "Window", "Help"]
let fileItems = [item("2.0", "New Text File", key: "⌘N"), item("2.1", "New File…", key: "⌃⌥⌘N"), sep,
                 item("2.3", "Open Recent", submenu: true), sep, item("2.5", "Save", key: "⌘S"),
                 item("2.6", "Auto Save", mark: "✓"), item("2.7", "Revert File", enabled: false)]
func titles(_ c: S.Content) -> [[String]] {
    guard case .sections(let s, _) = c else { return [] }
    return s.map { $0.map(\.title) }
}
func rows(_ c: S.Content) -> [Row] {
    guard case .sections(let s, _) = c else { return [] }
    return s.flatMap { $0 }
}
func keys(_ done: [S.Done]) -> [Int] { done.map(\.key) }

// MARK: Rule 1: nothing before the first top level

do {
    var s = S()
    check(!s.hasMenus && s.version == nil && s.menus.isEmpty, "a new state has nothing")
    check(s.fetch("2", version: nil, key: 1, token: 1, now: 0) == .settled(.message("Not connected.")), "a fetch before any top level is settled at once")
    check(s.fetch("2", version: 3, key: 2, token: 2, now: 0) == .settled(.message("Not connected.")), "…whatever its version")
    check(s.waitingKeys.isEmpty && s.oldestWait == nil, "nothing waits before a top level")
    check(s.press(Row(kind: .item, id: "2.5", title: "Save", version: 3), token: 3) == nil, "no choice before a top level")
    let r = s.receive(answer(3, token: 1, fileItems), now: 0)
    check(r.done.isEmpty && !r.topChanged && r.refusal == nil, "an answer before a top level settles nothing")
    check(s.barMenuID(builtID: "2", builtVersion: 3, title: "File") == nil, "no bar id without a top level")
}

// MARK: The top level

do {
    var s = S()
    let r = s.receive(top(3, code), now: 0)
    check(r.topChanged && r.done.isEmpty && r.refusal == nil, "the first top level changes the top")
    check(s.version == 3 && s.app == "Code" && s.menus.map(\.title) == code, "the top level as sent")
    check(s.menus.map(\.id) == (1...10).map { "\($0)" }, "the menus' ids")
    check(s.menus.allSatisfy { $0.kind == .submenu && $0.enabled && $0.version == 3 && $0.key == nil && $0.mark == .off }, "each a submenu of version 3")
    check(s.hasMenus && !s.stale && s.note == nil, "menus to show, not stale")
    check(!s.receive(top(3, code), now: 1).topChanged, "the same top level again changes nothing")
    check(s.receive(top(3, code + ["More"]), now: 1).topChanged, "another title changes the top")
    check(s.receive(top(3, code, app: "Code 2"), now: 1).topChanged, "another app name changes the top")
    check(s.receive(top(3, code, disabled: [2]), now: 1).topChanged && s.menus[1].enabled == false, "a disabled menu changes the top, and stays disabled")
    check(s.receive(top(4, code), now: 1).topChanged && s.version == 4, "a new version changes the top")
    check(!s.receive(top(nil, ["X"]), now: 1).topChanged && s.version == 4 && s.menus.count == 10, "a top level without a version is ignored")
    let none = s.receive(MacMenu(version: 5, menus: []), now: 2)
    check(none.topChanged && !s.hasMenus && s.app == nil && s.menus.isEmpty, "no menus: no button")
    _ = s.receive(MacMenu(version: 6, app: "Code", menus: [], note: "Allow Accessibility for Sill on the Mac (System Settings › Privacy & Security › Accessibility)."), now: 3)
    check(s.hasMenus && s.menus.isEmpty && s.note?.hasPrefix("Allow Accessibility") == true, "a note alone shows the button")
    check(s.top == S.Top(version: 6, app: "Code", menus: [], stale: false, note: s.note), "the top's snapshot")
}

// The top level's ids: one part, 1–4 digits, no leading zero, unique; at most 32 menus; titles cleaned.
do {
    var s = S()
    let odd = [MacMenuItem(id: "0", title: "Apple", submenu: true), MacMenuItem(id: "01", title: "Zero", submenu: true),
               MacMenuItem(id: "1.2", title: "Deep", submenu: true), MacMenuItem(id: "12345", title: "Long", submenu: true),
               MacMenuItem(id: "a", title: "Letter", submenu: true), MacMenuItem(id: "٣", title: "Arabic digit", submenu: true),
               MacMenuItem(id: "", title: "Empty", submenu: true), MacMenuItem(id: nil, title: "No id", submenu: true),
               MacMenuItem(id: "2", title: "File", submenu: true), MacMenuItem(id: "2", title: "File again", submenu: true),
               MacMenuItem(id: "3", title: " \u{202E} ", submenu: true), MacMenuItem(id: "4", title: nil, submenu: true),
               MacMenuItem(id: "9999", title: "Last", submenu: true), MacMenuItem(id: "5", title: "Fi\nle\u{200B}", submenu: true)]
    _ = s.receive(MacMenu(version: 2, menus: odd), now: 0)
    check(s.menus.map(\.id) == ["2", "9999", "5"], "only valid, unique ids with a title: \(s.menus.map { $0.id ?? "nil" })")
    check(s.menus.map(\.title) == ["File", "Last", "Fi le"], "titles cleaned: \(s.menus.map(\.title))")
    let forty = (1...40).map { MacMenuItem(id: "\($0)", title: "Menu \($0)", submenu: true) }
    _ = s.receive(MacMenu(version: 3, menus: forty), now: 0)
    check(s.menus.count == 32 && s.menus.last?.id == "32", "at most 32 menus")
    _ = s.receive(MacMenu(version: 4, app: "  Co\u{202E}de\n", menus: [MacMenuItem(id: "1", title: String(repeating: "x", count: 150), submenu: true)]), now: 0)
    check(s.app == "Code" && s.menus[0].title.count == 100, "the app's name and a long title cleaned")
    _ = s.receive(MacMenu(version: 5, app: " \n", menus: []), now: 0)
    check(s.app == nil, "an app name that cleans to nothing is none")
    check(S.isTopID("1") && S.isTopID("32") && S.isTopID("9999") && !S.isTopID("0") && !S.isTopID("007")
          && !S.isTopID("10000") && !S.isTopID("-1") && !S.isTopID("1 ") && !S.isTopID("²"), "isTopID")
}

// MARK: Fetches: sent, joined, answered (rules 3, 4, 5)

do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    check(s.fetch("2", version: 3, key: 1, token: 10, now: 1) == .send(FetchMenu(version: 3, id: "2", token: 10)), "a fetch is sent with the version and its token")
    check(s.fetch("2", version: 3, key: 2, token: 11, now: 1.1) == .joined, "the same menu again joins the waiting fetch")
    check(s.fetch("3", version: 3, key: 3, token: 12, now: 1.2) == .send(FetchMenu(version: 3, id: "3", token: 12)), "another menu is its own fetch")
    check(s.waitingKeys == [1, 2, 3] && s.oldestWait == 1, "three completions wait, the oldest sent at 1")
    let r = s.receive(answer(3, token: 10, fileItems), now: 1.3)
    check(keys(r.done) == [1, 2] && !r.topChanged && r.refusal == nil, "the answer settles both completions of its fetch")
    check(r.done.count == 2 && r.done[0].content == r.done[1].content, "…with the same content")
    let fileTitles = r.done.first.map { titles($0.content) } ?? []
    check(fileTitles == [["New Text File", "New File…"], ["Open Recent"], ["Save", "Auto Save", "Revert File"]], "File's sections: \(fileTitles)")
    check(s.waitingKeys == [3], "only the other menu still waits")
    check(s.receive(answer(3, token: 10, fileItems), now: 1.4).done.isEmpty, "the same token again settles nothing (rule 4)")
    check(s.receive(answer(3, token: 99, fileItems), now: 1.4).done.isEmpty, "an unknown token settles nothing")
    check(s.fetch("2", version: 3, key: 4, token: 13, now: 2) == .send(FetchMenu(version: 3, id: "2", token: 13)), "once answered, the menu is asked again")
    let other = s.receive(MacMenu(version: 4, answering: 13, menu: "2", items: [], note: changed), now: 2.1)
    check(keys(other.done) == [4] && other.done[0].content == .message(changed), "an answer of another version: the menus changed (rule 5)")
    check(s.fetch("2", version: 2, key: 5, token: 14, now: 3) == .settled(.message(changed)), "a row of an older version is settled unasked")
    check(s.waitingKeys == [3], "and does not wait")
    let late = s.receive(answer(3, token: 12, [item("3.0", "Undo", key: "⌘Z")]), now: 3)
    check(keys(late.done) == [3] && titles(late.done[0].content) == [["Undo"]], "the other menu's answer")
    check(s.waitingKeys.isEmpty && s.oldestWait == nil, "nothing waits")
}

// A new top level settles what was asked of another version (rule 2).
do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    _ = s.fetch("2", version: 3, key: 1, token: 1, now: 0)
    _ = s.fetch("5", version: 3, key: 2, token: 2, now: 0)
    _ = s.fetch("5", version: 3, key: 3, token: 3, now: 0)
    let same = s.receive(top(3, code), now: 0.5)
    check(same.done.isEmpty && s.waitingKeys == [1, 2, 3], "the same version again settles nothing")
    let staleSame = s.receive(top(3, code, stale: true, note: "Code isn’t responding."), now: 0.6)
    check(staleSame.done.isEmpty && staleSame.topChanged && s.waitingKeys == [1, 2, 3], "a stale top level of the same version leaves the fetches to their answers")
    let r = s.receive(top(4, ["Blender", "Window"], app: "Blender"), now: 1)
    check(Set(keys(r.done)) == [1, 2, 3] && r.done.allSatisfy { $0.content == .message(changed) } && r.topChanged, "a new version: every waiting fetch, the menus changed")
    check(s.waitingKeys.isEmpty && !s.stale && s.note == nil, "nothing waits; the new top level is not stale")
    check(s.receive(answer(3, token: 1, fileItems), now: 1.1).done.isEmpty, "the old fetch's answer is dropped")
}

// MARK: Rule 11: a bar menu asks by what it showed

do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    check(s.barMenuID(builtID: "2", builtVersion: 3, title: "File") == "2", "built from the current version: its own id")
    _ = s.receive(top(5, ["Safari", "Edit", "File", "Edit"], app: "Safari"), now: 1)
    check(s.barMenuID(builtID: "2", builtVersion: 3, title: "File") == "3", "built from version 3: the new app's File")
    check(s.barMenuID(builtID: "3", builtVersion: 3, title: "Edit") == "2", "the first menu of that title")
    check(s.barMenuID(builtID: "4", builtVersion: 3, title: "Selection") == nil, "a title the new top level lacks: none")
    check(s.barMenuID(builtID: "1", builtVersion: 4, title: "Code") == nil, "built from any other version: by title")
    check(s.barMenuID(builtID: "7", builtVersion: 5, title: "Anything") == "7", "built from version 5: its own id, whatever its title")
}

// MARK: Rule 6: the timeout

do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    _ = s.fetch("2", version: 3, key: 1, token: 1, now: 10)
    _ = s.fetch("2", version: 3, key: 2, token: 1, now: 11)
    _ = s.fetch("3", version: 3, key: 3, token: 2, now: 12)
    check(s.expire(now: 13.99, timeout: 4, mac: "Mac mini").isEmpty, "not before 4 s")
    let e = s.expire(now: 14, timeout: 4, mac: "Mac mini")
    check(keys(e) == [1, 2] && e.allSatisfy { $0.content == .message("Mac mini didn’t answer. Open the menu again.") }, "at 4 s exactly, the fetch and the one that joined it")
    check(s.waitingKeys == [3] && s.oldestWait == 12, "the later fetch still waits")
    check(s.expire(now: 19.99, timeout: 8, mac: "").isEmpty, "a longer timeout (a slow link)")
    check(s.expire(now: 20, timeout: 8, mac: "") == [S.Done(key: 3, content: .message("The Mac didn’t answer. Open the menu again."))], "no name: The Mac")
    check(s.receive(answer(3, token: 1, fileItems), now: 21).done.isEmpty, "an answer after its timeout is dropped")
    check(s.expire(now: 100, timeout: 4, mac: "x").isEmpty, "nothing twice")
}

// MARK: Rule 7: stale

do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    let r = s.receive(top(3, code, stale: true, note: "Code isn’t responding."), now: 0)
    check(r.topChanged && s.stale && s.note == "Code isn’t responding." && s.hasMenus, "a stale top level")
    let f = s.fetch("2", version: 3, key: 1, token: 1, now: 0)
    check(f == .settled(.sections([[Row.note("Code isn’t responding.")]], more: 0)), "a menu opened while stale holds the note alone, unasked")
    check(s.waitingKeys.isEmpty, "nothing was sent")
    let choice = s.press(Row(kind: .item, id: "2.5", title: "Save", version: 3), token: 2)
    check(choice == .refused(S.Refusal(title: "Save", id: "2.5", note: "Code isn’t responding.", byMac: false)), "a choice while stale is refused here")
    _ = s.receive(top(3, code, stale: true), now: 1)
    check(s.note == "Code isn’t responding.", "a stale top level without a note gets one of its own")
    _ = s.receive(top(3, code, app: nil, stale: true), now: 1)
    check(s.note == "The app isn’t responding.", "…without the app's name")
    _ = s.receive(top(3, code), now: 2)
    check(!s.stale && s.note == nil, "answering again: not stale")
    check(s.fetch("2", version: 3, key: 3, token: 3, now: 2) == .send(FetchMenu(version: 3, id: "2", token: 3)), "and asked again")
    let a = s.receive(answer(3, token: 3, fileItems, stale: true, note: "Code isn’t responding."), now: 2.1)
    check(a.done.count == 1, "a stale answer settles its fetch")
    let rs = a.done.first.map { rows($0.content) } ?? []
    check(rs.first == Row.note("Code isn’t responding.") && rs.count == 7 && rs.allSatisfy { !$0.enabled }, "a stale answer: its rows, every one disabled, under the note")
}

// MARK: Rule 8: choices

do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    let save = Row(kind: .item, id: "2.5", title: "Save", key: "⌘S", version: 3)
    check(s.press(save, token: 20) == .send(PressMenuItem(version: 3, id: "2.5", title: "Save", token: 20)), "a choice carries its version, id, title and token")
    check(s.press(Row(kind: .item, id: "2.7", title: "Revert File", enabled: false, version: 3), token: 21) == nil, "a disabled row: nothing")
    check(s.press(Row(kind: .submenu, id: "2.3", title: "Open Recent", version: 3), token: 22) == nil, "a submenu: nothing")
    check(s.press(Row.note("No items"), token: 23) == nil, "a note: nothing")
    check(s.press(Row(kind: .item, id: nil, title: "Untitled", version: 3), token: 24) == nil, "no id: nothing")
    check(s.press(Row(kind: .item, id: "2.5", title: "Save", version: nil), token: 25) == nil, "no version: nothing")
    check(s.press(Row(kind: .item, id: "2.5", title: "Save", version: 2), token: 26) == .send(PressMenuItem(version: 2, id: "2.5", title: "Save", token: 26)),
          "a row of an older version goes with that version, for the Mac to refuse")
    check(s.receive(pressed(3, token: 20, true), now: 1).refusal == nil, "pressed: nothing to tell")
    let refused = s.receive(pressed(4, token: 26, false, note: changed), now: 1)
    check(refused.refusal == S.Refusal(title: "Save", id: "2.5", note: changed, byMac: true) && refused.done.isEmpty && !refused.topChanged, "a refusal")
    check(refused.refusal?.announcement == "Couldn’t choose Save. The menus changed. Open the menu again.", "the announcement's words")
    check(s.receive(pressed(4, token: 26, false, note: changed), now: 1).refusal == nil, "one refusal per choice")
    _ = s.press(save, token: 27)
    check(s.receive(pressed(3, token: 27, false), now: 2).refusal?.note == changed, "a refusal without a note: the menus changed")
    _ = s.press(save, token: 28)
    check(s.receive(pressed(3, token: 28, false, note: "It isn’t available right now."), now: 2).refusal?.note == "It isn’t available right now.", "the Mac's note")
    _ = s.press(save, token: 29)
    check(s.receive(MacMenu(version: 3, answering: 29), now: 2).refusal == nil, "an answer that says nothing refuses nothing")
    for t in 100..<120 { _ = s.press(save, token: t) }
    check(s.receive(pressed(3, token: 100, false), now: 3).refusal == nil, "the oldest choices are forgotten past 16")
    check(s.receive(pressed(3, token: 119, false), now: 3).refusal != nil, "the newest is kept")
}

// MARK: Rule 9: reset and the move's hand-over

do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    _ = s.fetch("2", version: 3, key: 1, token: 1, now: 0)
    _ = s.fetch("2", version: 3, key: 2, token: 1, now: 0)
    _ = s.fetch("4", version: 3, key: 3, token: 2, now: 0)
    _ = s.press(Row(kind: .item, id: "2.5", title: "Save", version: 3), token: 3)
    let d = s.reset()
    check(keys(d).sorted() == [1, 2, 3] && d.allSatisfy { $0.content == .message("Not connected.") }, "reset settles every waiting completion: Not connected.")
    check(s == S(), "reset empties everything")
    check(s.reset().isEmpty, "a second reset settles nothing")
    check(s.receive(answer(3, token: 1, fileItems), now: 1).done.isEmpty, "an answer after the reset is dropped")
    check(s.receive(pressed(3, token: 3, false), now: 1).refusal == nil, "and so is a refusal")
    check(s.fetch("2", version: 3, key: 4, token: 4, now: 1) == .settled(.message("Not connected.")), "after a reset: rule 1 again")

    var m = S()
    _ = m.receive(top(3, code), now: 0)
    _ = m.fetch("2", version: 3, key: 1, token: 1, now: 0)
    _ = m.fetch("2", version: 3, key: 2, token: 1, now: 0)
    _ = m.press(Row(kind: .item, id: "2.5", title: "Save", version: 3), token: 2)
    let moved = m.connectionReplaced()
    check(keys(moved) == [1, 2] && moved.allSatisfy { $0.content == .message(changed) }, "a hand-over settles the waiting fetches: the menus changed")
    check(m.version == 3 && m.menus.count == 10 && m.waitingKeys.isEmpty, "…and keeps the top level")
    check(m.receive(pressed(3, token: 2, false), now: 1).refusal == nil, "…and forgets the choices")
    check(m.fetch("2", version: 3, key: 3, token: 3, now: 1) == .send(FetchMenu(version: 3, id: "2", token: 3)), "a menu opened after it is asked on the new connection")
}

// MARK: Rule 10: rows and sections

do {
    let v = 7
    func secs(_ items: [MacMenuItem], stale: Bool = false, note: String? = nil, more: Int = 0) -> [[String]] {
        S.sections(items, stale: stale, note: note, more: more, version: v).map { $0.map(\.title) }
    }
    let a = item("1.0", "A"), b = item("1.1", "B"), c = item("1.2", "C")
    check(secs([sep, a, sep, sep, b, sep]) == [["A"], ["B"]], "leading, doubled and trailing separators dropped")
    check(secs([a, b, sep, c]) == [["A", "B"], ["C"]], "a separator splits")
    check(secs([a, sep, item("1.2", nil), item("1.3", " \n\u{202E}"), sep, b]) == [["A"], ["B"]], "items without a title dropped, and their separators collapse")
    check(secs([]) == [["No items"]], "no items: No items")
    check(secs([sep, sep]) == [["No items"]], "only separators: No items")
    check(secs([], note: changed) == [[changed]], "a refusal: the note alone")
    check(secs([], more: 5) == [["5 more on the Mac"]], "nothing read but more on the Mac: that row alone")
    check(secs([a, b], more: 100) == [["A", "B"], ["100 more on the Mac"]], "more: a last row")
    check(secs([a], note: "Blender isn’t responding.", more: 3) == [["Blender isn’t responding."], ["A"], ["3 more on the Mac"]], "the note first, then the items, then more")
    let all = S.sections([a, item("1.1", "Sub", key: "⌘K", submenu: true), item("1.2", "Off", enabled: false),
                          item("1.3", "No id").with(id: nil), item("1.4", "Keyed", key: "  ⇧⌘S \n")],
                         stale: false, note: nil, more: 0, version: v)
    let flat = all.flatMap { $0 }
    check(flat.map(\.kind) == [.item, .submenu, .item, .item, .item], "kinds")
    check(flat.map(\.enabled) == [true, true, false, false, true], "enabled unless the Mac said false, or no id")
    check(flat[1].key == nil && flat[4].key == "⇧⌘S", "a submenu has no shortcut; a shortcut cleaned")
    check(flat.allSatisfy { $0.version == v }, "every row carries the version")
    check(S.sections([a, b], stale: true, note: nil, more: 0, version: v).flatMap { $0 }.allSatisfy { !$0.enabled }, "stale: every row disabled")
    let notes = S.sections([], stale: false, note: "x", more: 2, version: v).flatMap { $0 }
    check(notes.allSatisfy { $0.kind == .note && !$0.enabled && $0.id == nil && $0.version == nil }, "notes are disabled rows without an id")
    check(S.mark("✓") == .on && S.mark("-") == .mixed && S.mark("–") == .mixed && S.mark("•") == .on && S.mark("◆") == .on, "marks")
    check(S.mark(nil) == .off && S.mark("") == .off && S.mark(" ") == .off, "no mark: off")
    check(S.sections([item("1.0", "M", mark: "-")], stale: false, note: nil, more: 0, version: v)[0][0].mark == .mixed, "a mixed row")
    let long = S.sections([item("1.0", String(repeating: "é", count: 120), key: String(repeating: "⌘", count: 30))],
                          stale: false, note: String(repeating: "n", count: 400), more: 0, version: v)
    check(long[0][0].title.count == 300 && long[1][0].title.count == 100 && long[1][0].key?.count == 16, "notes 300, titles 100, shortcuts 16 characters")
}

// An answer's content: its sections and how many more.
do {
    var s = S()
    _ = s.receive(top(3, code), now: 0)
    _ = s.fetch("9", version: 3, key: 1, token: 1, now: 0)
    let window = (0..<500).map { item("9.\($0)", "Window \($0)") }
    let r = s.receive(answer(3, token: 1, menu: "9", window, more: 100), now: 0.2)
    guard case .sections(let sections, let more)? = r.done.first?.content else { check(false, "the long menu's content"); exit(1) }
    check(more == 100 && sections.count == 2 && sections[0].count == 500 && sections[1] == [Row.note("100 more on the Mac")], "500 rows and 100 more on the Mac")
    _ = s.fetch("9", version: 3, key: 2, token: 2, now: 1)
    let neg = s.receive(answer(3, token: 2, menu: "9", [], more: -4), now: 1)
    check(neg.done.first?.content == .sections([[Row.note("No items")]], more: 0), "a negative more counts as none")
}

// MARK: A random model of sessions

/// A small deterministic generator (splitmix64).
struct Gen {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
}

var modelRuns = 0, modelEvents = 0
for seed in 0..<5_000 {
    var g = Gen(state: UInt64(seed) &* 7919 &+ 17)
    var s = S()
    var now = 0.0
    var nextKey = 1, nextToken = 1
    var issued = Set<Int>()                 // completions handed to the state
    var settled: [Int: Int] = [:]           // key → times settled
    var sentAt: [Int: (id: String, version: Int, at: Double)] = [:]   // token → the fetch it sent
    var openFetch: [String: Int] = [:]      // "id@version" → token, while it waits (what the model expects)
    var choiceTokens: [Int: String] = [:]   // token → title
    var version = 0
    var ok = true
    func settle(_ done: [S.Done], _ why: String) {
        for d in done {
            if !issued.contains(d.key) { ok = false; print("FAIL: seed \(seed): \(why) settled key \(d.key), never issued") }
            settled[d.key, default: 0] += 1
            if settled[d.key]! > 1 { ok = false; print("FAIL: seed \(seed): \(why) settled key \(d.key) twice") }
        }
    }
    let steps = 20 + g.int(80)
    for _ in 0..<steps {
        modelEvents += 1
        now += Double(g.int(1500)) / 1000
        switch g.int(10) {
        case 0, 1:   // a top level: the same version or a new one, sometimes stale, sometimes no menus
            if version == 0 || g.chance(0.5) { version += 1 }
            let count = g.int(4)
            let titles = (0..<count).map { ["File", "Edit", "View", "Window"][($0 + g.int(2)) % 4] }
            let r = s.receive(top(version, titles, stale: g.chance(0.2) ? true : nil), now: now)
            settle(r.done, "a top level")
            for (k, t) in openFetch where !k.hasSuffix("@\(version)") { openFetch[k] = nil; sentAt[t] = nil }
        case 2, 3, 4:   // a menu opened, of the current version or an older one
            guard version > 0 else { break }
            let id = "\(1 + g.int(3))" + (g.chance(0.3) ? ".\(g.int(3))" : "")
            let v = g.chance(0.85) ? version : version - 1
            let key = nextKey; nextKey += 1
            issued.insert(key)
            let token = nextToken
            let expected = openFetch["\(id)@\(v)"]
            switch s.fetch(id, version: v, key: key, token: token, now: now) {
            case .send(let f):
                nextToken += 1
                if expected != nil { ok = false; print("FAIL: seed \(seed): a second kind 27 for \(id)@\(v) while one waits") }
                if f.token != token || f.id != id || f.version != v || v != s.version { ok = false; print("FAIL: seed \(seed): the kind 27 \(f)") }
                openFetch["\(id)@\(v)"] = token
                sentAt[token] = (id, v, now)
            case .joined:
                if expected == nil { ok = false; print("FAIL: seed \(seed): joined with nothing waiting for \(id)@\(v)") }
            case .settled(let content):
                settle([S.Done(key: key, content: content)], "a fetch settled at once")
                if v == s.version, !s.stale { ok = false; print("FAIL: seed \(seed): a current, answering menu settled unasked") }
            }
        case 5, 6:   // the Mac answers one waiting fetch (or a token it never had), in its version or a newer one
            let tokens = Array(sentAt.keys).sorted()
            let token = tokens.isEmpty || g.chance(0.1) ? 10_000 + g.int(100) : tokens[g.int(tokens.count)]
            let v = sentAt[token]?.version ?? version
            let answerVersion = g.chance(0.85) ? v : v + 1
            let r = s.receive(answer(answerVersion, token: token, menu: sentAt[token]?.id ?? "1",
                                     [item("1.0", "A"), sep, item("1.2", "B", enabled: g.chance(0.5) ? false : nil)],
                                     more: g.chance(0.2) ? 5 : nil), now: now)
            settle(r.done, "an answer")
            if let f = sentAt[token] {
                openFetch["\(f.id)@\(f.version)"] = nil
                sentAt[token] = nil
                if answerVersion != f.version, r.done.contains(where: { $0.content != .message(changed) }) {
                    ok = false; print("FAIL: seed \(seed): an answer of another version was shown")
                }
            } else if !r.done.isEmpty {
                ok = false; print("FAIL: seed \(seed): an unknown token settled something")
            }
        case 7:   // the timeout
            let timeout = 4.0
            let r = s.expire(now: now, timeout: timeout, mac: "Mac mini")
            settle(r, "the timeout")
            for (t, f) in sentAt where now - f.at >= timeout { sentAt[t] = nil; openFetch["\(f.id)@\(f.version)"] = nil }
            if let oldest = s.oldestWait, now - oldest >= timeout { ok = false; print("FAIL: seed \(seed): a fetch outlived its timeout") }
        case 8:   // a choice, and sometimes its answer
            guard version > 0 else { break }
            let token = nextToken
            let row = Row(kind: .item, id: "1.\(g.int(3))", title: "Item \(g.int(9))", enabled: g.chance(0.8), version: g.chance(0.8) ? version : version - 1)
            switch s.press(row, token: token) {
            case .send(let p)?:
                nextToken += 1
                if !row.enabled || s.stale || p.version != row.version { ok = false; print("FAIL: seed \(seed): the choice \(p) of \(row)") }
                choiceTokens[token] = row.title
            case .refused(let r)?:
                if !s.stale || r.byMac { ok = false; print("FAIL: seed \(seed): refused here while not stale") }
            case nil:
                if row.enabled && s.version != nil { ok = false; print("FAIL: seed \(seed): an enabled row not sent") }
            }
            if let (t, title) = choiceTokens.first, g.chance(0.5) {
                let r = s.receive(pressed(version, token: t, false, note: "It isn’t available right now."), now: now)
                choiceTokens[t] = nil
                if r.refusal != nil, r.refusal?.title != title { ok = false; print("FAIL: seed \(seed): a refusal for another choice") }
            }
        default:   // the connection ends, or a move hands the session over
            if g.chance(0.5) {
                settle(s.reset(), "the reset")
                if s != S() { ok = false; print("FAIL: seed \(seed): reset left something") }
                version = 0
            } else {
                settle(s.connectionReplaced(), "the hand-over")
            }
            openFetch = [:]; sentAt = [:]; choiceTokens = [:]
        }
        // What waits is exactly what was issued and not settled.
        let open = issued.filter { settled[$0] == nil }
        if Set(s.waitingKeys) != open { ok = false; print("FAIL: seed \(seed): waiting \(s.waitingKeys.sorted()) but open \(open.sorted())"); break }
        if !ok { break }
    }
    settle(s.reset(), "the last reset")
    if issued.contains(where: { settled[$0] != 1 }) { ok = false; print("FAIL: seed \(seed): a completion was not settled exactly once") }
    check(ok, "random session \(seed)")
    modelRuns += 1
}
print("model: \(modelRuns) random sessions, \(modelEvents) events, every completion settled exactly once")

extension MacMenuItem {
    func with(id: String?) -> MacMenuItem { var c = self; c.id = id; return c }
}

print(failures == 0 ? "menu-state: all \(checks) checks passed" : "menu-state: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
