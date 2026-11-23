"""Mutants of the app icon choice: one-line changes of AppIconChoice.swift (iOSClient), each compiled with the
check (main.swift), and changes of the wiring the check reads (the project's icon settings, the documents, the
previews, Sill for Mac's icon) made in a copy of those files, which the unchanged check is pointed at. Every one
must make the check fail. usage: mutants.py"""
import os, shutil, subprocess, sys, tempfile
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "app-icon")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/AppIconChoice.swift")
orig = open(SRC).read()

SOURCE = [
    # The choices.
    ("C1 a new install shows the community's", "static let standard = AppIconChoice.original", "static let standard = AppIconChoice.community"),
    ("C2 the community's first in Settings", "    case original\n    case community\n", "    case community\n    case original\n"),
    ("C3 the original's document under another name", 'case .original: return "AppIcon"', 'case .original: return "AppIconOriginal"'),
    ("C4 the community's name misspelt (setAlternateIconName would fail)", 'case .community: return "AppIconCommunity"', 'case .community: return "AppIconcommunity"'),
    ("C5 the original asked for by name, not as the primary", "var alternateIconName: String? { self == Self.standard ? nil : iconName }",
     "var alternateIconName: String? { iconName }"),
    ("C6 the alternates asked for as the primary", "var alternateIconName: String? { self == Self.standard ? nil : iconName }",
     "var alternateIconName: String? { self != Self.standard ? nil : iconName }"),
    ("C7 the previews under another name", 'var previewImageName: String { iconName + "Preview" }', 'var previewImageName: String { "Preview" + iconName }'),
    ("C8 one id for both", "var id: String { rawValue }", 'var id: String { "icon" }'),
    ("C9 the windowsill's name misspelt (setAlternateIconName would fail)", 'case .windowsill: return "AppIconWindowsill"',
     'case .windowsill: return "AppIconWindowSill"'),
    ("C10 the windowsill before the community in Settings", "    case community\n    case windowsill\n", "    case windowsill\n    case community\n"),
    # The words.
    ("W1 the community's author left out", 'case .community: return "grub-basket"', "case .community: return nil"),
    ("W2 the author's login misspelt", 'case .community: return "grub-basket"', 'case .community: return "grubbasket"'),
    ("W3 the credit with an at sign", 'var credit: String? { author.map { "by \\($0)" } }', 'var credit: String? { author.map { "by @\\($0)" } }'),
    ("W4 the original called Default", 'case .original: return "Original"', 'case .original: return "Default"'),
    ("W5 the community's called Alternate", 'case .community: return "Community"', 'case .community: return "Alternate"'),
    ("W6 VoiceOver without the credit", 'var spoken: String { "\\(title) icon" + (credit.map { ", \\($0)" } ?? "") }', 'var spoken: String { "\\(title) icon" }'),
    ("W7 VoiceOver without \"icon\"", 'var spoken: String { "\\(title) icon" + (credit.map { ", \\($0)" } ?? "") }',
     'var spoken: String { title + (credit.map { ", \\($0)" } ?? "") }'),
    ("W8 the group called App Icons", 'static let title = "App Icon"', 'static let title = "App Icons"'),
    ("W9 the footnote without the device's word", "this \\(device)’s Home Screen", "this device’s Home Screen"),
    ("W10 the footnote without the way back",
     " You can switch back to \\(AppIconChoice.standard.title) here whenever you’re connected to a Mac.", ""),
    ("W11 the hints the wrong way round", 'selected ? "Sill’s icon now." : "Changes Sill’s icon on the Home Screen to this one."',
     'selected ? "Changes Sill’s icon on the Home Screen to this one." : "Sill’s icon now."'),
    ("W12 the refusal silent", 'static let failed = "Sill’s icon didn’t change. Try again in a moment."', 'static let failed = ""'),
    ("W13 a straight apostrophe in the footnote", "this \\(device)’s Home Screen", "this \\(device)'s Home Screen"),
    ("W14 the footnote promising the way back always (Settings is only a session's)",
     " You can switch back to \\(AppIconChoice.standard.title) here whenever you’re connected to a Mac.",
     " \\(AppIconChoice.standard.title) is always here to switch back to."),
    ("W15 the footnote's way back without its Mac", "here whenever you’re connected to a Mac.", "here."),
    ("W16 the windowsill's author left out", 'case .windowsill: return "joannou"', "case .windowsill: return nil"),
    ("W17 the windowsill called Cat", 'case .windowsill: return "Windowsill"', 'case .windowsill: return "Cat"'),
    # Which icon shows.
    ("S1 no name reads as the community's", "guard let name else { return standard }", "guard let name else { return .community }"),
    ("S2 an unknown name reads as the community's", "return allCases.first { $0.alternateIconName == name } ?? standard",
     "return allCases.first { $0.alternateIconName == name } ?? .community"),
    ("S3 a name matched without its case", "return allCases.first { $0.alternateIconName == name } ?? standard",
     "return allCases.first { $0.alternateIconName?.lowercased() == name.lowercased() } ?? standard"),
    ("S4 a name matched by its start (a later icon's read as this one)", "return allCases.first { $0.alternateIconName == name } ?? standard",
     "return allCases.first { $0.alternateIconName.map { name.hasPrefix($0) } ?? false } ?? standard"),
    ("S5 a name matched with its white space trimmed", "return allCases.first { $0.alternateIconName == name } ?? standard",
     "return allCases.first { $0.alternateIconName == name.trimmingCharacters(in: .whitespaces) } ?? standard"),
    # What a tap asks.
    ("R1 judged against the choice it reads as (Original never clears an unknown name)",
     "choice.alternateIconName == name ? .none : .set(choice.alternateIconName)",
     "choice == current(alternateIconName: name) ? .none : .set(choice.alternateIconName)"),
    ("R2 always asks (an alert for the icon already set)", "choice.alternateIconName == name ? .none : .set(choice.alternateIconName)",
     ".set(choice.alternateIconName)"),
    ("R3 asks for the name already set", "choice.alternateIconName == name ? .none : .set(choice.alternateIconName)",
     "choice.alternateIconName == name ? .none : .set(name)"),
    ("R4 never asks", "choice.alternateIconName == name ? .none : .set(choice.alternateIconName)", ".none"),
    # Whether the group shows.
    ("O1 shown where iOS cannot change the icon", "supportsAlternateIcons && allCases.count > 1", "allCases.count > 1"),
    ("O2 never shown", "supportsAlternateIcons && allCases.count > 1", "supportsAlternateIcons && allCases.count > allCases.count"),
]

