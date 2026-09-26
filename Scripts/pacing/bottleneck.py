#!/usr/bin/env python3
"""The pacing harness's path between its device and its host: a downlink bottleneck with a rate
(Mbit/s, optionally changing over time) and a buffer of Q bytes in front of it, plus a fixed
propagation delay each way. A variant of Scripts/sillrelay.py, which paces reads with a 64 KB
receive buffer and so has no deep bottleneck queue; the Python standard library only.

The link keeps a virtual clock: while data waits, chunks go back to back at the rate, and a late
wake-up (the relay descheduled, a timer that fires late) is made up at once instead of being lost
from the rate. The investigation's relay slept once per 16 KB chunk, so every late wake-up was a
pause of the link: at 600 Mbit/s (4,600 chunks a second) that made the Extreme cases a path with
random stalls (on 2026-09-26, ext120 on the base build ran at 7-120 fps from run to run; with the
clock, 119-120 fps and 8.6 drops a minute every time, the figure the plan's critique measured).

usage: bottleneck.py --listen PORT --to HOST:PORT --rate-mbps R --delay-ms D [--queue-bytes Q]
                     [--rate-at T:R,T:R...]
  --rate-mbps R     downlink (host → device) bottleneck rate
  --delay-ms D      round trip added: D/2 each way
  --queue-bytes Q   the bottleneck's buffer (a cellular cell's per-device queue); the relay stops
                    reading from the host while Q bytes wait, so the host's TCP backs up behind it
  --rate-at         T seconds after the relay started, the rate becomes R (a cellular dip: 20:0.5,35:8)
The uplink (device → host) is only delayed. Prints one line per connection and per rate change."""
import asyncio, socket, sys, time
from collections import deque

def opt(name, default=None):
    a = sys.argv
    if name in a: return a[a.index(name) + 1]
    return default

LISTEN = int(opt("--listen", "0"))
HOST, _, PORT = opt("--to").rpartition(":")
PORT = int(PORT)
RATE = float(opt("--rate-mbps", "8"))
HALF = float(opt("--delay-ms", "70")) / 2000.0
QUEUE = int(opt("--queue-bytes", "262144"))
SCHEDULE = [(float(t), float(r)) for t, r in (p.split(":") for p in opt("--rate-at", "").split(",") if p)]
T0 = time.monotonic()

def rate_now():
    r = RATE
    for t, v in SCHEDULE:
        if time.monotonic() - T0 >= t: r = v
    return r

def stamp():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)) + ".%03d" % int((t % 1) * 1000)

COUNT = 0

async def handle(dev_reader, dev_writer):
    global COUNT
    COUNT += 1
    n = COUNT
    try:
        # The receive buffer is set before connecting, so the handshake advertises it and the
        # kernel never autotunes it: the only deep queue on this path is the bottleneck's own.
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 65536)
        s.setblocking(False)
        await asyncio.get_running_loop().sock_connect(s, (HOST, PORT))
        host_reader, host_writer = await asyncio.open_connection(sock=s)
    except OSError as e:
        print(f"{stamp()} relay #{n}: host unreachable: {e}", flush=True); dev_writer.close(); return
    print(f"{stamp()} relay #{n}: open", flush=True)
    done = asyncio.Event()
    queue, queued = deque(), [0]           # the bottleneck's buffer
    space, data_ready = asyncio.Event(), asyncio.Event()
    space.set()
    line = deque()                         # (due, chunk) after the bottleneck: propagation
    line_ready = asyncio.Event()
    stats = {"down": 0, "up": 0}

    async def fill():                      # host → bottleneck buffer, while it has room
        try:
            while True:
                while queued[0] >= QUEUE:
                    space.clear(); await space.wait()
                data = await host_reader.read(16384)
                if not data: break
                queue.append(data); queued[0] += len(data); data_ready.set()
        except (ConnectionError, OSError):
            pass
        queue.append(b""); data_ready.set()

    async def serialize():                 # the bottleneck: one chunk at a time at the rate
        free = time.monotonic()            # a virtual clock: when the link is done with what it sent
        while True:
            if not queue:
                while not queue:
                    data_ready.clear(); await data_ready.wait()
                free = max(free, time.monotonic())      # the link was idle until this arrived
            chunk = queue[0]
            if not chunk:
                line.append((time.monotonic() + HALF, b"")); line_ready.set(); return
            r = rate_now()
            if r <= 0:
                await asyncio.sleep(0.05); free = time.monotonic(); continue
            # Back to back while data waits: a late wake-up (the relay descheduled) is made up at
            # once, as a real link would have kept sending, rather than lost from the rate.
            free += len(chunk) * 8 / (r * 1e6)
            wait = free - time.monotonic()
            if wait > 0.001: await asyncio.sleep(wait)
            queue.popleft(); queued[0] -= len(chunk); space.set()
            line.append((free + HALF, chunk)); line_ready.set()

    async def deliver():                   # propagation, then the device
        while True:
            while not line:
                line_ready.clear(); await line_ready.wait()
            due, chunk = line[0]
            w = due - time.monotonic()
            if w > 0: await asyncio.sleep(w)
            line.popleft()
            if not chunk: break
            try:
                dev_writer.write(chunk); await dev_writer.drain(); stats["down"] += len(chunk)
            except (ConnectionError, OSError):
                break
        done.set()

    async def uplink():                    # device → host, delayed only
        up = deque(); ready = asyncio.Event()
        async def pump():
            try:
                while True:
                    d = await dev_reader.read(65536)
                    up.append((time.monotonic() + HALF, d)); ready.set()
                    if not d: return
            except (ConnectionError, OSError):
                up.append((time.monotonic() + HALF, b"")); ready.set()
        asyncio.ensure_future(pump())
        while True:
            while not up:
                ready.clear(); await ready.wait()
            due, d = up[0]
            w = due - time.monotonic()
            if w > 0: await asyncio.sleep(w)
            up.popleft()
            if not d: break
            try:
                host_writer.write(d); await host_writer.drain(); stats["up"] += len(d)
            except (ConnectionError, OSError):
                break
        done.set()

    tasks = [asyncio.ensure_future(t) for t in (fill(), serialize(), deliver(), uplink())]
    await done.wait()
    for t in tasks: t.cancel()
    for w in (dev_writer, host_writer):
        try: w.close()
        except (ConnectionError, OSError): pass
    print(f"{stamp()} relay #{n}: closed (down {stats['down']} B, up {stats['up']} B)", flush=True)

async def announce_rates():
    last = None
    while True:
        r = rate_now()
        if r != last:
            print(f"{stamp()} relay: downlink {r:g} Mbit/s", flush=True); last = r
        await asyncio.sleep(0.2)

async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", LISTEN)
    port = server.sockets[0].getsockname()[1]
    print(f"{stamp()} bottleneck listening on 127.0.0.1:{port} → {HOST}:{PORT}, {RATE:g} Mbit/s, +{HALF*2000:g} ms RTT, queue {QUEUE} B", flush=True)
    asyncio.ensure_future(announce_rates())
    async with server:
        await server.serve_forever()

try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
