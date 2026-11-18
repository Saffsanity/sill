import Foundation

// Every display Sill makes goes through one manager, SillDisplays (docs/virtual-desktop-plan.md §9 as revised
// 2026-11-18, phase 2b): the roles' identities, which macOS remembers a display by and DesktopDisplays.role tells Sill's
// two displays apart by (pure: Sources/SillHost/SillDisplayRole.swift, compiled with StreamProtocol's
// DesktopDisplays.swift and DisplayMakeGuard.swift), and the wiring, read as text in the repository given as the first
// argument: no display made anywhere else in the host (but its own self test's), each role's display made, waited for,
// listed, lost and removed there, the guard's marker around each make, the stage's IDs given to the catalog. Nothing here
// makes a display or looks up a private class.

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { return }
    failures += 1
    print("FAIL: \(what())")
}

// MARK: The roles and their identities (macOS remembers a display by them: they never change)

let stage = SillDisplayRole.stage, desktop = SillDisplayRole.desktop
check(SillDisplayRole.allCases == [.stage, .desktop], "two roles, the stage's and the Desktop's: \(SillDisplayRole.allCases)")
check(stage.name == "Sill" && stage.vendor == 0x5111 && stage.product == 0x0001 && stage.serial == 1,
      "the stage's display is milestone 3's \"Sill\", vendor 0x5111, product 0x0001, serial 1: \(stage.name) \(stage.vendor) \(stage.product) \(stage.serial)")
check(desktop.name == "Sill Desktop" && desktop.vendor == 0x5111 && desktop.product == 0x0002 && desktop.serial == 2,
      "the Desktop's is #200's \"Sill Desktop\", vendor 0x5111, product 0x0002, serial 2: \(desktop.name) \(desktop.vendor) \(desktop.product) \(desktop.serial)")
check(stage.vendor == DesktopDisplays.sillVendor && stage.product == DesktopDisplays.stageProduct
      && desktop.product == DesktopDisplays.desktopProduct, "the roles take DesktopDisplays' numbers")
// What the Desktop's stops make of each (DesktopDisplays.role): the stage's display is never a stop, the Desktop's is Sill's.
check(DesktopDisplays.role(vendor: stage.vendor, product: stage.product, madeByStage: false) == .stage, "the stage's display reads as the stage's")
check(DesktopDisplays.role(vendor: desktop.vendor, product: desktop.product, madeByStage: false) == .sillDesktop,
      "the Desktop's display reads as Sill's Desktop display")
check(DesktopDisplays.role(vendor: desktop.vendor, product: desktop.product, madeByStage: true) == .sillDesktop,
      "the Desktop's display is never taken for the stage's, even at an ID the stage once had")
check(Set(SillDisplayRole.allCases.map { "\($0.vendor)/\($0.product)/\($0.serial)" }).count == 2, "no two roles share an identity")
// The guard's marker names the role, and the next launch reads it (DisplayMakeGuard.parse, launchLine).
let when = Date(timeIntervalSince1970: 1_800_000_000)
for role in SillDisplayRole.allCases {
    let marker = DisplayMakeGuard.marker(role: role.rawValue, at: when)
    check(DisplayMakeGuard.parse(marker)?.role == role.rawValue, "the guard's marker for the \(role) role reads back: \(marker)")
}
check(DisplayMakeGuard.launchLine(marker: DisplayMakeGuard.marker(role: stage.rawValue, at: when), stops: 1)?.contains("its window display") == true,
      "a stage marker reads as its window display at the next launch")
check(DisplayMakeGuard.launchLine(marker: DisplayMakeGuard.marker(role: desktop.rawValue, at: when), stops: 1)?.contains("its Desktop display") == true,
      "a Desktop marker reads as its Desktop display")

// MARK: The wiring, read as text

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
let hostFolder = root.appendingPathComponent("Sources/SillHost")
let hostFiles = ((try? FileManager.default.contentsOfDirectory(atPath: hostFolder.path)) ?? []).filter { $0.hasSuffix(".swift") }.sorted()
check(hostFiles.contains("SillDisplays.swift") && hostFiles.count > 50, "the host's sources read (\(hostFiles.count) in \(hostFolder.path))")
let manager = source("Sources/SillHost/SillDisplays.swift")
let stageSource = source("Sources/SillHost/VirtualStage.swift")
func occurrences(_ text: String, _ s: String) -> Int { s.components(separatedBy: text).count - 1 }

