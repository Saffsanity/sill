#!/usr/bin/env python3
"""lanrelay (TEST ONLY; Tests/devicerig/README.md): a relay from an address of this Mac's that a device
reaches, the USB cable's (en14's 169.254.x.y), to a test host that listens on loopback alone
(SILL_TEST_LOOPBACK=1), so Sill on a physical iPad or iPhone can stream from a synthetic host on this
Mac: the device dials it with -SillConnect ADDRESS:PORT.

    python3 Tests/devicerig/lanrelay.py --listen 169.254.71.35:0 --to 127.0.0.1:PORT

It binds only the address given (never 0.0.0.0 unless asked), takes connections only from the
addresses --allow names (by default the link-local ones, 169.254.0.0/16 and fe80::/10, when it listens
on a link-local address; loopback when it listens on loopback), and relays only to a loopback port.

It reads Sill's plain wire (StreamProtocol's 14-byte header: kind, timestamp, keyframe flag, payload
length) in both directions and prints what the device sends: its hello, viewports, the Desktop picks,
taps, keys and text (kind 8), and for each scroll one line for its finger part and one for its coast,
with the number of deltas and their sums (fractions of the picture; dy > 0 moves the content down),
the sign the synthetic host's own input log (SILL_TEST_INPUT_LOG=1) does not print; --each prints
every delta. At each connection's end, a summary.

The guard: a synthetic host lists this Mac's real windows and apps, so a device's pick of a window
(kind 6) would capture one, a press of a thumbnail's lights (kind 15) would close, minimize or full-screen
one, and a launch from the Apps drawer (kind 7) would open an app. The relay drops all three, with a line
each, and passes everything else. A TLS session (SillHost --pairing) is refused: it cannot be read, so
it cannot be guarded.
"""
import argparse
import asyncio
import ipaddress
import json
import signal
import struct
import sys
import time

HEADER = 14
MAX_PAYLOAD = 64 << 20          # a frame; anything bigger is not Sill's wire
KINDS = {0: "parameterSets", 1: "frame", 2: "windowList", 3: "thumbnail", 4: "appIcon", 5: "appList",
         6: "selectSource", 7: "launchApp", 8: "input", 9: "viewport", 10: "ping", 11: "pong",
         12: "clientStats", 13: "tick", 14: "cursorShape", 15: "windowCommand", 16: "hostSettings",
         17: "changeSettings", 18: "macInfo", 19: "pairRequest", 20: "pairResult", 21: "pairingWanted",
         22: "goodbye", 23: "hello", 24: "macMenu", 25: "pressMenuItem", 26: "macPointer", 27: "fetchMenu",
         28: "gesture", 32: "clipboard"}
started = time.monotonic()


def say(line):
    print(f"lanrelay {time.monotonic() - started:7.2f} {line}", flush=True)


def endpoint(text, what):
    host, sep, port = text.rpartition(":")
    if not sep or not port.isdigit():
        raise SystemExit(f"lanrelay: {what} is ADDRESS:PORT, not {text!r}")
    return host.strip("[]"), int(port)


