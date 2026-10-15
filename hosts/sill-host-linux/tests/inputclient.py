#!/usr/bin/env python3
r"""Sends a device's input (kind 8) to a Linux host in a Docker container, over the plain door.

usage: inputclient.py PORT SOURCE STEP...
  SOURCE   desktop or window:ID (decimal X window id): what the device picks first
  STEP     move=X,Y            pointer to fractions X,Y of the source
           click=X,Y           left button down and up there
           rclick=X,Y          right button down and up there
           scroll=X,Y,DX,DY    a scroll gesture: began, 10 deltas of DX/10,DY/10 (fractions of the
                               source; positive DY moves the content down), ended
           key=USAGE[,MODS]    a HID usage (hex with 0x, or decimal) down then up; MODS the protocol's
                               bits (shift 1<<17, control 1<<18, option 1<<19, command 1<<20)
           keydown=USAGE[,MODS] / keyup=USAGE[,MODS]
           text=STRING         typed text (\n is Return)
           sleep=S             wait S seconds

It refuses to connect unless 127.0.0.1:PORT is published by a running container whose name starts
with "sill-linux-" (docker ps), so it can never send input to a Mac host (Sill.app or SillHost) on
this machine. Waits for the first video frame before the first step, and prints each step.
"""
import json, socket, struct, subprocess, sys, time


def msg(kind, payload=b""):
    return struct.pack(">BdBI", kind, time.time(), 0, len(payload)) + payload


def guard(port):
    out = subprocess.run(["docker", "ps", "--format", "{{.Names}}\t{{.Ports}}"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        name, _, ports = line.partition("\t")
        if name.startswith("sill-linux-") and f"127.0.0.1:{port}->" in ports:
            return name
    sys.exit(f"refused: 127.0.0.1:{port} is not published by a sill-linux-* container")


def num(s):
    return int(s, 16) if s.lower().startswith("0x") else int(s)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    port, source, steps = int(sys.argv[1]), sys.argv[2], sys.argv[3:]
    container = guard(port)
    sel = {"desktop": {}} if source == "desktop" else {"window": {"_0": int(source.split(":", 1)[1])}}
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.sendall(msg(23, json.dumps({"appVersion": "0.5.1", "protocol": 1, "device": "inputclient"}).encode()))
    s.sendall(msg(6, json.dumps(sel).encode()))
    # Read until the first frame (kind 1), so the source is streaming and placed.
    buf = b""
    deadline = time.time() + 10
    got_frame = False
    s.settimeout(0.5)
    while time.time() < deadline and not got_frame:
        try:
            chunk = s.recv(1 << 20)
        except socket.timeout:
            continue
        if not chunk:
            sys.exit("the host closed the connection")
        buf += chunk
        while len(buf) >= 14:
            kind, _, _, ln = struct.unpack(">BdBI", buf[:14])
            if len(buf) < 14 + ln:
                break
            buf = buf[14 + ln:]
            if kind == 1:
                got_frame = True
    print(f"{container}: {'streaming' if got_frame else 'NO FRAME in 10 s'}; sending {len(steps)} steps")

    def send(event):
        s.sendall(msg(8, json.dumps(event).encode()))

    def ptr(action, x, y):
        send({"pointer": {"_0": action, "x": x, "y": y}})

    for step in steps:
        name, _, arg = step.partition("=")
        a = arg.split(",") if arg else []
        if name == "move":
            ptr("move", float(a[0]), float(a[1]))
        elif name in ("click", "rclick"):
            side = "left" if name == "click" else "right"
            x, y = float(a[0]), float(a[1])
            ptr("move", x, y); ptr(side + "Down", x, y); time.sleep(0.03); ptr(side + "Up", x, y)
        elif name == "scroll":
            x, y, dx, dy = map(float, a)
            send({"scrollGesture": {"_0": "began", "x": x, "y": y}})
            for _ in range(10):
                send({"scroll": {"x": x, "y": y, "dx": dx / 10, "dy": dy / 10}}); time.sleep(0.01)
            send({"scrollGesture": {"_0": "ended", "x": x, "y": y}})
        elif name in ("key", "keydown", "keyup"):
            usage, mods = num(a[0]), (num(a[1]) if len(a) > 1 else 0)
            downs = [True, False] if name == "key" else [name == "keydown"]
            for d in downs:
                send({"key": {"hidUsage": usage, "down": d, "modifiers": mods}}); time.sleep(0.02)
        elif name == "text":
            send({"text": {"_0": arg.replace("\\n", "\n")}})
        elif name == "sleep":
            time.sleep(float(arg)); continue
        else:
            sys.exit(f"unknown step {step!r}")
        print(f"  sent {step}")
        time.sleep(0.05)
    time.sleep(0.5)
    s.close()


if __name__ == "__main__":
    main()
