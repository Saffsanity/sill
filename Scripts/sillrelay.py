#!/usr/bin/env python3
"""A passthrough TCP relay that shapes the link between a Sill device (or sillclient.py) and a
host, for testing the remote door's slow-link rules headless. Standard library only (asyncio).

usage: sillrelay.py --listen PORT --to HOST:PORT [--delay-ms N] [--rate-mbps R]
                    [--blackhole-after S] [--record PREFIX]
  --listen PORT         where to listen on 127.0.0.1; 0 takes any free port
  --to HOST:PORT        the host's door ([v6]:port for IPv6); every accepted connection gets its own
  --delay-ms N          N ms more round trip, half each way, order kept
  --rate-mbps R         host → client at most R Mbit/s. The relay reads from the host only as fast
                        as R allows, so the host's own send queue fills as it would behind a slow
                        uplink. Client → host is not shaped. (The relay's receive buffer from the
                        host is always small, 64 KB, for the same reason.)
  --blackhole-after S   S seconds into each connection, stop forwarding both ways without closing
                        either side (nothing is read, written or closed from then on): a dead path
  --record PREFIX       write each connection's bytes to PREFIX-N.up (client → host) and
                        PREFIX-N.down (host → client), N = 1, 2, … in accept order

It prints "sillrelay listening on 127.0.0.1:P" once it listens, one line per connection and one
when each ends. TLS passes through untouched: the relay never sees a key. Stop it with a signal."""
import asyncio, socket, sys, time

def fail(text):
    print(f"sillrelay.py: {text}", file=sys.stderr); sys.exit(2)

def parse(argv):
    opts = {"listen": None, "to": None, "delay-ms": 0.0, "rate-mbps": None, "blackhole-after": None, "record": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if not a.startswith("--"): fail(f"unexpected argument {a!r}")
        name, eq, value = a[2:].partition("=")
        if name not in opts: fail(f"unknown flag {a!r}")
        if not eq:
            i += 1
            if i >= len(argv): fail(f"--{name} needs a value")
            value = argv[i]
        opts[name] = value
        i += 1
    if opts["listen"] is None or opts["to"] is None: fail("--listen and --to are required")
    try:
        opts["listen"] = int(opts["listen"])
        host, _, port = opts["to"].rpartition(":")
        if host.startswith("[") and host.endswith("]"): host = host[1:-1]
        if not host: raise ValueError("--to needs HOST:PORT")
        opts["to"] = (host, int(port))
        opts["delay-ms"] = float(opts["delay-ms"])
        if opts["rate-mbps"] is not None: opts["rate-mbps"] = float(opts["rate-mbps"])
        if opts["blackhole-after"] is not None: opts["blackhole-after"] = float(opts["blackhole-after"])
    except ValueError as e:
        fail(str(e))
    if opts["delay-ms"] < 0 or (opts["rate-mbps"] is not None and opts["rate-mbps"] <= 0): fail("delay and rate must be positive")
    return opts

OPTS = parse(sys.argv[1:])
COUNT = 0

class Pipe:
    """One direction of one connection: reads, optionally paces the reads, delays each chunk by a
    fixed amount (a writer task keeps the order) and writes. Stops at EOF, an error or the
    blackhole."""
    def __init__(self, name, reader, writer, delay, rate, record, dead):
        self.name, self.reader, self.writer = name, reader, writer
        self.delay, self.rate, self.record, self.dead = delay, rate, record, dead
        self.queue = asyncio.Queue()
        self.bytes = 0

    async def pump(self):
        # Pacing: a chunk of n bytes is followed by a pause of n*8/rate seconds before the next
        # read, so the host is drained at the link's rate and its own queue does the waiting.
        chunk = 16384 if self.rate else 1 << 20
        while not self.dead.is_set():
            try:
                data = await self.reader.read(chunk)
            except (ConnectionError, OSError):
                data = b""
            if self.dead.is_set(): return
            await self.queue.put((time.monotonic() + self.delay, data))
            if not data: return
            self.bytes += len(data)
            if self.record: self.record.write(data)
            if self.rate: await asyncio.sleep(len(data) * 8 / (self.rate * 1e6))

    async def deliver(self):
        while True:
            due, data = await self.queue.get()
            wait = due - time.monotonic()
            if wait > 0: await asyncio.sleep(wait)
            if self.dead.is_set(): return      # the blackhole swallows what was still in flight
            if not data:
                try:
                    if self.writer.can_write_eof(): self.writer.write_eof()
                except (ConnectionError, OSError):
                    pass
                return
            try:
                self.writer.write(data)
                await self.writer.drain()
            except (ConnectionError, OSError):
                return

async def handle(client_reader, client_writer):
    global COUNT
    COUNT += 1
    n = COUNT
    peer = client_writer.get_extra_info("peername")
    try:
        host_reader, host_writer = await asyncio.open_connection(OPTS["to"][0], OPTS["to"][1])
    except OSError as e:
        print(f"sillrelay #{n}: {peer} could not reach {OPTS['to']}: {e}", flush=True)
        client_writer.close(); return
    sock = host_writer.get_extra_info("socket")
    if sock is not None:
        # A small receive buffer, so the kernel does not soak up megabytes a real link could not
        # carry: behind a slow or dead path the host's own queue fills, as it would on a real uplink.
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 65536)
    print(f"sillrelay #{n}: {peer} → {OPTS['to'][0]}:{OPTS['to'][1]}", flush=True)
    dead = asyncio.Event()
    half = OPTS["delay-ms"] / 2000.0
    rec_up = open(f"{OPTS['record']}-{n}.up", "wb") if OPTS["record"] else None
    rec_down = open(f"{OPTS['record']}-{n}.down", "wb") if OPTS["record"] else None
    up = Pipe("up", client_reader, host_writer, half, None, rec_up, dead)
    down = Pipe("down", host_reader, client_writer, half, OPTS["rate-mbps"], rec_down, dead)
    tasks = [asyncio.ensure_future(t) for t in (up.pump(), up.deliver(), down.pump(), down.deliver())]
    if OPTS["blackhole-after"] is not None:
        async def blackhole():
            await asyncio.sleep(OPTS["blackhole-after"])
            dead.set()
            print(f"sillrelay #{n}: blackhole: forwarding stopped, both sides left open", flush=True)
        asyncio.ensure_future(blackhole())
    await asyncio.gather(*tasks, return_exceptions=True)
    for f in (rec_up, rec_down):
        if f: f.close()
    if dead.is_set():
        # A dead path closes nothing: park until the relay is stopped.
        print(f"sillrelay #{n}: ended inside the blackhole (up {up.bytes} B, down {down.bytes} B)", flush=True)
        await asyncio.Event().wait()
    print(f"sillrelay #{n}: closed (up {up.bytes} B, down {down.bytes} B)", flush=True)
    for w in (client_writer, host_writer):
        try: w.close()
        except (ConnectionError, OSError): pass

async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", OPTS["listen"])
    port = server.sockets[0].getsockname()[1]
    shaping = []
    if OPTS["delay-ms"]: shaping.append(f"+{OPTS['delay-ms']:g} ms round trip")
    if OPTS["rate-mbps"]: shaping.append(f"host → client {OPTS['rate-mbps']:g} Mbit/s")
    if OPTS["blackhole-after"] is not None: shaping.append(f"blackhole after {OPTS['blackhole-after']:g} s")
    print(f"sillrelay listening on 127.0.0.1:{port}" + (f" ({', '.join(shaping)})" if shaping else ""), flush=True)
    async with server:
        await server.serve_forever()

try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
