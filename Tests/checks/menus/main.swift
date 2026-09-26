import Foundation
// H3 (menus), docs/menu-bar-plan.md §10: the wire's kinds 24, 25 and 27 and their JSON
// (Sources/StreamProtocol/MacMenu.swift). Compiled with Sources/StreamProtocol as one module
// (build.sh), with -package-name sill.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") } else { print("ok   \(what())") }
}
func json(_ text: String) -> Data { Data(text.utf8) }
func keys<T: Encodable>(_ value: T) -> Set<String> {
    (try? JSONSerialization.jsonObject(with: Wire.encode(value)) as? [String: Any]).map { Set($0.keys) } ?? []
}

// MARK: - Kinds

func header(_ kind: UInt8) -> StreamHeader? {
    var d = Data([kind]); d.append(Data(count: 8)); d.append(0); d.append(contentsOf: [0, 0, 0, 0])
    return StreamMessage.parseHeader(d)
}
check(StreamMessageKind.macMenu.rawValue == 24 && StreamMessageKind.pressMenuItem.rawValue == 25
      && StreamMessageKind.fetchMenu.rawValue == 27, "kinds: macMenu 24, pressMenuItem 25, fetchMenu 27")
check(header(24)?.kind == .macMenu && header(25)?.kind == .pressMenuItem && header(27)?.kind == .fetchMenu,
      "kinds 24, 25 and 27 parse")
check(header(26)?.kind == .unknown, "kind 26 (the Mac's pointer, another branch) is unknown here")
check(header(23)?.kind == .hello && header(22)?.kind == .goodbye, "kinds 22 and 23 unchanged")
let m24 = StreamMessage(kind: .macMenu, timestamp: 1, isKeyframe: false, payload: Wire.encode(MacMenu(version: 3, menus: [])))
check(StreamMessage.parseHeader(m24.serialized())?.kind == .macMenu
      && StreamMessage.parseHeader(m24.serialized())?.payloadLength == Wire.encode(MacMenu(version: 3, menus: [])).count,
      "a kind 24 serializes and its header parses")

// MARK: - JSON: every field optional, nil left out, unknown keys ignored

check(Wire.decode(MacMenu.self, from: json("{}")) == MacMenu(), "MacMenu: {} decodes to all nil")
check(Wire.decode(MacMenuItem.self, from: json("{}")) == MacMenuItem(), "MacMenuItem: {} decodes to all nil")
check(Wire.decode(FetchMenu.self, from: json("{}")) == FetchMenu(), "FetchMenu: {} decodes to all nil")
check(Wire.decode(PressMenuItem.self, from: json("{}")) == PressMenuItem(), "PressMenuItem: {} decodes to all nil")
check(String(data: Wire.encode(MacMenu()), encoding: .utf8) == "{}", "MacMenu(): encodes as {}")
check(keys(MacMenu(version: 5, menus: [])) == ["version", "menus"], "a top level without menus: only version and menus")
check(keys(MacMenuItem(separator: true)) == ["separator"], "a separator: only separator")
check(keys(MacMenuItem(id: "2.14", title: "Revert File", enabled: false)) == ["id", "title", "enabled"],
      "a disabled item: id, title, enabled")
let full = MacMenu(version: 3, app: "Code", bundleID: "com.microsoft.VSCode",
                   menus: [MacMenuItem(id: "1", title: "Code", submenu: true)], answering: 7, menu: "2",
                   items: [MacMenuItem(id: "2.0", title: "New Text File", key: "⌘N"), MacMenuItem(separator: true),
                           MacMenuItem(id: "2.12", title: "Auto Save", mark: "✓"),
                           MacMenuItem(id: "2.14", title: "Revert File", enabled: false)],
                   more: 12, pressed: false, stale: true, note: "Code isn’t responding.")   // distinct values: no field stands in for another
