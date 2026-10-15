#!/usr/bin/env python3
"""Run ClipboardSync without launching the viewer app or accessing the general pasteboard.
The only substitutions are the test pasteboard, its read permission, isolated defaults, and the
session stub in viewer.swift. The subscription, timer, read/write and image policies are production code.
A second run removes accepts at the actual viewer send call; the smoke check must detect it.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="sill-clipboard-viewer-") as t:
    target = Path(t)
    files = []
    for source in sorted((ROOT / "Sources/StreamProtocol").glob("*.swift")):
        text = source.read_text()
        if source.name == "SideStreams.swift":
            text = text.replace("NSPasteboard.general", "testBoard")
            start = text.index("    public static var access: ClipboardPolicy.MacAccess {")
            end = text.index("    /// Unprompted reads only:", start)
            text = text[:start] + "    public static var access: ClipboardPolicy.MacAccess { testAccess }\n\n" + text[end:]
        path = target / source.name
        path.write_text(text)
        files.append(str(path))
    viewer = ROOT / "Sources/MacClient/ClipboardSync.swift"
    source = viewer.read_text().replace("import StreamProtocol\n", "").replace("NSPasteboard.general", "testBoard").replace("UserDefaults.standard", "testDefaults")
    actual = target / "ClipboardSync.swift"
    main = target / "main.swift"
    main.write_text((HERE / "viewer.swift").read_text())
    for mutant in [False, True]:
        text = source
        if mutant:
            old = "client.sendClipboard(request)"
            assert text.count(old) == 1
            text = text.replace(old, "client.sendClipboard(Clipboard())")
        actual.write_text(text)
        exe = target / "viewer-check"
        subprocess.run(["swiftc", "-O", *files, str(actual), str(main), "-o", str(exe)], check=True)
        result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
        if mutant:
            assert result.returncode != 0 and "text host gets the viewer’s accepts 2 subscription" in result.stdout, result.stdout
            print("Viewer mutant caught: 1 of 1 (subscribes without accepts)", flush=True)
        else:
            assert result.returncode == 0, result.stdout + result.stderr
            print(result.stdout, end="", flush=True)
