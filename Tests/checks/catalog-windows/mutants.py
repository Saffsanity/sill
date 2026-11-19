"""Mutants of CatalogWindows.swift (issue #114): each changes it in one place, is compiled with the check
and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/CatalogWindows.swift")
MUTANTS = [
    ("the window server's own windows listed (the owner's name not asked)",
     "guard let name = w.appName, !name.isEmpty else { return false }", "guard w.appName != nil else { return false }"),
    ("every layer from 0 up listed", "w.layer == 0 &&", "w.layer >= 0 &&"),
    ("every layer from 0 down listed", "w.layer == 0 &&", "w.layer <= 0 &&"),
    ("100 points wide listed", "w.width > 100", "w.width >= 100"),
    ("100 points tall listed", "w.height > 100", "w.height >= 100"),
    ("Sill's own windows listed", " && w.pid != ownPID", ""),
    ("LayerProbeParent listed",
     'if (w.title ?? "").lowercased().contains("layerprobe") { return .layerProbe }', ""),
    ("LayerProbeParent only in lower case",
     '(w.title ?? "").lowercased().contains("layerprobe")', '(w.title ?? "").contains("layerprobe")'),
    ("macOS's own interface listed", "if systemInterface.contains(id) { return .systemInterface }", ""),
    ("Stage Manager's WindowManager not in the list", '"com.apple.windowmanager",', ""),
    ("the Dock not in the list", '"com.apple.dock",', ""),
    ("Control Center not in the list", '"com.apple.controlcenter",', ""),
    ("the menu bar's extras not in the list", '"com.apple.systemuiserver",', ""),
    ("Notification Center not in the list", '"com.apple.notificationcenterui",', ""),
    ("the screenshot tools not in the list", '"com.apple.screencaptureui",', ""),
    ("bundle identifiers compared in their own case", 'let id = (w.bundleID ?? "").lowercased()', 'let id = w.bundleID ?? ""'),
    ("an identifier that starts with a listed one matched",
     "systemInterface.contains(id)", "systemInterface.contains { id.hasPrefix($0) }"),
    ("an identifier that ends with a listed one matched",
     "systemInterface.contains(id)", "systemInterface.contains { id.hasSuffix($0) }"),
    ("a tool's untitled window listed", "if untitled && id.isEmpty { return .untitledWithoutBundle }", ""),
    ("every untitled window left out (an app's too)", "if untitled && id.isEmpty", "if untitled"),
    ("every window of a tool with no bundle left out (a titled one too)", "if untitled && id.isEmpty", "if id.isEmpty"),
    ("a title of spaces counts as a title",
     '(w.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', '(w.title ?? "").isEmpty'),
    ("a title of a newline and a tab counts as a title",
     ".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty", ".trimmingCharacters(in: .whitespaces).isEmpty"),
    ("the helpers' windows listed", "isAppWindow(w, ownPID: ownPID) && helper(w) == nil", "isAppWindow(w, ownPID: ownPID)"),
    ("a line for LayerProbeParent",
     "guard let kind = helper(w), kind != .layerProbe else { continue }", "guard let kind = helper(w) else { continue }"),
    ("a line at every look", 'guard named.insert("\\(id) \\(name)").inserted else { continue }', 'named.insert("\\(id) \\(name)")'),
    ("one line for every tool with no bundle (keyed by the identifier alone)",
     'named.insert("\\(id) \\(name)")', "named.insert(id)"),
    ("a line for windows that were never tiles",
     "for w in windows where isAppWindow(w, ownPID: ownPID) {", "for w in windows {"),
    ("the two lines' words swapped", "lines.append(kind == .systemInterface", "lines.append(kind != .systemInterface"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "CatalogWindows.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"{name}: did not compile (caught)"); caught += 1; continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
            code, out = r.returncode, r.stdout
        except subprocess.TimeoutExpired:
            code, out = -1, "FAIL timed out"
        if code != 0:
            caught += 1
            failed = [l for l in out.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit {code}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
