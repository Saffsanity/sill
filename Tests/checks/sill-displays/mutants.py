"""Mutants of SillDisplayRole.swift (the roles' identities, compiled with the check) and of the wiring the check reads as
text (SillDisplays.swift, VirtualStage.swift, StreamCoordinator.swift): each changes one file in one place and must make
the check fail. The role file's mutants are compiled from a copy; the wiring's change the source in place and are put
back after, whatever happens. A mutant that does not compile is caught.
usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
ROLE = "Sources/SillHost/SillDisplayRole.swift"
MANAGER = "Sources/SillHost/SillDisplays.swift"
STAGE = "Sources/SillHost/VirtualStage.swift"
COORD = "Sources/SillHost/StreamCoordinator.swift"
MUTANTS = [
    # The roles' identities (macOS remembers a display by them; DesktopDisplays.role reads them)
    (ROLE, "R1 the stage's display with the Desktop's product", "case .stage: return DesktopDisplays.stageProduct",
     "case .stage: return DesktopDisplays.desktopProduct"),
    (ROLE, "R2 the Desktop's display with the stage's product", "case .desktop: return DesktopDisplays.desktopProduct",
     "case .desktop: return DesktopDisplays.stageProduct"),
    (ROLE, "R3 the Desktop's serial the stage's", "case .desktop: return 2", "case .desktop: return 1"),
    (ROLE, "R4 the stage's serial changed (a new display to macOS)", "case .stage: return 1", "case .stage: return 3"),
    (ROLE, "R5 the Desktop's display named as the stage's", 'case .desktop: return "Sill Desktop"', 'case .desktop: return "Sill"'),
    (ROLE, "R6 the Desktop's marker word one the next launch does not read", "    case desktop\n", '    case desktop = "headless"\n'),
    (ROLE, "R7 another vendor", "var vendor: UInt32 { DesktopDisplays.sillVendor }", "var vendor: UInt32 { 0x5112 }"),
    # SillDisplays
    (MANAGER, "W1 made without the role's identity", "vendorID: role.vendor, productID: role.product, serialNum: role.serial)",
     "vendorID: 0x5111, productID: 0x0001, serialNum: 1)"),
    (MANAGER, "W2 a make that throws keeps the guard's marker", "            makeGuard?.made(cameUp: false)\n            throw error\n",
     "            throw error\n"),
    (MANAGER, "W3 the marker kept once the display is up", "        makeGuard?.made(cameUp: d.bounds.width > 0)\n", ""),
    (MANAGER, "W4 every marker says stage", "makeGuard?.willMake(role.rawValue)", "makeGuard?.willMake(\"stage\")"),
    (MANAGER, "W5 the catalog not told of the stage's display", "        if role == .stage { catalog.stageDisplayIDs.insert(d.displayID) }\n", ""),
    (MANAGER, "W6 removed without being destroyed (gone only when its object goes)", "        let id = d.displayID\n        d.destroy()\n",
     "        let id = d.displayID\n"),
    (MANAGER, "W7 an old display's termination taken for the new one's",
     "guard gen == generations[role], made[role] != nil, let handler = onLost[role] else { return }",
     "guard made[role] != nil, let handler = onLost[role] else { return }"),
    # The stage
    (STAGE, "W8 the stage makes its display itself again", "d = try displays.make(.stage, widthPt:",
     "d = try VirtualDisplay(name: \"Sill\", widthPt:"),
    (STAGE, "W9 the stage's marker after its old display goes", "        if mayMake, !guarded { displays.willMake(.stage) }\n        destroyDisplay()\n",
     "        destroyDisplay()\n        if mayMake, !guarded { displays.willMake(.stage) }\n"),
    (STAGE, "W10 the stage tells the catalog itself", "        creationFailures = 0\n        let created = Self.ms(since: t0)\n",
     "        creationFailures = 0\n        catalog.stageDisplayIDs.insert(d.displayID)\n        let created = Self.ms(since: t0)\n"),
    (STAGE, "W11 the stage's removal not through SillDisplays", "if let id = displays.remove(.stage) {", "if let id = display?.displayID {"),
    (STAGE, "W12 the stage never hears its display lost", "        displays.onLost[.stage] = { [weak self] in self?.displayLost() }\n", ""),
    (STAGE, "W13 the stage ignores the guard", "guarded = displays.guardHolds", "guarded = false"),
    (STAGE, "W14 the stage's display waited for without the guard", "let online = await displays.waitUntilOnline(d, timeout: 3)",
     "let online = await d.waitUntilOnline(timeout: 3)"),
    # The Desktop's display (the coordinator)
    (COORD, "W15 the coordinator makes the Desktop's display itself again", "d = try displays.make(.desktop, widthPt:",
     "d = try VirtualDisplay(name: \"Sill Desktop\", widthPt:"),
    (COORD, "W16 the Desktop's marker not written", "            displays.willMake(.desktop)\n            if testHeadlessFile != nil {",
     "            if testHeadlessFile != nil {"),
    (COORD, "W17 the Desktop's display waited for without the guard", "_ = await displays.waitUntilOnline(d, timeout: 3)",
     "_ = await d.waitUntilOnline(timeout: 3)"),
    (COORD, "W18 a test host makes its display (no longer only said)", "                displays.say(.desktop)\n",
     "                displays.willMake(.desktop)\n"),
    (COORD, "W19 Quit leaves the Desktop's display", "        displays.removeAll()             // the Desktop's display", "        // the Desktop's display"),
    (COORD, "W20 the coordinator registers its own callback again", "        displays.watchReconfiguration { [weak self] in\n",
     "        CGDisplayRegisterReconfigurationCallback({ _, _, _ in }, nil)\n        displays.watchReconfiguration { [weak self] in\n"),
    (COORD, "W21 the coordinator keeps a display of its own", "private var headlessDisplay: VirtualDisplay? { displays.display(.desktop) }",
     "private var headlessDisplay: VirtualDisplay?"),
    (MANAGER, "W22 a said display not taken as up for the guard", "        said.insert(role)\n        makeGuard?.made(cameUp: true)\n",
     "        said.insert(role)\n"),
    (MANAGER, "W23 remove keeps a said display", "        said.remove(role)\n        listedBy[role] = nil\n", "        listedBy[role] = nil\n"),
    (MANAGER, "W24 removeAll misses the Desktop's display", "for role in SillDisplayRole.allCases { remove(role) }",
     "for role in [SillDisplayRole.stage] { remove(role) }"),
    (MANAGER, "W25 a change's beginning taken for a change", "guard !flags.contains(.beginConfigurationFlag), let context else { return }",
     "guard let context else { return }"),
    (MANAGER, "W26 registered at every call", "        guard onReconfigured == nil else { return }\n", ""),
]
caught = 0
originals = {}
try:
    for path, name, old, new in MUTANTS:
        full = os.path.join(WT, path)
        orig = originals.setdefault(path, open(full).read())
        if orig.count(old) != 1:
            print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
        with tempfile.TemporaryDirectory() as t:
            exe = os.path.join(t, "c")
            try:
                if path == ROLE:
                    mf = os.path.join(t, "SillDisplayRole.swift"); open(mf, "w").write(orig.replace(old, new, 1))
                    subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
                else:
                    open(full, "w").write(orig.replace(old, new, 1))
                    subprocess.run([os.path.join(HERE, "build.sh"), WT, exe], capture_output=True, text=True)
                if not os.path.exists(exe):
                    print(f"{name}: did not compile (caught)"); caught += 1; continue
                r = subprocess.run([exe, WT], capture_output=True, text=True, timeout=300)
            finally:
                if path != ROLE: open(full, "w").write(orig)
        if r.returncode != 0:
            caught += 1
            failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
finally:
    for path, text in originals.items():
        open(os.path.join(WT, path), "w").write(text)
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