// A display is made in one place: SillDisplays.make, and the self test's own (--virtual-display-selftest, a person's).
// A make is VirtualDisplay's initializer, `VirtualDisplay(name:` (its first label).
var makers: [String] = []
for f in hostFiles where f != "VirtualDisplay.swift" {
    let n = occurrences("VirtualDisplay(name:", source("Sources/SillHost/\(f)"))
    if n > 0 { makers.append("\(f) \(n)") }
}
check(makers == ["SillDisplays.swift 1", "StreamCoordinator.swift 1", "VirtualDisplaySelfTest.swift 1"],
      "a display made only in SillDisplays.make, the self test and (until the headless display moves) the coordinator: \(makers)")
check(manager.contains("d = try VirtualDisplay(name: role.name, widthPt: widthPt, heightPt: heightPt, scale: scale, refreshHz: refreshHz,\n"
                       + "                                   vendorID: role.vendor, productID: role.product, serialNum: role.serial)"),
      "SillDisplays.make makes each display with its role's identity")
// The guard for #380 around every make: the marker taken back on a throw and once it is up (or not).
check(manager.contains("        } catch {\n            makeGuard?.made(cameUp: false)\n            throw error\n        }"),
      "a make that throws takes the guard's marker back as a make that failed")
check(manager.contains("let online = await d.waitUntilOnline(timeout: timeout)\n        makeGuard?.made(cameUp: d.bounds.width > 0)"),
      "waiting until it is online takes the marker back, resetting the count once it came up")
check(manager.contains("func willMake(_ role: SillDisplayRole) {\n        makeGuard?.willMake(role.rawValue)"), "willMake writes the marker with the role's word")
// The catalog knows the stage's displays, gone or not (DesktopDisplays.role's madeByStage).
check(occurrences("stageDisplayIDs.insert(", manager) == 1 && manager.contains("if role == .stage { catalog.stageDisplayIDs.insert(d.displayID) }"),
      "the stage's display is given to the catalog as it is made, in SillDisplays alone")
check(hostFiles.filter { $0 != "SillDisplays.swift" && source("Sources/SillHost/\($0)").contains("stageDisplayIDs.insert(") }.isEmpty,
      "no other file gives the catalog a stage display")
// Removal: the display destroyed at once, and an old display's termination ignored.
check(manager.contains("guard let d = made.removeValue(forKey: role) else { return nil }\n        let id = d.displayID\n        d.destroy()"),
      "remove destroys the display at once")
check(manager.contains("guard gen == generations[role], made[role] != nil, let handler = onLost[role] else { return }"),
      "a lost callback counts only for the role's newest display, and only for a role that handles it")
check(manager.contains("d.onTerminated = { [weak self] in Task { @MainActor [weak self] in self?.lost(role, generation: gen) } }"),
      "every display's termination hops to the main actor")

// The stage (VirtualStage): its display through SillDisplays, as it was made before (the marker before the old one goes).
check(!stageSource.contains("VirtualDisplay(name:"), "the stage makes no display itself")
check(stageSource.contains("if mayMake, !guarded { displays.willMake(.stage) }\n        destroyDisplay()\n"),
      "the stage's marker is written before its old display goes (#380's stops came right after \"Removed virtual display N\")")
check(stageSource.contains("d = try displays.make(.stage, widthPt: Int(env.width), heightPt: Int(env.height + menuInset), scale: 2,"),
      "the stage's display is made by SillDisplays")
check(stageSource.contains("let online = await displays.waitUntilOnline(d, timeout: 3)"), "and waited for there")
check(stageSource.contains("guard await displays.waitUntilListed(d, as: .stage, timeout: 3) != nil else {"), "and listed there")
check(stageSource.contains("if let id = displays.remove(.stage) {\n            print(\"Removed virtual display \\(id)\""),
      "and removed there, with its line as before")
check(stageSource.contains("displays.onLost[.stage] = { [weak self] in self?.displayLost() }"), "the stage hears its display lost")
check(stageSource.contains("guarded = displays.guardHolds"), "the stage reads the guard there")

print("sill-displays: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
