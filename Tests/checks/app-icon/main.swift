// AppIconChoice (iOSClient/AppIconChoice.swift) on its own, and the build's wiring of the icons it names: the
// Home Screen icon of Sill for iPhone and iPad, the person's choice in Settings beside the version (Noah,
// 2026-11-18; docs/app-icons-plan.md).
//   - The choices: the original first, the primary icon and what a new install shows; the community's an
//     alternate with its name; their names, previews and ids each its own.
//   - The words: each title, the community's credit by its author's login, VoiceOver's, the group's title, the
//     footnote (the device's word, the way back while a Mac is connected, never "always"), each tile's hint, the
//     refusal.
//   - Which icon shows: no name, each alternate's name, and names this build does not ship (a later icon's, the
//     primary's own name, an empty one, another case): the original for every unknown one.
//   - What a tap asks: every choice from every name, nothing when that very icon is set, the original clearing
//     an unknown name; a round trip for each choice; whether the group shows.
//   - The wiring, read from the repository (or from the folder given as the first argument, which the
//     mutants use): the project's icon names in both configurations (the primary, the alternates exactly), each
//     icon's document as a resource and no asset catalog icon set of its name, each document's icon.json and
//     every layer it names, each preview image set and its picture, and Sill for Mac's icon the original.
//   swiftc -O iOSClient/AppIconChoice.swift Tests/checks/app-icon/main.swift -o .build/checks/app-icon/check && .build/checks/app-icon/check
import Foundation

typealias C = AppIconChoice

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
func path(_ p: String) -> String { (root as NSString).appendingPathComponent(p) }
func read(_ p: String) -> String? { try? String(contentsOfFile: path(p), encoding: .utf8) }
func exists(_ p: String) -> Bool { FileManager.default.fileExists(atPath: path(p)) }

// MARK: - The choices

check("two choices, the original first, then the community's", C.allCases == [.original, .community])
check("a new install shows the original (the standard)", C.standard == .original)
check("the original is the primary icon, AppIcon: no alternate name, so setAlternateIconName(nil) brings it back",
      C.original.iconName == "AppIcon" && C.original.alternateIconName == nil)
check("the community's is the alternate AppIconCommunity", C.community.iconName == "AppIconCommunity"
      && C.community.alternateIconName == "AppIconCommunity")
check("the alternates are exactly [AppIconCommunity]: what the project must list", C.alternateIconNames == ["AppIconCommunity"])
check("every choice but the standard has an alternate name, and only the standard has none",
      C.allCases.allSatisfy { ($0 == C.standard) == ($0.alternateIconName == nil) })
check("each choice's icon name, preview, id and title its own",
      Set(C.allCases.map(\.iconName)).count == C.allCases.count && Set(C.allCases.map(\.previewImageName)).count == C.allCases.count
      && Set(C.allCases.map(\.id)).count == C.allCases.count && Set(C.allCases.map(\.title)).count == C.allCases.count)
check("the previews: AppIconPreview and AppIconCommunityPreview (the icon's name, then Preview)",
      C.original.previewImageName == "AppIconPreview" && C.community.previewImageName == "AppIconCommunityPreview")
check("a choice's id is its raw value, original and community", C.original.id == "original" && C.community.id == "community"
      && C.allCases.allSatisfy { C(rawValue: $0.id) == $0 })
check("no alternate is named as the primary, so no name means two icons", !C.alternateIconNames.contains(C.standard.iconName))

// MARK: - The words

check("the titles: Original, Community", C.original.title == "Original" && C.community.title == "Community")
check("the community's author by login, grub-basket; the original none", C.community.author == "grub-basket" && C.original.author == nil)
check("the credit under the community's title: \"by grub-basket\"; none under the original's",
      C.community.credit == "by grub-basket" && C.original.credit == nil)
check("VoiceOver: \"Original icon\", \"Community icon, by grub-basket\"",
      C.original.spoken == "Original icon" && C.community.spoken == "Community icon, by grub-basket")
check("the group's title: App Icon", C.Copy.title == "App Icon")
check("the footnote, on an iPad: what it changes and the way back",
      C.Copy.footnote(device: "iPad")
        == "The icon Sill shows on this iPad’s Home Screen. You can switch back to Original here whenever you’re connected to a Mac.")