class Session:
    """One device's connection: what it sent, for the summary."""
    count = 0

    def __init__(self, peer, each):
        Session.count += 1
        self.number = Session.count
        self.peer = peer
        self.each = each
        self.began = time.monotonic()
        self.inputs = {}
        self.gestures = []          # one line per scroll gesture: its finger part and its coast
        self.gesture = 0
        self.phase = None           # "finger" or "coast" inside a gesture, None outside one
        self.sums = [0, 0.0, 0.0]   # the open part's events, dx and dy
        self.plain = [0, 0.0, 0.0]  # scrolls outside a gesture (a wheel's)
        self.dropped = []
        self.frames = 0
        self.down_bytes = 0

    def tag(self):
        return f"#{self.number}"

    def summary(self):
        inputs = ", ".join(f"{k} {v}" for k, v in sorted(self.inputs.items())) or "none"
        plain = f"; plain scrolls {self.plain[0]} (dx {self.plain[1]:+.4f}, dy {self.plain[2]:+.4f})" if self.plain[0] else ""
        return (f"{self.tag()} ended after {time.monotonic() - self.began:.1f} s: inputs {inputs}; "
                f"scroll gestures {self.gesture}{plain}; dropped {len(self.dropped)}; "
                f"from the host {self.frames} frames, {self.down_bytes / 1e6:.1f} MB")

    def close_part(self, at):
        """The finger part or the coast of the open gesture, in one line."""
        n, dx, dy = self.sums
        self.sums = [0, 0.0, 0.0]
        what = "finger" if self.phase == "finger" else "coast"
        return (f"scroll {self.gesture} {what}: {n} event{'' if n == 1 else 's'}, dx {dx:+.4f}, dy {dy:+.4f} "
                f"(fractions of the picture; dy > 0 moves the content down), ending at {at}")

    def describe_input(self, event):
        """One input event (StreamProtocol's InputEvent, as Swift encodes an enum) in a line, or None
        for a scroll's delta inside a gesture (summed, and printed with --each)."""
        (case, body), = event.items()
        self.inputs[case] = self.inputs.get(case, 0) + 1
        at = f"{body.get('x', 0):.3f},{body.get('y', 0):.3f}" if isinstance(body, dict) else ""
        if case == "scroll":
            sums = self.sums if self.phase else self.plain
            sums[0] += 1; sums[1] += body["dx"]; sums[2] += body["dy"]
            line = f"scroll dx {body['dx']:+.4f} dy {body['dy']:+.4f} at {at}"
            return line if self.each or not self.phase else None
        if case == "scrollGesture":
            phase = body.get("_0")
            if phase == "began":
                self.gesture += 1
                self.phase, self.sums = "finger", [0, 0.0, 0.0]
                return f"scroll {self.gesture} began at {at}"
            if phase == "momentumBegan":
                self.phase, self.sums = "coast", [0, 0.0, 0.0]
                return None
            if phase in ("ended", "momentumEnded") and self.phase:
                line = self.close_part(at)
                self.phase = None
                return line
            return f"scroll {phase} at {at}"
        if case == "pointer":
            return f"pointer {body.get('_0')} at {at}"
        if case == "key":
            return f"key usage {body['hidUsage']} {'down' if body['down'] else 'up'} modifiers {body['modifiers']:#x}"
        if case == "text":
            return f"text {body.get('_0')!r}"
        return f"{case} {json.dumps(body, separators=(',', ':'))}"


async def pipe_up(reader, writer, session):
    """Device → host: read each message, print what it says, drop what the guard drops."""
    try:
        await read_up(reader, writer, session)
    except (asyncio.IncompleteReadError, ConnectionError):
        pass


async def read_up(reader, writer, session):
    first = await reader.read(1)
    if not first:
        return
    if first[0] == 0x16:
        say(f"{session.tag()} refused: a TLS session (SillHost --pairing) cannot be read, so it cannot be guarded")
        return
    pending = first
    while True:
        header = pending + await reader.readexactly(HEADER - len(pending))
        pending = b""
        kind, _, _, length = struct.unpack(">BdBI", header)
        if length > MAX_PAYLOAD:
            say(f"{session.tag()} closed: a message of {length} bytes is not Sill's wire")
            return
        payload = await reader.readexactly(length)
        name = KINDS.get(kind, f"kind {kind}")
        drop = None
        line = None
        try:
            body = json.loads(payload) if kind in (6, 7, 8, 9, 15, 17, 23, 28) and payload else None
        except ValueError:
            body = None
        if kind == 8 and isinstance(body, dict) and len(body) == 1:
            described = session.describe_input(body)
            line = described and "input " + described
        elif kind == 6:
            source = next(iter(body), "?") if isinstance(body, dict) else "?"
            if source == "window":
                drop = "a window's pick (the synthetic host would capture that real window)"
            else:
                line = f"pick {source}"
        elif kind == 7:
            drop = "an app's launch (it would open on this Mac)"
        elif kind == 15:
            drop = "a window's light (it would close, minimize or full-screen a real window)"
        elif kind == 23 and isinstance(body, dict):
            line = (f"hello: Sill {body.get('appVersion')} ({body.get('build')}), protocol {body.get('protocol')}, "
                    f"{body.get('device')}")
        elif kind in (9, 17, 28) and body is not None:
            line = f"{name} {json.dumps(body, separators=(',', ':'))}"
        if drop:
            session.dropped.append(name)
            say(f"{session.tag()} dropped {name}: {drop}")
            continue
        if line:
            say(f"{session.tag()} {line}")
        writer.write(header + payload)
        await writer.drain()