check(Wire.decode(MacMenu.self, from: Wire.encode(full)) == full, "MacMenu: a full one round-trips")
// The initializers set each field from its own argument: built, then against the JSON written by hand.
check(MacMenu(version: 1, app: "a", bundleID: "b", menus: [], answering: 2, menu: "m", items: [], more: 3,
              pressed: false, stale: true, note: "n")
      == Wire.decode(MacMenu.self, from: json(#"{"version":1,"app":"a","bundleID":"b","menus":[],"answering":2,"menu":"m","items":[],"more":3,"pressed":false,"stale":true,"note":"n"}"#)),
      "MacMenu's init sets every field from its own argument")
check(MacMenuItem(id: "1.2", title: "t", separator: false, enabled: true, mark: "✓", key: "⌘K", submenu: false)
      == Wire.decode(MacMenuItem.self, from: json(#"{"id":"1.2","title":"t","separator":false,"enabled":true,"mark":"✓","key":"⌘K","submenu":false}"#)),
      "MacMenuItem's init sets every field from its own argument")
check(FetchMenu(version: 4, id: "2", token: 9) == Wire.decode(FetchMenu.self, from: json(#"{"version":4,"id":"2","token":9}"#))
      && PressMenuItem(version: 4, id: "2.9", title: "Save", token: 10)
         == Wire.decode(PressMenuItem.self, from: json(#"{"version":4,"id":"2.9","title":"Save","token":10}"#)),
      "FetchMenu's and PressMenuItem's inits set every field from its own argument")
check(keys(full) == ["version", "app", "bundleID", "menus", "answering", "menu", "items", "more", "pressed", "stale", "note"],
      "MacMenu's keys are the plan's: version app bundleID menus answering menu items more pressed stale note")
let item = MacMenuItem(id: "3.4.1", title: "Save", separator: false, enabled: true, mark: "-", key: "⇧⌘S", submenu: false)
check(Wire.decode(MacMenuItem.self, from: Wire.encode(item)) == item, "MacMenuItem: a full one round-trips")
check(keys(item) == ["id", "title", "separator", "enabled", "mark", "key", "submenu"],
      "MacMenuItem's keys: id title separator enabled mark key submenu")
let fetch = FetchMenu(version: 3, id: "2", token: 2)
check(Wire.decode(FetchMenu.self, from: Wire.encode(fetch)) == fetch && keys(fetch) == ["version", "id", "token"],
      "FetchMenu: round-trips; keys version id token")
check(keys(FetchMenu(token: 1)) == ["token"], "the subscription: only token")
let press = PressMenuItem(version: 3, id: "2.9", title: "Save", token: 3)
check(Wire.decode(PressMenuItem.self, from: Wire.encode(press)) == press && keys(press) == ["version", "id", "title", "token"],
      "PressMenuItem: round-trips; keys version id title token")
check(Wire.decode(MacMenu.self, from: json(#"{"version":3,"x":1,"menus":[{"id":"1","title":"File","submenu":true,"y":[1]}],"z":{"a":1}}"#))
      == MacMenu(version: 3, menus: [MacMenuItem(id: "1", title: "File", submenu: true)]),
      "unknown keys are ignored, at both levels")
check(Wire.decode(FetchMenu.self, from: json(#"{"token":1,"later":"field"}"#)) == FetchMenu(token: 1), "FetchMenu ignores unknown keys")
check(Wire.decode(PressMenuItem.self, from: json(#"{"id":"4.0","token":2,"alt":true}"#)) == PressMenuItem(id: "4.0", token: 2),
      "PressMenuItem ignores unknown keys")
check(Wire.decode(MacMenu.self, from: json(#"{"version":"3"}"#)) == nil, "a retyped field fails the decode (why fields are never retyped)")

// The plan's §3.4 examples, as a device and a host read them.
let examples: [(String, Bool)] = [
    (#"{"token":1}"#, false),
    (#"{"version":3,"answering":1,"app":"Code","bundleID":"com.microsoft.VSCode","menus":[{"id":"1","title":"Code","submenu":true},{"id":"2","title":"File","submenu":true},{"id":"3","title":"Edit","submenu":true},{"id":"10","title":"Help","submenu":true}]}"#, true),
    (#"{"version":3,"id":"2","token":2}"#, false),
    (#"{"version":3,"answering":2,"menu":"2","items":[{"id":"2.0","title":"New Text File","key":"⌘N"},{"id":"2.1","title":"New File…","key":"⌃⌥⌘N"},{"separator":true},{"id":"2.3","title":"Open Recent","submenu":true},{"id":"2.9","title":"Save","key":"⌘S"},{"id":"2.12","title":"Auto Save","mark":"✓"},{"id":"2.14","title":"Revert File","enabled":false}]}"#, true),
    (#"{"version":3,"id":"2.9","title":"Save","token":3}"#, false),
    (#"{"version":3,"answering":3,"pressed":true}"#, true),
    (#"{"version":4,"answering":4,"pressed":false,"note":"The menus changed. Open the menu again."}"#, true),
    (#"{"version":4,"app":"Blender","bundleID":"org.blenderfoundation.blender","menus":[],"stale":true,"note":"Blender isn’t responding."}"#, true),
    (#"{"version":5,"menus":[]}"#, true),
]
for (text, host) in examples {
    let ok = host ? Wire.decode(MacMenu.self, from: json(text)) != nil
                  : (Wire.decode(FetchMenu.self, from: json(text)) != nil && Wire.decode(PressMenuItem.self, from: json(text)) != nil)
    check(ok, "§3.4 example decodes: \(text.prefix(60))…")
}
if let answer = Wire.decode(MacMenu.self, from: json(examples[3].0)) {
    check(answer.answering == 2 && answer.menu == "2" && answer.items?.count == 7 && answer.items?[2].separator == true
          && answer.items?[6].enabled == false && answer.items?[5].mark == "✓" && answer.items?[1].key == "⌃⌥⌘N",
          "the File example: 7 items, the separator third, Revert File disabled, Auto Save marked")
} else { check(false, "the File example decodes") }
if let refusal = Wire.decode(MacMenu.self, from: json(examples[6].0)) {
    check(refusal.pressed == false && refusal.note == "The menus changed. Open the menu again.", "the refusal example")
} else { check(false, "the refusal example decodes") }

// Size: 500 items (the cap) with 100-character titles of 4-byte characters and 16-character keys
// stay far under the device's cap for a host message.
let long = String(repeating: "𝔐", count: 100), wide = String(repeating: "⌘", count: 16)
let big = MacMenu(version: 1, answering: 1, menu: "4.21",
                  items: (0..<500).map { MacMenuItem(id: "4.21.\($0)", title: long, enabled: false, mark: "✓", key: wide, submenu: true) },
                  more: 100)
let bigSize = Wire.encode(big).count
check(bigSize < StreamMessage.maxOtherHostPayload / 8, "500 items of 100 wide characters: \(bigSize) bytes, under an eighth of the 4 MiB cap")

// MARK: - MenuFormat.shortcut: every row of the plan's §4.1 tables

typealias F = MenuFormat
func sc(_ char: String? = nil, _ mods: Int? = 0, vk: Int? = nil, glyph: Int? = nil) -> String? {
    F.shortcut(char: char, modifiers: mods, virtualKey: vk, glyph: glyph)
}
// The character table, each with ⌘ (modifiers 0).
let charRows: [(String, String)] = [("\u{8}", "⌫"), ("\u{7f}", "⌫"), ("\u{1b}", "⎋"), ("\r", "↩"), ("\u{3}", "⌤"), ("\t", "⇥"),
                                     (" ", "Space"), ("\u{F700}", "↑"), ("\u{F701}", "↓"), ("\u{F702}", "←"), ("\u{F703}", "→"),
                                     ("\u{F728}", "⌦"), ("\u{F729}", "↖"), ("\u{F72B}", "↘"), ("\u{F72C}", "⇞"), ("\u{F72D}", "⇟")]
for (c, shown) in charRows {
    check(sc(c) == "⌘" + shown, "character U+\(String(c.unicodeScalars.first!.value, radix: 16, uppercase: true)) → ⌘\(shown) (got \(sc(c) ?? "nil"))")
}
// U+F704…U+F726 → F1…F35.
for (scalar, n) in [(0xF704, 1), (0xF705, 2), (0xF708, 5), (0xF70F, 12), (0xF710, 13), (0xF726, 35)] {
    let c = String(Character(UnicodeScalar(scalar)!))
    check(sc(c, 8) == "F\(n)", "character U+\(String(scalar, radix: 16, uppercase: true)) → F\(n) (got \(sc(c, 8) ?? "nil"))")
}
// The glyph table (Carbon Menus.h), with nothing else to go on.
var glyphRows: [(Int, String)] = [(2, "⇥"), (4, "⌤"), (9, "Space"), (10, "⌦"), (11, "↩"), (23, "⌫"), (27, "⎋"), (28, "⌧"), (98, "⇞"),
                                  (100, "←"), (101, "→"), (102, "↖"), (104, "↑"), (105, "↘"), (106, "↓"), (107, "⇟")]
for n in 1...12 { glyphRows.append((110 + n, "F\(n)")) }
glyphRows += [(135, "F13"), (136, "F14"), (137, "F15")]
for (g, shown) in glyphRows { check(sc(nil, 0, glyph: g) == "⌘" + shown, "glyph \(g) → ⌘\(shown) (got \(sc(nil, 0, glyph: g) ?? "nil"))") }
// The virtual key table (Events.h), with nothing else to go on.
let vkRows: [(Int, String)] = [(36, "↩"), (48, "⇥"), (49, "Space"), (51, "⌫"), (53, "⎋"), (76, "⌤"), (115, "↖"), (116, "⇞"), (117, "⌦"),
                               (119, "↘"), (121, "⇟"), (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
                               (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
                               (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")]
for (v, shown) in vkRows { check(sc(nil, 0, vk: v) == "⌘" + shown, "virtual key \(v) → ⌘\(shown) (got \(sc(nil, 0, vk: v) ?? "nil"))") }
// The probe's examples.
check(sc("K", 0) == "⌘K", "\"K\" with 0 → ⌘K")
check(sc("E", 1) == "⇧⌘E", "\"E\" with 1 → ⇧⌘E")
check(sc("\u{F708}", 8) == "F5", "U+F708 with 8 → F5")
check(sc("\u{8}", 0, glyph: 23) == "⌘⌫", "\\u{8} with glyph 23 → ⌘⌫")
check(sc("F", 28) == "fn ⌃F", "the Fill item's F with 28 → fn ⌃F")
check(sc(nil, 29, vk: 123) == "fn ⌃⇧←", "a tiling item: virtual key 123 with 29 → fn ⌃⇧←")
// The fixture's, as the probe read the same keys (dumps/fixture-prohibited.txt).
check(sc("", 0, vk: 51, glyph: 23) == "⌘⌫", "an empty character with virtual key 51 and glyph 23 → ⌘⌫")
check(sc("", 8, vk: 96, glyph: 115) == "F5", "F5 with no ⌘: glyph 115, modifiers 8 → F5")
check(sc("", 4, vk: 126, glyph: 104) == "⌃⌘↑", "up arrow with ⌃: glyph 104, modifiers 4 → ⌃⌘↑")
check(sc("\t", 12, vk: 48, glyph: 2) == "⌃⇥", "tab with ⌃ and no ⌘ (12) → ⌃⇥")
check(sc(" ", 2, vk: 49, glyph: 9) == "⌥⌘Space", "space with ⌥ → ⌥⌘Space")
check(sc("⎋", 2, vk: 53, glyph: 27) == "⌥⌘⎋", "Force Quit: ⎋ in the character, glyph 27, ⌥ → ⌥⌘⎋")
check(sc("B", 13) == "⌃⇧B", "B with ⌃⇧ and no ⌘ (13) → ⌃⇧B")
// Modifiers: Apple's order, fn first, ⌘ unless no-Command.
check(sc("A", 1 | 2 | 4) == "⌃⌥⇧⌘A", "all four in Apple's order: ⌃⌥⇧⌘A")
check(sc("A", 2 | 4) == "⌃⌥⌘A", "⌃ before ⌥")
check(sc("A", 1 | 2) == "⌥⇧⌘A", "⌥ before ⇧")
check(sc("A", 16) == "fn ⌘A", "fn alone: fn ⌘A")
check(sc("A", 8) == "A", "no-Command alone: A")
check(sc("A", 8 | 1) == "⇧A", "⇧ without ⌘: ⇧A")
check(sc("A", nil) == "⌘A", "missing modifiers count as 0: ⌘A")
check(sc("A", 32) == "⌘A", "an unknown modifier bit shows nothing of its own")
// No key.
check(sc(nil, 0) == nil && sc(nil, 8) == nil && sc(nil, nil) == nil, "modifiers alone are no shortcut (every item has 0 or 8)")
check(sc("", 0) == nil, "an empty character alone is no shortcut")
check(sc("\u{F727}", 0) == nil && sc("\u{E000}", 0) == nil && sc("\u{F72A}", 8) == nil, "a private-use character with no name: no shortcut")
check(sc("\u{F727}", 0, vk: 114) == nil, "…whatever its virtual key (nothing readable remains)")
check(sc(nil, 0, glyph: 150) == nil && sc(nil, 0, vk: 7) == nil, "a glyph or virtual key outside the tables alone: no shortcut")
check(sc("🎤", 8, glyph: 150) == "🎤", "a glyph outside the table falls to its printable character: 🎤")
check(sc("\u{0}", 0) == nil && sc("\u{200B}", 0) == nil, "a control or format character is no shortcut")
// Which source wins.
check(sc("X", 0, glyph: 23) == "⌘⌫", "the glyph wins over the character")
check(sc("\u{8}", 0, glyph: 10) == "⌘⌦", "the glyph wins over a special character")
check(sc("K", 0, vk: 51) == "⌘K", "the character wins over the virtual key")
check(sc("\u{F700}", 0, vk: 123) == "⌘↑", "a special character wins over the virtual key")
check(sc("k", 0) == "⌘k", "a character as Accessibility gives it (no case change)")
// The 16-character limit.
check(sc(String(repeating: "W", count: 15), 0)?.count == 16, "⌘ and 15 characters: 16, shown")
check(sc(String(repeating: "W", count: 16), 0) == nil, "⌘ and 16 characters: 17, not shown")
check(sc("F", 16 | 4 | 2 | 1) == "fn ⌃⌥⇧⌘F", "the longest real one fits: fn ⌃⌥⇧⌘F")
check(F.keyLimit == 16 && F.titleLimit == 100, "limits: keys 16, titles 100")

// MARK: - MenuFormat.item

func raw(_ title: String?, desc: String? = nil, enabled: Bool? = true, mark: String? = nil, char: String? = nil, mods: Int? = 0,
         vk: Int? = nil, glyph: Int? = nil, children: Int = 0, role: String? = nil) -> RawMenuItem {
    RawMenuItem(title: title, description: desc, enabled: enabled, mark: mark, char: char, modifiers: mods, virtualKey: vk, glyph: glyph,
                childCount: children, firstChildRole: role)
}
check(F.item(raw("", enabled: false), id: "4.2") == MacMenuItem(separator: true), "a separator: \"\", disabled, no children → {separator}")
check(F.item(raw("", enabled: true), id: "4.7") == nil, "an enabled untitled item (image-only) is not a separator, and has no title: nil")
check(F.item(raw("", enabled: nil), id: "4.7") == nil, "an untitled item whose enabled flag is missing: nil, not a separator")
check(F.item(raw("", enabled: false, children: 1, role: "AXMenu"), id: "4.7") == nil, "an untitled disabled submenu is not a separator: nil")
check(F.item(raw("", desc: "Star", enabled: true), id: "4.7") == nil, "a title of \"\" stays \"\": no description stands in")
check(F.item(raw(nil, desc: "Apple Developer"), id: "6.30")?.title == "Apple Developer", "no title at all: the description (Chrome's bookmarks)")
check(F.item(raw(nil), id: "6.30") == nil, "no title and no description: nil")
check(F.item(raw(nil, enabled: false), id: "6.30") == nil, "a missing title (not \"\"), disabled, no children: not a separator, nil")
check(F.item(raw("Save\n\u{202E}evil"), id: "2.9")?.title == "Save evil", "the title cleaned (SafeText): newline and bidi override gone")
check(F.item(raw(String(repeating: "a", count: 150)), id: "2.9")?.title?.count == 100, "the title cut to 100 characters")
check(F.item(raw("   "), id: "2.9") == nil, "a title of spaces only: nil")
let save = F.item(raw("Save", char: "S", mods: 0), id: "2.9")
check(save == MacMenuItem(id: "2.9", title: "Save", key: "⌘S"), "Save ⌘S: id, title, key; enabled and the rest left out")
check(F.item(raw("Revert", enabled: false), id: "2.14") == MacMenuItem(id: "2.14", title: "Revert", enabled: false), "a disabled item: enabled false")
check(F.item(raw("Go", enabled: nil), id: "2.1")?.enabled == nil, "a missing enabled flag counts as enabled: nil")
check(F.item(raw("Go", enabled: true), id: "2.1")?.enabled == nil, "enabled true is left out")
check(F.item(raw("Open Recent", children: 1, role: "AXMenu"), id: "2.3") == MacMenuItem(id: "2.3", title: "Open Recent", submenu: true),
      "a submenu: its first child an AXMenu")
check(F.item(raw("Tags", children: 1, role: "AXButton"), id: "3.1") == nil, "a custom view (children not an AXMenu): nil")
check(F.item(raw("Tags", children: 2, role: nil), id: "3.1") == nil, "children whose role is unknown: nil")
check(F.item(raw("Checked", mark: "✓"), id: "4.3")?.mark == "✓", "the mark ✓")
check(F.item(raw("Mixed", mark: "-"), id: "4.4")?.mark == "-", "the mixed mark -")
check(F.item(raw("Dot", mark: "•x"), id: "4.4")?.mark == "•", "a mark: its first character")
check(F.item(raw("Off", mark: ""), id: "4.4")?.mark == nil && F.item(raw("Off", mark: nil), id: "4.4")?.mark == nil, "no mark: nil")
check(F.item(raw("Off", mark: "\u{200B}"), id: "4.4")?.mark == nil && F.item(raw("Off", mark: " "), id: "4.4")?.mark == nil,
      "a mark that cleans to nothing: nil")
check(F.item(raw("F5 Item", char: "", mods: 8, vk: 96, glyph: 115), id: "4.9")?.key == "F5", "the key comes from shortcut()")
check(F.item(raw("Plain", char: nil, mods: 8), id: "4.9")?.key == nil, "no key: nil")
check(F.item(raw("Deep", children: 1, role: "AXMenu"), id: "4.19")?.id == "4.19", "the id is kept")
// The bar's menus.
check(F.topItem(raw("File"), index: 2) == MacMenuItem(id: "2", title: "File", submenu: true), "a bar menu: id, title, submenu")
check(F.topItem(raw("Help", enabled: false), index: 9)?.enabled == false, "a disabled bar menu: enabled false")
check(F.topItem(raw(""), index: 3) == nil && F.topItem(raw(nil), index: 3) == nil, "an untitled bar menu: nil")
check(F.displayTitle(title: nil, description: "d") == "d" && F.displayTitle(title: "t", description: "d") == "t", "displayTitle: title, else description")

// MARK: - MenuPath

check(MenuPath("3.4.1")?.indexes == [3, 4, 1] && MenuPath("3.4.1")?.id == "3.4.1", "3.4.1 parses and formats")
check(MenuPath("1")?.indexes == [1] && MenuPath("9999")?.indexes == [9999], "one part; four digits")
check(MenuPath("1.0")?.indexes == [1, 0], "0 after the first part (a menu's first item)")
check(MenuPath("0") == nil && MenuPath("0.1") == nil, "0 first (the Apple menu): refused")
check(MenuPath("1.2.3.4.5.6.7.8") != nil, "8 levels")
check(MenuPath("1.2.3.4.5.6.7.8.9") == nil, "9 levels: refused")
check(MenuPath("10000") == nil && MenuPath("1.10000") == nil, "5 digits: refused")
for junk in ["", ".", "1.", ".1", "1..2", "a", "-1", "+1", " 1", "1 ", "1.a", "٣", "１", "1,2", "01", "1.02", "1e2", "0x1"] {
    check(MenuPath(junk) == nil, "junk refused: \(junk.debugDescription)")
}
check(MenuPath("4.21.0")?.parent == MenuPath("4.21") && MenuPath("4")?.parent == nil, "parent: 4.21.0 → 4.21; a bar menu has none")
check(MenuPath("4")?.child(21)?.id == "4.21" && MenuPath("1.2.3.4.5.6.7.8")?.child(0) == nil, "child: 4 → 4.21; none past 8 levels")
check(MenuPath("4.21.0")?.lineage.map(\.id) == ["4", "4.21", "4.21.0"], "lineage: 4, 4.21, 4.21.0")
check(MenuPath(indexes: [0]) == nil && MenuPath(indexes: []) == nil && MenuPath(indexes: [1, 10000]) == nil && MenuPath(indexes: [1, -1]) == nil,
      "init(indexes:) keeps the same limits")

// MARK: - MenuCache

let items1 = [MacMenuItem(id: "4.0", title: "A")]
var cache = MenuCache()
cache.store("4", .init(items: items1, more: 0, at: 100, appWasFrontmost: true))
check(cache.fresh("4", now: 100.99)?.items == items1, "fresh at 0.99 s")
check(cache.fresh("4", now: 101.0) == nil, "not fresh at 1.0 s")
check(cache.fresh("5", now: 100.1) == nil, "another menu: nothing")
check(cache.wait("4", now: 100.3) == 0, "after a read while frontmost: no wait")
cache.store("3", .init(items: items1, more: 0, at: 200, appWasFrontmost: false))
check(cache.fresh("3", now: 200.1) == nil, "a read made while the app was not frontmost is never answered from")
check(abs(cache.wait("3", now: 200.3) - 0.7) < 1e-9, "…and waits out the rest of its second: 0.7 s at 0.3 s")
check(cache.wait("3", now: 201.0) == 0 && cache.wait("3", now: 205) == 0, "…no wait once the second is over")
check(cache.wait("9", now: 1) == 0, "nothing read: no wait")
cache.store("4", .init(items: [], more: 3, at: 300, appWasFrontmost: true))
check(cache.fresh("4", now: 300.5)?.more == 3 && cache.fresh("4", now: 300.5)?.items == [], "a store replaces")
cache.clear()
check(cache.fresh("4", now: 300.5) == nil && cache.isEmpty, "clear")
check(MenuCache.lifetime == 1.0, "lifetime 1 s")

// MARK: - RequestRate

var rate = RequestRate()
check((0..<20).allSatisfy { rate.allowFetch(now: 10 + Double($0) * 0.01) }, "20 fetches within a second: allowed")
check(!rate.allowFetch(now: 10.5), "the 21st: refused")
check(!rate.allowFetch(now: 10.99), "still refused within the second")
check(rate.allowFetch(now: 11.0), "a second after the first: allowed again")
check((0..<4).allSatisfy { rate.allowPress(now: 10 + Double($0) * 0.01) }, "4 presses: allowed (counted apart from fetches)")
check(!rate.allowPress(now: 10.2), "the 5th press: refused")
check(rate.allowPress(now: 11.1), "a press after the second: allowed")
var burst = RequestRate()
var allowed = 0
for i in 0..<50 { if burst.allowFetch(now: 50 + Double(i) * 0.001) { allowed += 1 } }
check(allowed == 20, "50 back to back: 20 allowed (\(allowed))")
var steady = RequestRate()
var steadyAllowed = 0
for i in 0..<100 { if steady.allowFetch(now: Double(i) * 0.04) { steadyAllowed += 1 } }   // 25 a second for 4 s
check(steadyAllowed <= 80 + 1 && steadyAllowed >= 79, "25 a second for 4 s: about 20 a second allowed (\(steadyAllowed)); refused ones do not count")
var lines = RequestRate()
check(lines.ignoredLineDue(now: 5), "the first ignored line: due")
check(!lines.ignoredLineDue(now: 5.5), "a second one within the second: not due")
check(lines.ignoredLineDue(now: 6.0), "a second later: due again")
check(RequestRate.fetchesPerSecond == 20 && RequestRate.pressesPerSecond == 4, "20 fetches, 4 presses a second")

// MARK: - TopLevel

let tl = TopLevel(titles: ["menufixture", "File", "Edit", "Probe"], enabled: [true, true, true, true])
check(tl == TopLevel(titles: ["menufixture", "File", "Edit", "Probe"], enabled: [true, true, true, true]), "the same titles and flags: equal")
check(tl != TopLevel(titles: ["menufixture", "File", "Edit", "Probe"], enabled: [true, true, false, true]), "an enabled flag changed: differs")
check(tl != TopLevel(titles: ["menufixture", "File", "Probe", "Edit"], enabled: [true, true, true, true]), "the order changed: differs")
check(tl != TopLevel(titles: ["menufixture", "File", "Edit"], enabled: [true, true, true]), "a menu gone: differs")
check(tl != TopLevel(titles: ["menufixture", "File", "Edit", "Tools"], enabled: [true, true, true, true]), "a title changed: differs")

// MARK: - PressDecision (every row)

typealias D = PressDecision
check(D.decide(elementValid: true, found: nil, shown: "Save", enabled: true) == .press, "a kept element that answers: pressed")
check(D.decide(elementValid: true, found: nil, shown: "Save", enabled: nil) == .press, "…its enabled flag missing: pressed")
check(D.decide(elementValid: true, found: nil, shown: "Undo Typing", enabled: true) == .press
      && D.decide(elementValid: true, found: "Undo Paste", shown: "Undo Typing", enabled: true) == .press,
      "a kept element is authoritative: its title is never compared (Undo Typing → Undo Paste)")
check(D.decide(elementValid: true, found: nil, shown: nil, enabled: true) == .press, "a kept element with no title shown: pressed")
check(D.decide(elementValid: true, found: nil, shown: "Save", enabled: false) == .refuse(.disabled), "a kept element, disabled: refused")
check(D.decide(elementValid: false, found: "Rebuilt Leaf", shown: "Rebuilt Leaf", enabled: true) == .pressFound, "found again by its path, same title: pressed")
check(D.decide(elementValid: false, found: "Rebuilt Leaf", shown: "Rebuilt Leaf", enabled: nil) == .pressFound, "…enabled missing: pressed")
check(D.decide(elementValid: false, found: "Rebuilt Leaf", shown: "Rebuilt Leaf", enabled: false) == .refuse(.disabled), "…disabled: refused")
check(D.decide(elementValid: false, found: "Renamed Leaf", shown: "Rebuilt Leaf", enabled: true) == .refuse(.changed), "found again, another title: refused")
check(D.decide(elementValid: false, found: nil, shown: "Rebuilt Leaf", enabled: nil) == .refuse(.changed), "nothing at the path: refused")
check(D.decide(elementValid: false, found: "Rebuilt Leaf", shown: nil, enabled: true) == .refuse(.changed), "found again but no title shown to compare: refused")

// MARK: - The refusals' words and the log's path

typealias R = MenuRefusal
check(R.changed.note(app: "Code") == "The menus changed. Open the menu again.", "note: the menus changed")
check(R.disabled.note(app: "Code") == "It isn’t available right now.", "note: disabled")
check(R.gone.note(app: "Code") == "Code is no longer open.", "note: gone")
check(R.notAnswering.note(app: "Blender") == "Blender isn’t responding.", "note: not answering")
check(R.notTrusted.note(app: "Code") == "Allow Accessibility for Sill on the Mac (System Settings › Privacy & Security › Accessibility).", "note: no Accessibility")
check(R.tooMany.note(app: "Code") == "Too many requests. Open the menu again.", "note: too many")
check(R.failed("failure").note(app: "Code") == "It isn’t available right now.", "note: another AX error")
check(R.changed.logReason(app: "Code") == "the menus changed" && R.disabled.logReason(app: "Code") == "disabled"
      && R.gone.logReason(app: "Code") == "Code is no longer open" && R.notAnswering.logReason(app: "Code") == "Code is not answering Accessibility"
      && R.notTrusted.logReason(app: "Code") == "no Accessibility permission", "the log's reasons (the plan's §4.7)")
check(MenuLog.path(app: "Code", titles: ["File", "Save"]) == "Code › File › Save", "the log's path: Code › File › Save")
check(MenuLog.path(app: "menufixture", titles: ["Probe", "Deep", "Level 2", "Level 3", "Deep Leaf"])
      == "menufixture › Probe › Deep › Level 2 › Level 3 › Deep Leaf", "…five levels")
check(MenuLog.path(app: "Code", titles: ["File", nil]) == nil && MenuLog.path(app: "Code", titles: ["", "Save"]) == nil,
      "an unknown or empty title: nil (the line gives the id)")
check(MenuLog.path(app: "Co\nde", titles: [String(repeating: "x", count: 80)]) == "Co de › " + String(repeating: "x", count: 64),
      "each part cleaned to 64 characters")

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
