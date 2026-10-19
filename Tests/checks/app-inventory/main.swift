import Foundation
var checks = 0
func expect(_ condition: Bool, _ label: String) { checks += 1; if !condition { fatalError(label) } }
let editor = AppInfo(name: "Editor", bundleID: "test.editor")
let minimized = AppInfo(name: "Minimized", bundleID: "test.minimized")
let windowless = AppInfo(name: "Windowless", bundleID: "test.windowless")
let fullscreen = AppInfo(name: "Fullscreen", bundleID: "test.fullscreen")
let a = WindowInfo(id: 1, title: "A", appName: editor.name, bundleID: editor.bundleID, width: 800, height: 600)
var b = a; b.id = 2; b.title = "B"
var f = a; f.id = 3; f.bundleID = fullscreen.bundleID; f.appName = fullscreen.name
expect(AppInventory.openApps(windows: [a,b,f], runningApps: nil) == [editor,fullscreen], "legacy window grouping deduplicates and preserves order")
let running = [fullscreen, minimized, editor, windowless, editor]
expect(AppInventory.openApps(windows: [a,b,f], runningApps: running) == [editor,fullscreen,minimized,windowless], "new inventory includes minimized and windowless, retains selectable app order, no duplicates")
expect(AppInventory.openApps(windows: [a,b], runningApps: []) == [], "empty advertised inventory is authoritative")
expect(AppInventory.openApps(windows: [], runningApps: running) == [fullscreen,minimized,editor,windowless], "window catalog failure does not erase running apps")
let legacyJSON = Data(#"{"macName":"Test","windows":[],"active":{"desktop":{}}}"#.utf8)
let legacy = Wire.decode(WindowList.self, from: legacyJSON)
expect(legacy != nil && legacy?.runningApps == nil, "old host decodes without optional inventory")
let list = WindowList(macName: "Test", windows: [a,b,f], active: .desktop, runningApps: running)
let encoded = Wire.encode(list)
expect(Wire.decode(WindowList.self, from: encoded)?.runningApps == running, "inventory wire roundtrip")
struct OldWindowList: Decodable { let macName: String; let windows: [WindowInfo]; let active: StreamSource }
expect(Wire.decode(OldWindowList.self, from: encoded)?.windows == [a,b,f], "older client ignores additive inventory field")
let empty = Wire.decode(WindowList.self, from: Wire.encode(WindowList(macName: "Test", windows: [], active: .none, runningApps: [])))
expect(empty?.runningApps == [], "wire distinguishes empty inventory from legacy nil")
expect(Wire.decode(LaunchApp.self, from: Wire.encode(LaunchApp(bundleID: minimized.bundleID)))?.bundleID == minimized.bundleID, "running activation retains existing launch wire")
print("app-inventory: \(checks) checks, 0 failed")
