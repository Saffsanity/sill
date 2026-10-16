import Foundation

var checks = 0
var failures = 0
func check(_ name: String, _ condition: Bool) {
    checks += 1
    if !condition { print("FAIL: \(name)"); failures += 1 }
}

let fm = FileManager.default
let scratch = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("sill-installed-apps-\(UUID().uuidString)")
try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }
let applications = scratch.appendingPathComponent("Applications")
let userApplications = scratch.appendingPathComponent("UserApplications")
try fm.createDirectory(at: applications, withIntermediateDirectories: true)
try fm.createDirectory(at: userApplications, withIntermediateDirectories: true)

@discardableResult
func app(_ path: String, _ id: String?, root: URL = applications) throws -> URL {
    let url = root.appendingPathComponent(path)
    let contents = url.appendingPathComponent("Contents")
    try fm.createDirectory(at: contents, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleName": url.deletingPathExtension().lastPathComponent]
    if let id { info["CFBundleIdentifier"] = id }
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: contents.appendingPathComponent("Info.plist"))
    return url
}

let top = try app("Alpha.app", "test.alpha")
let nested = try app("Adobe/Creative Suite/Photo.app", "test.photo")
try app("Utilities/Tool.app", "test.tool")
let personal = try app("Vendor/Personal.app", "test.personal", root: userApplications)
try app("Alpha.app", "test.alpha", root: userApplications)
try app("Alpha.app/Contents/Helpers/Helper.app", "test.helper")
try app("Container.bundle/Hidden.app", "test.bundle-helper")
try app(".hidden/Secret.app", "test.hidden")
try app("Broken.app", nil)
let outside = scratch.appendingPathComponent("Outside")
try app("Outside.app", "test.outside", root: outside)
try fm.createSymbolicLink(at: applications.appendingPathComponent("LinkedFolder"), withDestinationURL: outside)
try fm.createSymbolicLink(at: applications.appendingPathComponent("Loop"), withDestinationURL: applications)

let found = InstalledApps.find(in: [applications, userApplications, applications.appendingPathComponent("Utilities"), scratch.appendingPathComponent("Missing")])
let ids = found.map(\.bundleID)
func pathMatches(_ id: String, _ expected: URL) -> Bool {
    guard let path = found.first(where: { $0.bundleID == id })?.path else { return false }
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == expected.resolvingSymlinksInPath().path
}
check("an app directly in Applications", ids.contains("test.alpha"))
check("an app two folders deep", ids.contains("test.photo"))
check("Utilities remains included", ids.contains("test.tool"))
check("an app in a user's nested folder", ids.contains("test.personal"))
check("no helper within an app bundle", !ids.contains("test.helper"))
check("no apps within another package", !ids.contains("test.bundle-helper"))
check("no hidden folders", !ids.contains("test.hidden"))
check("no traversal through directory symlinks", !ids.contains("test.outside"))
check("duplicates across roots and repeated Utilities appear once", ids.count == Set(ids).count)
check("first root's bundle wins", pathMatches("test.alpha", top))
check("nested app keeps its own path", pathMatches("test.photo", nested))
check("personal app keeps its own path", pathMatches("test.personal", personal))
check("display names have no app suffix", found.allSatisfy { !$0.name.hasSuffix(".app") })
check("case-insensitive display name order", found.map(\.name) == found.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
check("only the four valid visible apps", Set(ids) == Set(["test.alpha", "test.photo", "test.tool", "test.personal"]))
check("empty or missing roots are harmless", InstalledApps.find(in: [scratch.appendingPathComponent("Missing")]).isEmpty)

print("installed-apps: \(checks) checks, \(failures) failures")
// exit() does not unwind the top-level defer.
try fm.removeItem(at: scratch)
exit(failures == 0 ? 0 : 1)
