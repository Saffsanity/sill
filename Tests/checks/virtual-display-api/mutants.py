"""Mutants of VirtualDisplay.swift's private API surface, its TypeEncoding, Runtime.method's decision and
the applySettings: call (#87, #62): each changes it in one place, is compiled with the check by build.sh
and must make it fail.
usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/VirtualDisplay.swift")
ACCEPTED = 'expected.first == "B" ? [expected, "c" + expected.dropFirst()] : [expected]'
MUTANTS = [
    # TypeEncoding.accepted
    ("a BOOL return only as B (the c spelling dropped)", ACCEPTED,
     'expected.first == "B" ? [expected] : [expected]'),
    ("a BOOL return only as c", ACCEPTED,
     'expected.first == "B" ? ["c" + expected.dropFirst()] : [expected]'),
    ("every return also as c", 'expected.first == "B" ?', 'expected.first != nil ?'),
    ("a B anywhere counts as a BOOL return", 'expected.first == "B" ?', 'expected.contains("B") ?'),
    ("unsigned char for signed", '"c" + expected.dropFirst()', '"C" + expected.dropFirst()'),
    ("the c put before the B", '"c" + expected.dropFirst()', '"c" + expected'),
    ("written c, also taken as B", ': [expected]\n',
     ': (expected.first == "c" ? [expected, "B" + expected.dropFirst()] : [expected])\n'),
    # TypeEncoding.normalized
    ("the offsets kept", "String(encoding.filter { !$0.isNumber })", "String(encoding)"),
    ("only the offsets kept", "String(encoding.filter { !$0.isNumber })", "String(encoding.filter { $0.isNumber })"),
    # The surface
    ("applySettings: written c", '("CGVirtualDisplay", "applySettings:", "B@:@"),',
     '("CGVirtualDisplay", "applySettings:", "c@:@"),'),
    ("setHiDPI: written as taking a BOOL", '("CGVirtualDisplaySettings", "setHiDPI:", "v@:I"),',
     '("CGVirtualDisplaySettings", "setHiDPI:", "v@:B"),'),
    ("a method left off the surface", '        ("CGVirtualDisplay", "displayID", "I@:"),\n', ""),
    ("an entry written with offsets", '("CGVirtualDisplay", "initWithDescriptor:", "@@:@"),',
     '("CGVirtualDisplay", "initWithDescriptor:", "@24@0:8@16"),'),
    # Runtime.method's decision, which the check asks through methodProblem about classes made at run time
    ("Runtime.method's guard back to one spelling (as before #87)",
     "guard accepted.contains(found) else {", "guard found == encoding else {"),
    ("Runtime.method without normalized",
     ".map { VirtualDisplay.TypeEncoding.normalized(String(cString: $0)) }", ".map { String(cString: $0) }"),
    # The applySettings: call, which the check sends to classes made at run time
    ("applySettings: sent expecting c@:@", '"applySettings:", "B@:@", as: Runtime.ApplyFn.self)',
     '"applySettings:", "c@:@", as: Runtime.ApplyFn.self)'),
    ("applySettings:'s NO read as YES", "return fn(display, sel, settings).boolValue",
     "return fn(display, sel, settings).boolValue || true"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "VirtualDisplay.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"{name}: did not compile (caught)"); caught += 1; continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            caught += 1
            failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