check("the footnote, on an iPhone: its own device's word", C.Copy.footnote(device: "iPhone").contains("this iPhone’s Home Screen")
      && !C.Copy.footnote(device: "iPhone").contains("iPad"))
check("the footnote names the standard's title as the way back", C.Copy.footnote(device: "iPad").contains("switch back to \(C.standard.title) here"))
check("the footnote says the way back needs a Mac connected (Settings is a session's), and never promises it always",
      C.Copy.footnote(device: "iPad").hasSuffix("whenever you’re connected to a Mac.")
      && !C.Copy.footnote(device: "iPad").lowercased().contains("always"))
check("a tile's hint: what choosing it does; the one set, that it is Sill's icon now",
      C.Copy.hint(selected: false) == "Changes Sill’s icon on the Home Screen to this one." && C.Copy.hint(selected: true) == "Sill’s icon now.")
check("the refusal's words", C.Copy.failed == "Sill’s icon didn’t change. Try again in a moment.")
check("the words use typographic apostrophes, never a straight one",
      ([C.Copy.footnote(device: "iPad"), C.Copy.hint(selected: false), C.Copy.hint(selected: true), C.Copy.failed]
        + C.allCases.flatMap { [$0.title, $0.spoken, $0.credit ?? ""] }).allSatisfy { !$0.contains("'") })

// MARK: - Which icon shows

check("no alternate name: the original", C.current(alternateIconName: nil) == .original)
check("AppIconCommunity: the community's", C.current(alternateIconName: "AppIconCommunity") == .community)
for unknown in ["AppIconPride", "AppIcon", "", "appiconcommunity", "AppIconCommunity ", "community", "original", "AppIconCommunityPreview"] {
    check("a name this build does not ship (\"\(unknown)\"): the original, which iOS shows then",
          C.current(alternateIconName: unknown) == .original)
}

// MARK: - What a tap asks

let names: [String?] = [nil, "AppIconCommunity", "AppIconPride"]
func word(_ n: String?) -> String { n.map { "\"\($0)\"" } ?? "nil" }
func say(_ r: C.Request) -> String {
    switch r {
    case .none: return "nothing"
    case .set(let n): return "set \(word(n))"
    }
}
let expected: [AppIconChoice: [C.Request]] = [
    .original: [.none, .set(nil), .set(nil)],
    .community: [.set("AppIconCommunity"), .none, .set("AppIconCommunity")],
]
for choice in C.allCases {
    for (i, name) in names.enumerated() {
        check("\(choice.title) tapped while the name is \(word(name)): \(say(expected[choice]![i]))",
              C.request(choice, from: name) == expected[choice]![i])
    }
}
for choice in C.allCases {
    check("round trip: \(choice.title)'s own name reads as \(choice.title), and tapping it asks nothing",
          C.current(alternateIconName: choice.alternateIconName) == choice && C.request(choice, from: choice.alternateIconName) == .none)
    for other in C.allCases where other != choice {
        check("\(choice.title) tapped while \(other.title) shows: set \(word(choice.alternateIconName))",
              C.request(choice, from: other.alternateIconName) == .set(choice.alternateIconName))
    }
}
check("Original from an unknown name clears it (set nil), though it reads as the original already",
      C.current(alternateIconName: "AppIconPride") == .original && C.request(.original, from: "AppIconPride") == .set(nil))

// MARK: - Whether the group shows

check("where iOS can change the icon: shown", C.offered(supportsAlternateIcons: true))
check("where it cannot (no alternate in the bundle, an extension): hidden", !C.offered(supportsAlternateIcons: false))

// MARK: - The wiring

let pbxprojPath = "iOSClient/Sill.xcodeproj/project.pbxproj"
let pbx = read(pbxprojPath) ?? ""
check("the project file reads", !pbx.isEmpty)

