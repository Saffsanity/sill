"""H3 (docs/update-notice-plan.md) mutants of DeviceGate.swift: each changes it in one place, is compiled
with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/DeviceGate.swift")
MUTANTS = [
    ("admits only above the floor", "DeviceGate.swift", "version(hello) >= floor", "version(hello) > floor"),
    ("no version counts as 1", "DeviceGate.swift", "hello?.appVersion.flatMap { SillVersion($0) } ?? .zero", "hello?.appVersion.flatMap { SillVersion($0) } ?? SillVersion(components: [1])"),
    ("iPhone anywhere in the name", "DeviceGate.swift", "if name.hasPrefix(\"iPhone\") { return \"iPhone\" }", "if name.contains(\"iPhone\") { return \"iPhone\" }"),
    ("device word from the raw name", "DeviceGate.swift", "let name = SafeText.label(hello?.device ?? \"\")\n        if name.hasPrefix(\"iPhone\")", "let name = hello?.device ?? \"\"\n        if name.hasPrefix(\"iPhone\")"),
    ("no minimumVersion", "DeviceGate.swift", "minimumVersion: floor.description, reconnect: false)", "minimumVersion: nil, reconnect: false)"),
    ("reconnect left out", "DeviceGate.swift", "minimumVersion: floor.description, reconnect: false)", "minimumVersion: floor.description, reconnect: nil)"),
    ("no hello reads as no version", "DeviceGate.swift", "what = \"an older Sill\"", "what = \"no version\""),
    ("hello line without the endpoint", "DeviceGate.swift", "if !name.isEmpty { line += \" (\\(endpoint))\" }", ""),
    ("slowed from the seventh", "DeviceGate.swift", "count >= loopRefusals", "count > loopRefusals"),
    ("hello line's name not cleaned", "DeviceGate.swift", "let name = SafeText.label(hello.device ?? \"\")\n        let v = SafeText.label(hello.appVersion ?? \"\", limit: 32)", "let name = hello.device ?? \"\"\n        let v = SafeText.label(hello.appVersion ?? \"\", limit: 32)"),
    ("hello line's build not cleaned", "DeviceGate.swift", "let build = SafeText.label(hello.build ?? \"\", limit: 32)", "let build = hello.build ?? \"\""),
    ("a shipped floor above 0", "DeviceGate.swift", "package static let minimumDeviceVersion = \"0\"", "package static let minimumDeviceVersion = \"0.1\""),
    ("a shipped floor that does not parse", "DeviceGate.swift", "package static let minimumDeviceVersion = \"0\"", "package static let minimumDeviceVersion = \"zero\""),
    ("count line always plural", "DeviceGate.swift", "Refused \\(n) more connection\\(n == 1 ? \"\" : \"s\")", "Refused \\(n) more connections"),
]
caught = 0
for name, _, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "DeviceGate.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