PBX = "iOSClient/Sill.xcodeproj/project.pbxproj"
# Changes of the wiring: (name, file, old, new, found) for a text change, `old` found that many times in the file and
# the first replaced (every one when found is negative: -n for n found); (name, path, None, None, 0) removes the
# file or folder; (name, path, "", text, None) writes a new file.
WIRING = [
    ("P1 the first configuration without the alternates", PBX, "\t\t\t\tASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"AppIconCommunity AppIconWindowsill\";\n", "", 2),
    ("P2 neither configuration with the alternates", PBX, "\t\t\t\tASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"AppIconCommunity AppIconWindowsill\";\n", "", -2),
    ("P3 an alternate the choices do not have", PBX, 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIconCommunity AppIconWindowsill";',
     'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIconCommunity AppIconWindowsill AppIconPride";', 2),
    ("P4 every icon set included instead", PBX, "\t\t\t\tASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"AppIconCommunity AppIconWindowsill\";\n",
     "\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;\n", -2),
    ("P5 another primary icon", PBX, "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "ASSETCATALOG_COMPILER_APPICON_NAME = AppIconCommunity;", 2),
    ("P6 the community's document not a resource", PBX, "\t\t\t\tA1000001000000000000A1C1 /* AppIconCommunity.icon in Resources */,\n", "", 1),
    ("P7 the original's document a plain folder", PBX, "lastKnownFileType = folder.iconcomposer.icon; name = AppIcon.icon;",
     "lastKnownFileType = folder; name = AppIcon.icon;", 1),
    ("P8 the community's document at another path", PBX, "path = ../Packaging/AppIconCommunity.icon;", "path = ../design/AppIconCommunity.icon;", 1),
    ("P9 the windowsill left out of the alternates", PBX, 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIconCommunity AppIconWindowsill";',
     "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = AppIconCommunity;", -2),
    ("P10 the windowsill's document not a resource", PBX, "\t\t\t\tA1000001000000000000A1C4 /* AppIconWindowsill.icon in Resources */,\n", "", 1),
    ("D1 a layer of the original missing", "Packaging/AppIcon.icon/Assets/ipad.svg", None, None, 0),
    ("D2 a layer of the community's missing", "Packaging/AppIconCommunity.icon/Assets/island.svg", None, None, 0),
    ("D3 the community's document without its icon.json", "Packaging/AppIconCommunity.icon/icon.json", None, None, 0),
    ("D4 the original's icon.json not JSON", "Packaging/AppIcon.icon/icon.json", '"groups" : [', '"groups" : [[', 1),
    ("D5 a layer naming no picture", "Packaging/AppIcon.icon/icon.json", '"image-name" : "window.svg",\n', "", 1),
    ("D6 a layer of the windowsill's missing", "Packaging/AppIconWindowsill.icon/Assets/sill.svg", None, None, 0),
    ("A1 the old icon set back beside the document", "iOSClient/Assets.xcassets/AppIcon.appiconset/Contents.json", "", '{"images":[]}', None),
    ("A2 the community's preview missing", "iOSClient/Assets.xcassets/AppIconCommunityPreview.imageset", None, None, 0),
    ("A3 the original's preview naming a picture that is not there", "iOSClient/Assets.xcassets/AppIconPreview.imageset/Contents.json",
     '"filename" : "AppIconPreview.png"', '"filename" : "AppIconPreview@3x.png"', 1),
    ("A4 the windowsill's preview missing", "iOSClient/Assets.xcassets/AppIconWindowsillPreview.imageset", None, None, 0),
    ("M1 Sill for Mac's icon another", "Packaging/Info.plist", "<key>CFBundleIconName</key>\n\t<string>AppIcon</string>",
     "<key>CFBundleIconName</key>\n\t<string>AppIconCommunity</string>", 1),
    ("M2 make-app.sh compiling the community's for Sill for Mac", "Scripts/make-app.sh", 'doc="$PWD/Packaging/AppIcon.icon"',
     'doc="$PWD/Packaging/AppIconCommunity.icon"', 1),
]
# What the check reads, copied for the wiring's mutants.
READS = [PBX, "Packaging/AppIcon.icon", "Packaging/AppIconCommunity.icon", "Packaging/AppIconWindowsill.icon",
         "iOSClient/Assets.xcassets", "Packaging/Info.plist", "Scripts/make-app.sh"]

caught = 0
total = len(SOURCE) + len(WIRING)
exe = os.path.join(OUT, "check")
c = subprocess.run(["swiftc", "-O", SRC, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
if c.returncode != 0:
    print(f"the check does not compile: {c.stderr.strip()[:300]}"); sys.exit(1)
base = subprocess.run([exe, ROOT], capture_output=True, text=True, timeout=120)
if base.returncode != 0:
    print("the check fails without a mutant: " + next((l for l in base.stdout.splitlines() if l.startswith("FAIL")), "?")); sys.exit(1)

def judge(name, r):
    global caught
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else 'exit ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")

for name, old, new in SOURCE:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "AppIconChoice.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    mexe = os.path.join(OUT, "mutant")
    if os.path.exists(mexe): os.remove(mexe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", mexe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    judge(name, subprocess.run([mexe, ROOT], capture_output=True, text=True, timeout=120))

for name, rel, old, new, count in WIRING:
    with tempfile.TemporaryDirectory(dir=OUT) as tmp:
        for item in READS:
            src, dst = os.path.join(ROOT, item), os.path.join(tmp, item)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dst)
        target = os.path.join(tmp, rel)
        if old is None:
            if not os.path.exists(target):
                print(f"{name}: NOT APPLIED ({rel} is not there)"); continue
            (shutil.rmtree if os.path.isdir(target) else os.remove)(target)
        elif count is None:        # a new file
            os.makedirs(os.path.dirname(target), exist_ok=True)
            open(target, "w").write(new)
        else:
            text = open(target).read()
            if text.count(old) != abs(count):
                print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times in {rel}, wanted {abs(count)})"); continue
            open(target, "w").write(text.replace(old, new) if count < 0 else text.replace(old, new, 1))
        judge(name, subprocess.run([exe, tmp], capture_output=True, text=True, timeout=120))

print(f"{caught} of {total} mutants caught")
sys.exit(0 if caught == total else 1)
