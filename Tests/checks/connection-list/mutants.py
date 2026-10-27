"""Mutants of ConnectionList.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/ConnectionList.swift")
MUTANTS = [
    # The style: tiles by default (Noah, 2026-10-27), a stored choice always wins.
    ("the list by default again (main before 2026-10-27)", "static let defaultStyle: Style = .tiles",
     "static let defaultStyle: Style = .list"),
    ("the old rule: tiles only when stored", "raw.flatMap(Style.init(rawValue:)) ?? defaultStyle",
     "raw == Style.tiles.rawValue ? .tiles : .list"),
    ("a stored choice ignored", "raw.flatMap(Style.init(rawValue:)) ?? defaultStyle", "defaultStyle"),
    ("nothing stored read as the list", "raw.flatMap(Style.init(rawValue:)) ?? defaultStyle",
     "raw.flatMap(Style.init(rawValue:)) ?? (raw == nil ? .list : defaultStyle)"),
    ("a value no build writes read as the list", "raw.flatMap(Style.init(rawValue:)) ?? defaultStyle",
     "raw.flatMap(Style.init(rawValue:)) ?? (raw == nil ? defaultStyle : .list)"),
    ("toggled stays the same", "self == .list ? .tiles : .list", "self"),
    # When a session's end keeps a picture (only with tiles, the default since 2026-10-27; the list keeps none).
    ("a picture with the list too", "style == .tiles && sceneActive && saved", "sceneActive && saved"),
    ("a picture from a window behind", "style == .tiles && sceneActive && saved", "style == .tiles && saved"),
    ("a picture of a Mac not saved", "style == .tiles && sceneActive && saved", "style == .tiles && sceneActive"),
    ("a picture when any condition holds", "style == .tiles && sceneActive && saved", "style == .tiles || sceneActive || saved"),
    ("a picture only with the list", "style == .tiles && sceneActive && saved", "style == .list && sceneActive && saved"),
    # Every row of one Mac shows its one picture (Noah, 2026-10-27).
    ("a row taken by its name shows no picture", "        macID ?? savedByName\n", "        macID\n"),
    ("the name before the tag", "        macID ?? savedByName\n", "        savedByName ?? macID\n"),
    ("no row stands for a Mac", "        macID ?? savedByName\n", "        nil\n"),
    # A style never deletes a picture: the list hides them, tiles show them again (Noah, 2026-10-27).
    ("the switch to the list deletes the pictures",
     "guard style == .tiles else { return PreviewPlan(delete: delete, show: []) }",
     "guard style == .tiles else { return PreviewPlan(delete: files.filter { $0.hasSuffix(\".jpg\") }, show: []) }"),
    ("the list keeps the files of Macs no longer saved",
     "guard style == .tiles else { return PreviewPlan(delete: delete, show: []) }",
     "guard style == .tiles else { return PreviewPlan(delete: [], show: []) }"),
    ("the list shows the pictures", "guard style == .tiles else { return PreviewPlan(delete: delete, show: []) }", ""),
    ("the pictures not shown after switching back", "return PreviewPlan(delete: delete, show: show)",
     "return PreviewPlan(delete: delete, show: [])"),
    ("tiles delete every picture", "let delete = stalePreviewFiles(in: files, keepingMacIDs: savedMacIDs)",
     "let delete = files.filter { $0.hasSuffix(\".jpg\") }"),
    ("no file of a Mac no longer saved deleted", "let delete = stalePreviewFiles(in: files, keepingMacIDs: savedMacIDs)",
     "let delete: [String] = []"),
    ("a Mac no longer saved shows its picture", "return savedMacIDs.contains(macID) && previewFileName(for: macID) == file",
     "return previewFileName(for: macID) == file"),
    ("any name of a saved Mac shows", "return savedMacIDs.contains(macID) && previewFileName(for: macID) == file",
     "return savedMacIDs.contains(macID)"),
    ("the shown Macs in the folder's order", "}.map { String($0.dropLast(4)) }.sorted()", "}.map { String($0.dropLast(4)) }"),
    # Group names.
    ("no group length cap", 'String(words.joined(separator: " ").prefix(maxGroupLength))', 'String(words.joined(separator: " "))'),
    ("a name cut at the cap keeps its space", ").trimmingCharacters(in: .whitespaces)", ")"),
    ("blank group kept", "guard !words.isEmpty else { return nil }", ""),
    ("Other is a group", "if name.caseInsensitiveCompare(otherTitle) == .orderedSame { return nil }", ""),
    ("only Other itself, not other", "if name.caseInsensitiveCompare(otherTitle) == .orderedSame { return nil }",
     "if name == otherTitle { return nil }"),
    ("a preset in another case is another group",
     "return presetGroups.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name", "return name"),
    ("decode ignores empty macID check", "where !macID.isEmpty && macID.count <= 128", "where macID.count <= 128"),
    ("setting nil does not remove", "        } else {\n            next.removeValue(forKey: macID)", "        } else {"),
    ("a name in another case makes a second group",
     "next[macID] = groups.values.filter { $0.caseInsensitiveCompare(clean) == .orderedSame }.min() ?? clean",
     "next[macID] = clean"),
    # A superseded record's group.
    ("the successor's own group replaced", "if next[new] == nil { next[new] = group }", "next[new] = group"),
    ("the group not carried", "if next[new] == nil { next[new] = group }", ""),
    ("the retired record keeps its group", "next.removeValue(forKey: old)", ""),
    # The order of groups and sections.
    ("custom groups dropped", "ordered(Set(presetGroups).union(groups.values.compactMap(cleanGroup)))", "ordered(Set(presetGroups))"),
    ("presets sorted with the rest", "presetGroups.filter(names.contains) + names.subtracting(presetGroups).sorted {",
     "names.sorted {"),
    ("other names in reverse", "return order == .orderedSame ? a < b : order == .orderedAscending",
     "return order == .orderedSame ? a < b : order == .orderedDescending"),
    ("other names in plain code order", "let order = a.localizedStandardCompare(b)", "let order = a.compare(b)"),
    ("sections sorted without the presets first", "var out = ordered(Set(byGroup.keys)).compactMap",
     "var out = byGroup.keys.sorted().compactMap"),
    ("empty items returns a section", "guard !items.isEmpty else { return [] }", ""),
    ("ungrouped list titled Other even with no groups", "guard !byGroup.isEmpty else { return [Section(title: nil, items: items)] }",
     "guard !byGroup.isEmpty else { return [Section(title: otherTitle, items: items)] }"),
    ("ungrouped rows dropped when groups exist", "if !ungrouped.isEmpty { out.append(Section(title: otherTitle, items: ungrouped)) }", ""),
    # Pictures' files.
    ("path traversal allowed in previewFileName", "macID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == \"-\" || $0 == \"_\") })", "true"),
    ("previewFileName length uncapped", "macID.count <= 128,", ""),
    ("stalePreviewFiles deletes non-jpg", "guard file.hasSuffix(\".jpg\") else { return false }", "if !file.hasSuffix(\".jpg\") { return true }"),
    ("stalePreviewFiles deletes kept Macs", "return !keepingMacIDs.contains(id)", "return keepingMacIDs.contains(id)"),
    # Tiles' columns.
    ("columns ignores accessibleText", "(!accessibleText && width >= twoColumnMinWidth) ? 2 : 1", "width >= twoColumnMinWidth ? 2 : 1"),
    ("columns boundary off by one", "width >= twoColumnMinWidth", "width > twoColumnMinWidth"),
    # The picture's size (the stream's last keyframe, decoded).
    ("the picture as wide as the video", "let width = min((previewPoints * previewScale).rounded(.down), video.width.rounded(.down))",
     "let width = video.width.rounded(.down)"),
    ("the picture at 1x", "let width = min((previewPoints * previewScale).rounded(.down), video.width.rounded(.down))",
     "let width = min(previewPoints.rounded(.down), video.width.rounded(.down))"),
    ("a picture wider than its video", "let width = min((previewPoints * previewScale).rounded(.down), video.width.rounded(.down))",
     "let width = (previewPoints * previewScale).rounded(.down)"),
    ("the height rounded to nearest", "let height = max(1, (video.height * width / video.width).rounded(.down))",
     "let height = max(1, (video.height * width / video.width).rounded())"),
    ("a picture can be no pixel tall", "let height = max(1, (video.height * width / video.width).rounded(.down))",
     "let height = (video.height * width / video.width).rounded(.down)"),
    ("a video under a pixel makes a picture", "video.width >= 1, video.height >= 1", "video.width > 0, video.height > 0"),
    # The black test.
    ("a channel at the black level is bright",
     "if pixels[p] > blackLevel || pixels[p + 1] > blackLevel || pixels[p + 2] > blackLevel { return false }",
     "if pixels[p] >= blackLevel || pixels[p + 1] >= blackLevel || pixels[p + 2] >= blackLevel { return false }"),
    ("only the first channel looked at",
     "if pixels[p] > blackLevel || pixels[p + 1] > blackLevel || pixels[p + 2] > blackLevel { return false }",
     "if pixels[p] > blackLevel { return false }"),
    ("the fourth byte looked at, not the third",
     "if pixels[p] > blackLevel || pixels[p + 1] > blackLevel || pixels[p + 2] > blackLevel { return false }",
     "if pixels[p] > blackLevel || pixels[p + 1] > blackLevel || pixels[p + 3] > blackLevel { return false }"),
    ("the rows' padding ignored as a stride", "let start = row * bytesPerRow", "let start = row * width * 4"),
    ("the last row not looked at", "for row in 0..<height {", "for row in 0..<(height - 1) {"),
    ("the last pixel of a row not looked at", "for x in 0..<width {", "for x in 0..<(width - 1) {"),
    ("a much brighter black", "static let blackLevel: UInt8 = 24", "static let blackLevel: UInt8 = 100"),
    ("a bad layout read as a picture",
     "guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * (height - 1) + width * 4 else { return true }",
     "guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * (height - 1) + width * 4 else { return false }"),
    ("rows shorter than their pixels read",
     "guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count",
     "guard width > 0, height > 0, pixels.count"),
    # A picture decoded after its session ended.
    ("a decoded picture kept with the list", "static func keepsDecodedPicture(style: Style, saved: Bool) -> Bool {\n        style == .tiles && saved",
     "static func keepsDecodedPicture(style: Style, saved: Bool) -> Bool {\n        saved"),
    ("a decoded picture kept for a forgotten Mac", "static func keepsDecodedPicture(style: Style, saved: Bool) -> Bool {\n        style == .tiles && saved",
     "static func keepsDecodedPicture(style: Style, saved: Bool) -> Bool {\n        style == .tiles"),
    ("a decode given longer", "static let decodeBound: TimeInterval = 1", "static let decodeBound: TimeInterval = 5"),
    # Disconnect's fresh keyframe.
    ("asked when the end keeps no picture", "guard takesPreview, streaming else { return .stored }",
     "guard streaming else { return .stored }"),
    ("asked while nothing streams", "guard takesPreview, streaming else { return .stored }",
     "guard takesPreview else { return .stored }"),
    ("no Mac asked", "guard takesPreview, streaming else { return .stored }", "return .stored"),
    ("asked within the recovery's spacing", "if let since = sinceLastAsk, since < KeyframeRecovery.spacing { return askOut ? .awaitAsked : .stored }", ""),
    ("waits for an ask that came", "return askOut ? .awaitAsked : .stored }", "return .awaitAsked }"),
    ("never waits for the recovery's ask", "return askOut ? .awaitAsked : .stored }", "return .stored }"),
    ("the spacing's end still within it", "since < KeyframeRecovery.spacing", "since <= KeyframeRecovery.spacing"),
    ("the Mac's 1 s for the recovery's 2", "since < KeyframeRecovery.spacing", "since < 1"),
    ("a longer wait", "static let freshKeyframeWait: TimeInterval = 0.3", "static let freshKeyframeWait: TimeInterval = 3"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "ConnectionList.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O", mf, os.path.join(WT, "iOSClient/KeyframeRecovery.swift"), os.path.join(HERE, "main.swift"),
                        "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