/// Every build configuration block (`… = { isa = XCBuildConfiguration; … };`) that names an app icon.
let configs: [String] = {
    var out: [String] = []
    var rest = Substring(pbx)
    while let start = rest.range(of: "isa = XCBuildConfiguration;") {
        let tail = rest[start.upperBound...]
        guard let end = tail.range(of: "\n\t\t};") else { break }
        let block = String(tail[..<end.lowerBound])
        if block.contains("ASSETCATALOG_COMPILER_APPICON_NAME") { out.append(block) }
        rest = tail[end.upperBound...]
    }
    return out
}()
/// A build setting's value in a block: its words, quotes taken off ("A B" or A).
func setting(_ key: String, in block: String) -> [String]? {
    guard let line = block.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + " = ") }) else { return nil }
    var value = line.trimmingCharacters(in: .whitespaces).dropFirst(key.count + 3)
    if value.hasSuffix(";") { value = value.dropLast() }
    return value.replacingOccurrences(of: "\"", with: "").split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
}
check("the app target's two configurations (Debug and Release) name its icons", configs.count == 2)
for (i, block) in configs.enumerated() {
    check("configuration \(i + 1): the primary icon is \(C.standard.iconName)",
          setting("ASSETCATALOG_COMPILER_APPICON_NAME", in: block) == [C.standard.iconName])
    check("configuration \(i + 1): the alternates are exactly \(C.alternateIconNames), in order",
          setting("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES", in: block) == C.alternateIconNames)
    check("configuration \(i + 1): not every icon set at once (only the named alternates ship)",
          setting("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS", in: block) != ["YES"])
}
let resourcesPhase: String = {
    guard let r = pbx.range(of: "isa = PBXResourcesBuildPhase;"), let e = pbx[r.upperBound...].range(of: "};") else { return "" }
    return String(pbx[r.upperBound..<e.lowerBound])
}()
for choice in C.allCases {
    let doc = "Packaging/\(choice.iconName).icon"
    let ref = pbx.split(separator: "\n").first { $0.contains("/* \(choice.iconName).icon */ = {isa = PBXFileReference;") }.map(String.init) ?? ""
    check("\(doc) is in the project as an Icon Composer document at ../\(doc)",
          ref.contains("lastKnownFileType = folder.iconcomposer.icon;") && ref.contains("path = ../\(doc);") && ref.contains("sourceTree = SOURCE_ROOT;"))
    check("\(doc) is one of the app's resources", resourcesPhase.contains("/* \(choice.iconName).icon in Resources */"))
    check("no asset catalog icon set takes \(choice.iconName)'s name from its document",
          !exists("iOSClient/Assets.xcassets/\(choice.iconName).appiconset"))
    let json = (try? Data(contentsOf: URL(fileURLWithPath: path("\(doc)/icon.json"))))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    check("\(doc)/icon.json reads as an Icon Composer document (its groups)", (json?["groups"] as? [[String: Any]])?.isEmpty == false)
    let layers = ((json?["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }
    let images = layers.compactMap { $0["image-name"] as? String }
    check("\(doc): every layer names its picture (\(images.count) of \(layers.count))", !layers.isEmpty && images.count == layers.count)
    for image in images {
        check("\(doc): its layer \(image) is in Assets", exists("\(doc)/Assets/\(image)"))
    }
    let set = "iOSClient/Assets.xcassets/\(choice.previewImageName).imageset"
    let contents = (try? Data(contentsOf: URL(fileURLWithPath: path("\(set)/Contents.json"))))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let files = ((contents?["images"] as? [[String: Any]]) ?? []).compactMap { $0["filename"] as? String }
    check("\(set): one picture, and it is there", files.count == 1 && files.allSatisfy { exists("\(set)/\($0)") && $0.hasSuffix(".png") })
}
let macInfo = read("Packaging/Info.plist") ?? ""
check("Sill for Mac's icon is the original (Packaging/Info.plist's CFBundleIconName is AppIcon)",
      macInfo.range(of: "<key>CFBundleIconName</key>\\s*<string>\(C.standard.iconName)</string>", options: .regularExpression) != nil)
check("Scripts/make-app.sh compiles the original's document for Sill for Mac, and no alternate",
      (read("Scripts/make-app.sh") ?? "").contains("[ -d Packaging/\(C.standard.iconName).icon ]")
      && C.alternateIconNames.allSatisfy { !(read("Scripts/make-app.sh") ?? "").contains("doc=\"$PWD/Packaging/\($0).icon\"") })

print("app-icon: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
