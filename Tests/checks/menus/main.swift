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

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
