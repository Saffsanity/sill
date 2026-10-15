#!/usr/bin/env python3
"""Clipboard merge wire check, with sillclient.py and a synthetic, software-only loopback host.
Run after swift build -c release: python3 Scripts/clipboard-check/run.py
Only the test pasteboard is read or written. Only processes this script starts are stopped.
Receipts go to .build/clipboard-merge (ignored by Git).
"""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".build/clipboard-merge"
OUT.mkdir(parents=True, exist_ok=True)
BOARD = f"me.saffer.sill.test.clipboard-merge.{os.getpid()}"
PROBE = OUT / "board"
subprocess.run(["swiftc", str(Path(__file__).with_name("board.swift")), "-o", str(PROBE)], check=True)
processes = []
handles = []
checks = 0

def check(ok, what):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(what)
    print(f"PASS {what}", flush=True)

def board(mode, text=None):
    return subprocess.check_output([str(PROBE), BOARD, mode] + ([] if text is None else [text]), text=True).strip()

def host(label, disabled=False):
    log = OUT / f"{label}-host.log"
    handle = log.open("w")
    handles.append(handle)
    env = dict(os.environ, SILL_TEST_LOOPBACK="1", SILL_TEST_SOFTWARE_ENCODER="1", SILL_TEST_NO_ROUTER="1",
               SILL_TEST_PASTEBOARD=BOARD, SILL_TEST_CLIPBOARD_LOG="1")
    p = subprocess.Popen([str(ROOT / ".build/release/SillHost"), "--synthetic"] + (["--no-clipboard"] if disabled else []),
                         env=env, stdout=handle, stderr=subprocess.STDOUT, cwd=ROOT)
    processes.append(p)
    for _ in range(100):
        if p.poll() is not None:
            raise AssertionError("synthetic host exited before listening")
        ports = subprocess.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", str(p.pid)], capture_output=True, text=True)
        match = re.search(r"127\.0\.0\.1:(\d+) .*LISTEN", ports.stdout)
        if match:
            check("hardware encoder is never probed" in log.read_text(), "synthetic host forces software encoder")
            return p, match[1]
        time.sleep(.1)
    raise AssertionError("synthetic host did not listen on loopback")

def client(port, label, seconds, *flags):
    log = OUT / f"{label}-client.log"
    handle = log.open("w")
    handles.append(handle)
    p = subprocess.Popen([sys.executable, str(ROOT / "Scripts/sillclient.py"), str(port), str(seconds), "none", "--no-select", *flags],
                         stdout=handle, stderr=subprocess.STDOUT, cwd=ROOT)
    processes.append(p)
    return p, log

def finish(pair):
    p, log = pair
    check(p.wait(timeout=20) == 0, f"{log.stem} completed")
    return log.read_text()

def clips(text):
    return [line for line in text.splitlines() if "clipboard at " in line]

try:
    board("text", "preexisting")
    running, port = host("enabled")
    legacy = client(port, "text", 8, "--clipboard")
    images = client(port, "images", 8, '--raw32={"accepts":2}@0.1', '--raw32={}@4.8')
    stopped = client(port, "stopped", 8, "--clipboard", '--raw32={"stop":true}@1.8')
    silent = client(port, "unsubscribed", 8)
    start = time.monotonic()
    for at, mode, words in [(1, "text", "sample one"), (2.3, "image", None), (3.3, "both", "caption"),
                            (4.1, "marked", None), (5.5, "image", None), (6.5, "text", "sample two")]:
        time.sleep(max(0, start + at - time.monotonic()))
        board(mode, words)
    text, image, stop, unsub = [finish(p) for p in [legacy, images, stopped, silent]]
    check("clipboard=2" in text, "host advertises image generation 2")
    check(len(clips(text)) == 3 and all("image" not in l for l in clips(text)), "{} subscriber gets three texts and no images")
    check(len(clips(image)) == 4 and sum("image" in l for l in clips(image)) == 2, "accepts 2 gets images; {} renegotiates back to text")
    check(len(clips(stop)) == 1 and "sample one" in clips(stop)[0], "stop ends both text and images")
    check(not clips(unsub), "unsubscribed connection gets nothing")
    check(all("preexisting" not in s for s in [text, image, stop, unsub]), "connecting never exports the previous clipboard")
    check(all("caption" in s and "sample two" in s for s in [text, image]), "text works before and after image negotiation")
    png = board("png")
    relay_text = client(port, "relay-text", 3, "--clipboard")
    relay_images = client(port, "relay-images", 3, '--raw32={"accepts":2}@0.1')
    sender = client(port, "sender", 2, '--raw32=' + json.dumps({"image": png, "accepts": 2}, separators=(",", ":")) + '@0.6')
    finish(sender)
    got = json.loads(board("read"))
    check(got["image"] and got["own"], "viewer image reaches host pasteboard with the launch marker")
    relayed_text, relayed_image = finish(relay_text), finish(relay_images)
    check(not clips(relayed_text), "viewer image is not relayed to a {} subscriber")
    check(len(clips(relayed_image)) == 1 and "image" in clips(relayed_image)[0], "viewer image is relayed only to an image subscriber")
    check(len(base64.b64decode(png)) < 600_000, "fixture image fits the device payload cap")
    running.terminate()
    running.wait(timeout=10)
    board("text", "disabled baseline")
    _, port = host("disabled", disabled=True)
    disabled = finish(client(port, "disabled", 2, "--clipboard", '--copy=disabled copy@0.2'))
    check("clipboard=" not in disabled and not clips(disabled), "disabled host advertises no capability and sends nothing")
    check(json.loads(board("read"))["text"] == "disabled baseline", "disabled host ignores viewer writes")
    print(f"Wire checks: {checks} passed", flush=True)
finally:
    for p in reversed(processes):
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=10)
    for h in handles:
        h.close()