async def pipe_down(reader, writer, session):
    """Host → device: passed through as it comes; frames and the window list counted."""
    try:
        await read_down(reader, writer, session)
    except ConnectionError:
        pass


async def read_down(reader, writer, session):
    buffer = b""
    reading = True
    while True:
        data = await reader.read(1 << 16)
        if not data:
            return
        session.down_bytes += len(data)
        writer.write(data)
        await writer.drain()
        if not reading:
            continue
        buffer += data
        while len(buffer) >= HEADER:
            kind, _, _, length = struct.unpack(">BdBI", buffer[:HEADER])
            if length > MAX_PAYLOAD:
                reading = False         # not Sill's wire: passed through, no longer read
                buffer = b""
                break
            if len(buffer) < HEADER + length:
                break
            payload, buffer = buffer[HEADER:HEADER + length], buffer[HEADER + length:]
            if kind == 1:
                session.frames += 1
            elif kind == 2:
                try:
                    listing = json.loads(payload)
                    # Only the count: the titles are this Mac's windows.
                    say(f"{session.tag()} window list: {len(listing.get('windows', []))} windows, "
                        f"active {next(iter(listing.get('active') or {}), 'none')}")
                except ValueError:
                    pass


async def handle(reader, writer, args, allowed, sessions):
    peer = writer.get_extra_info("peername")
    address = ipaddress.ip_address(peer[0].split("%")[0])
    if not any(address in net for net in allowed):
        say(f"refused {peer[0]}: not in --allow")
        writer.close()
        return
    session = Session(peer[0], args.each)
    sessions.append(session)
    try:
        up_reader, up_writer = await asyncio.open_connection(args.to_host, args.to_port)
    except OSError as error:
        say(f"{session.tag()} from {peer[0]}: the host at {args.to} did not answer ({error})")
        writer.close()
        return
    say(f"{session.tag()} from {peer[0]} relayed to {args.to}")
    tasks = [asyncio.ensure_future(pipe_up(reader, up_writer, session)),
             asyncio.ensure_future(pipe_down(up_reader, writer, session))]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks:
            task.cancel()
        for w in (writer, up_writer):
            w.close()
        say(session.summary())
        sessions.remove(session)


async def main():
    parser = argparse.ArgumentParser(description="TEST ONLY: relay a device to a loopback Sill test host.")
    parser.add_argument("--listen", required=True, help="ADDRESS:PORT of this Mac's to listen on (PORT 0: any)")
    parser.add_argument("--to", required=True, help="127.0.0.1:PORT (or [::1]:PORT) of the test host")
    parser.add_argument("--allow", action="append", default=[], help="a network peers may come from (CIDR)")
    parser.add_argument("--each", action="store_true", help="print every scroll delta, not one line per finger part and coast")
    args = parser.parse_args()
    host, port = endpoint(args.listen, "--listen")
    args.to_host, args.to_port = endpoint(args.to, "--to")
    try:
        to = ipaddress.ip_address(args.to_host)
        listen = ipaddress.ip_address(host.split("%")[0])
    except ValueError as error:
        raise SystemExit(f"lanrelay: an address, not a name: {error}")
    if not to.is_loopback:
        raise SystemExit("lanrelay: --to must be a loopback address: it relays only to a test host on this Mac")
    allowed = [ipaddress.ip_network(n, strict=False) for n in args.allow]
    if not allowed:
        if listen.is_link_local:
            allowed = [ipaddress.ip_network("169.254.0.0/16"), ipaddress.ip_network("fe80::/10")]
        elif listen.is_loopback:
            allowed = [ipaddress.ip_network("127.0.0.0/8"), ipaddress.ip_network("::1/128")]
        else:
            raise SystemExit("lanrelay: --allow is needed for a listen address that is not link-local or loopback")
    sessions = []
    server = await asyncio.start_server(lambda r, w: handle(r, w, args, allowed, sessions), host, port)
    bound = server.sockets[0].getsockname()
    say(f"listening on {bound[0]}:{bound[1]}, relaying to {args.to}; allowed {', '.join(map(str, allowed))}")
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    server.close()
    for session in list(sessions):
        say(session.summary() + " (still open at the relay's end)")
    say("stopped")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(130)
