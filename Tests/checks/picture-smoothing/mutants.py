"""Mutants of PictureSmoothing.swift and StreamShader.swift: each changes one of them in one place, is
compiled with both checks (the model's and the GPU's) and must make one of them fail. usage:
mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = "iOSClient/PictureSmoothing.swift"; SHADER = "iOSClient/StreamShader.swift"
MUTANTS = [
    ("an unknown value kept", MODEL, "raw.flatMap(PictureSmoothing.init(rawValue:)) ?? .automatic", ".automatic"),
    ("Automatic uses Sill's renderer", MODEL, "var usesOwnRenderer: Bool { self != .automatic }", "var usesOwnRenderer: Bool { true }"),
    ("Low is nearest", MODEL, "case .low: return .bilinear", "case .low: return .nearest"),
    ("shader modes swapped", MODEL, "case .bicubic: return 2\n            case .lanczos: return 3", "case .bicubic: return 3\n            case .lanczos: return 2"),
    ("the reference never widens", MODEL, "let s = min(scale, 1), r = filter.support / s", "let s = 1.0, r = filter.support / s"),
    ("the reference unnormalized", MODEL, "return sum == 0 ? row[min(m - 1, max(0, Int(c.rounded())))] : acc / sum", "return acc"),
    ("bicubic's far lobe dropped", MODEL, "if x < 2 { return -0.5 * x * x * x + 2.5 * x * x - 4 * x + 2 }", ""),
    ("Lanczos-2", MODEL, "guard x < 3 else { return 0 }", "guard x < 2 else { return 0 }"),
    ("the shader never widens", SHADER, "float s = min(scale, 1.0);", "float s = 1.0;"),
    ("the shader unnormalized", SHADER, ": acc / sum;", ": acc;"),
    ("the shader's pixel centre off by half", SHADER, "float c = along / scale - 0.5;", "float c = along / scale;"),
    ("the shader's bicubic far lobe dropped", SHADER, "if (x < 2.0) { return -0.5 * x * x * x + 2.5 * x * x - 4.0 * x + 2.0; }", ""),
    ("the shader's Lanczos-2", SHADER, "if (x >= 3.0) { return 0.0; }", "if (x >= 2.0) { return 0.0; }"),
    ("the shader's nearest rounds", SHADER, "int k = min(m - 1, int(along / scale));", "int k = min(m - 1, int(round(along / scale)));"),
    ("the shader reads the wrong axis", SHADER, "acc += src.read(across ? uint2(kk, other) : uint2(other, kk)) * w;", "acc += src.read(uint2(kk, other)) * w;"),
    ("no clamp on the last pass", SHADER, "return p.clampOut != 0 ? clamp(out, 0.0, 1.0) : out;", "return out;"),
]

def build_and_run(model, shader, t):
    check, gpu = os.path.join(t, "check"), os.path.join(t, "gpu")
    os.makedirs(os.path.join(t, "g"), exist_ok=True)
    gmain = os.path.join(t, "g", "main.swift"); open(gmain, "w").write(open(os.path.join(HERE, "gpu.swift")).read())
    subprocess.run(["swiftc", "-O", model, os.path.join(HERE, "main.swift"), "-o", check], capture_output=True)
    subprocess.run(["swiftc", "-O", model, shader, gmain, "-o", gpu, "-framework", "Metal"], capture_output=True)
    if not (os.path.exists(check) and os.path.exists(gpu)): return None, "did not compile"
    for exe in (check, gpu):
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            fails = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
            return True, (fails[0][:90] if fails else f"exit status {r.returncode}")
        if "skipped" in r.stdout and exe == gpu:
            return False, "no Metal device: the GPU check could not judge it"
    return False, ""

caught = 0
for name, which, old, new in MUTANTS:
    src = open(os.path.join(WT, which)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        model, shader = os.path.join(t, "PictureSmoothing.swift"), os.path.join(t, "StreamShader.swift")
        open(model, "w").write(open(os.path.join(WT, MODEL)).read())
        open(shader, "w").write(open(os.path.join(WT, SHADER)).read())
        open(model if which == MODEL else shader, "w").write(src.replace(old, new, 1))
        ok, why = build_and_run(model, shader, t)
        if ok is None: print(f"{name}: {why}")
        elif ok: caught += 1; print(f"{name}: caught ({why})")
        else: print(f"{name}: NOT CAUGHT {why}")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
