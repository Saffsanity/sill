#!/usr/bin/env python3
"""The pacing harness's device: what the iPad's StreamClient does on a remote session, minus the
pixels. TLS 1.3 with a client certificate and ALPN sill/1 (or plain TCP with --plain) to
127.0.0.1:PORT.
- reads every message;
- pings every 0.25 s (8-byte monotonic stamp, echoed by the host as a pong);
- closes a one-second window each second: fps, frame age median/max, rtt median/max, sent to the
  host as ClientStats (kind 12, device "harness") and printed here with the bytes that arrived, the
  keyframes among the frames and the stamp of the newest frame it has (across reconnects: what its
  screen shows, which summarize.py compares with the host's last frame before a still spell);
- the device's liveness rule (StreamClient.checkLiveness), checked at each ping: nothing for
  max(6 s, 4 × the worst rtt of the last second that had a pong) → "connection silent … lost".
  By default "nothing" means no message completed (the device before MessageReader, which stamped
  only whole headers and payloads); with --liveness-bytes, no byte arrived (MessageReader: every
  piece of at most 256 KB counts). With --reconnect it dials again 3 s later (the automatic
  remote dial).
The key and certificate are made on first use with /usr/bin/openssl in $PACING_OUT (run.py sets
it; default the repository's .build/pacing), never in the repository.
usage: device.py PORT [--seconds S] [--plain] [--reconnect] [--liveness-bytes] [--tag NAME]"""
import asyncio, json, os, ssl, struct, subprocess, sys, time

def opt(name, default=None):
    a = sys.argv
    return a[a.index(name) + 1] if name in a else default

PORT = int(sys.argv[1])
SECONDS = float(opt("--seconds", "60"))
PLAIN = "--plain" in sys.argv
RECONNECT = "--reconnect" in sys.argv
TAG = opt("--tag", "dev")
BYTES_LIVENESS = "--liveness-bytes" in sys.argv
NEWEST = [0.0]      # the newest frame's stamp (the header's), across sessions
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("PACING_OUT") or os.path.join(HERE, "..", "..", ".build", "pacing")
KEY, CERT = os.path.join(OUT, "devkey.pem"), os.path.join(OUT, "devcert.pem")

def stamp():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)) + ".%03d" % int((t % 1) * 1000)

def say(s): print(f"{stamp()} {TAG}: {s}", flush=True)

def context():
    if not os.path.exists(CERT):
        os.makedirs(OUT, exist_ok=True)
        subprocess.run(["/usr/bin/openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", KEY], check=True, capture_output=True)
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-new", "-key", KEY, "-subj", "/CN=harness", "-days", "30", "-out", CERT], check=True, capture_output=True)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ctx.maximum_version = ssl.TLSVersion.TLSv1_3
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ctx.load_cert_chain(CERT, KEY)
    ctx.set_alpn_protocols(["sill/1"])
    return ctx

def msg(kind, payload=b""):
    return struct.pack(">BdBI", kind, time.time(), 0, len(payload)) + payload

def medmax(xs):
    if not xs: return None
    s = sorted(xs)
    return (int(round(s[len(s) // 2])), int(round(s[-1])))

async def session(ctx, deadline):
    reader, writer = await asyncio.open_connection("127.0.0.1", PORT, ssl=None if PLAIN else ctx,
                                                   server_hostname=None if PLAIN else "sill")
    say("connected")
    st = {"last": time.monotonic(), "worst": None, "frames": 0, "ages": [], "rtts": [], "bytes": 0,
          "keys": 0, "open": True, "why": None}

    async def read():
        buf = bytearray()
        need = None   # (kind, ts, key, length) once a header is complete
        while st["open"]:
            data = await reader.read(262144)
            if not data: st["why"] = st["why"] or "host closed"; break
            st["bytes"] += len(data)
            if BYTES_LIVENESS: st["last"] = time.monotonic()      # any byte counts
            buf += data
            while True:
                if need is None:
                    if len(buf) < 14: break
                    kind, ts, key, n = struct.unpack(">BdBI", bytes(buf[:14])); del buf[:14]
                    need = (kind, ts, key, n)
                    st["last"] = time.monotonic()          # a header completed
                kind, ts, key, n = need
                if len(buf) < n: break
                payload = bytes(buf[:n]); del buf[:n]; need = None
                if n: st["last"] = time.monotonic()        # a payload completed
                if kind == 1:
                    st["frames"] += 1
                    NEWEST[0] = max(NEWEST[0], ts)
                    st["ages"].append(max(0.0, (time.time() - ts) * 1000))
                    if key: st["keys"] += 1
                elif kind == 11 and len(payload) >= 8:
                    st["rtts"].append((time.monotonic() - struct.unpack(">d", payload[:8])[0]) * 1000)
        st["open"] = False

    async def ping():
        while st["open"]:
            await asyncio.sleep(0.25)
            now = time.monotonic()
            limit = max(6.0, 4 * (st["worst"] or 0) / 1000)
            if now - st["last"] > limit:
                say(f"connection silent for {int(now - st['last'])} s: lost")
                st["why"] = "liveness"; st["open"] = False; break
            writer.write(msg(10, struct.pack(">d", time.monotonic())))

    async def window():
        opened = time.monotonic()
        while st["open"]:
            await asyncio.sleep(1)
            now = time.monotonic()
            fps = int(round(st["frames"] / (now - opened))); opened = now
            age, rtt = medmax(st["ages"]), medmax(st["rtts"])
            if rtt: st["worst"] = rtt[1]
            stats = {"fps": fps, "frameAgeMs": age[0] if age else -1, "rttMs": rtt[0] if rtt else -1,
                     "device": "harness", "frameAgeMaxMs": age[1] if age else -1, "rttMaxMs": rtt[1] if rtt else -1}
            writer.write(msg(12, json.dumps(stats).encode()))
            a = f"{age[0]}/{age[1]}" if age else "–"
            r = f"{rtt[0]}/{rtt[1]}" if rtt else "–"
            say(f"{fps:3d} fps  age {a:>11}  rtt {r:>11}  in {st['bytes'] // 1000:5d} kB  keys {st['keys']}  newest {NEWEST[0]:.3f}")
            st["frames"] = 0; st["ages"].clear(); st["rtts"].clear(); st["bytes"] = 0; st["keys"] = 0
            if time.monotonic() > deadline: st["why"] = "done"; st["open"] = False

    tasks = [asyncio.ensure_future(t()) for t in (read, ping, window)]
    while st["open"]:
        await asyncio.sleep(0.05)
    for t in tasks: t.cancel()
    try: writer.close()
    except Exception: pass
    say(f"closed ({st['why']})")
    return st["why"]

async def main():
    ctx = None if PLAIN else context()
    deadline = time.monotonic() + SECONDS
    while time.monotonic() < deadline:
        try:
            why = await session(ctx, deadline)
        except (OSError, ssl.SSLError, asyncio.IncompleteReadError) as e:
            say(f"error: {e}"); why = "error"
        if why == "done" or not RECONNECT: break
        await asyncio.sleep(3)

asyncio.run(main())
