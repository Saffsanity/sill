#!/usr/bin/env python3
r"""A fake GitHub "latest release" endpoint for testing Sill.app's update check without GitHub.

usage: sillfeed.py PORT [flags...]      (PORT 0: any free port; the first line says which)
  --tag TAG          the release's tag_name (default v0.4.0)
  --status CODE      answer this status: 200 (default), 304, 403, 404, 429, 500 or any other
  --etag ETAG        the 200's ETag (default W/"‹a hash of the body›", so it changes with the body, as
                     GitHub's does); a request whose If-None-Match equals it gets 304 with no body
  --no-etag          send no ETag
  --draft            "draft": true
  --prerelease       "prerelease": true
  --html-url URL     the release page (default https://github.com/Saffsanity/sill/releases/tag/TAG)
  --body JSON        this body instead of the release (sent as written)
  --big N            a body of N bytes (a JSON string padded to N): more than 1 MB is refused
  --slow S           wait S seconds before answering (the check gives up after 10)
  --reset EPOCH      X-RateLimit-Reset for 403/429 (default an hour from now)
  --redirect URL     answer 302 with this Location
  --set-cookie       every answer sets a cookie (the check must never send one back)
  --bind ADDR        listen on ADDR (default 127.0.0.1; ::1 for IPv6)
Every request is printed on one line: the time, the path, and the headers the check sends or must
never send (User-Agent, Accept, X-GitHub-Api-Version, If-None-Match, Cookie, Authorization), then
the status answered. GET /__control?key=value&... changes the flags above while it runs (keys:
tag, status, etag, noetag, draft, prerelease, htmlurl, body, big, slow, reset, redirect; 1/0 for
the switches, an empty value clears), so one app run can meet several answers. Python's standard
library only; it only ever listens on this Mac."""
import hashlib, http.server, json, socket, sys, time, urllib.parse

args = sys.argv[1:]
if not args or not args[0].isdigit():
    print(__doc__, file=sys.stderr); sys.exit(2)
port = int(args[0])
cfg = {"tag": "v0.4.0", "status": 200, "etag": None, "noetag": False, "draft": False, "prerelease": False, "htmlurl": None,
       "body": None, "big": 0, "slow": 0.0, "reset": None, "redirect": None, "setcookie": False, "bind": "127.0.0.1"}
VALUED = {"--tag": "tag", "--status": "status", "--etag": "etag", "--html-url": "htmlurl", "--body": "body", "--big": "big",
          "--slow": "slow", "--reset": "reset", "--redirect": "redirect", "--bind": "bind"}
SWITCH = {"--no-etag": "noetag", "--draft": "draft", "--prerelease": "prerelease", "--set-cookie": "setcookie"}
INTS = {"status", "big"}
FLOATS = {"slow", "reset"}
i = 1
while i < len(args):
    a = args[i]
    if a in SWITCH: cfg[SWITCH[a]] = True
    elif a in VALUED and i + 1 < len(args):
        k = VALUED[a]; v = args[i + 1]; i += 1
        cfg[k] = int(v) if k in INTS else float(v) if k in FLOATS else v
    else:
        print(f"sillfeed.py: unknown or incomplete flag {a!r}", file=sys.stderr); sys.exit(2)
    i += 1

def etag(body):
    if cfg["noetag"]: return None
    return cfg["etag"] or f'W/"{hashlib.sha1(body).hexdigest()[:16]}"'

def release_body():
    if cfg["body"] is not None: return cfg["body"].encode()
    tag = cfg["tag"]
    page = cfg["htmlurl"] or f"https://github.com/Saffsanity/sill/releases/tag/{tag}"
    d = {"url": f"https://api.github.com/repos/Saffsanity/sill/releases/1", "html_url": page, "id": 1, "tag_name": tag,
         "target_commitish": "main", "name": f"Sill {tag.lstrip('vV')}", "draft": cfg["draft"], "prerelease": cfg["prerelease"],
         "published_at": "2026-09-25T12:00:00Z", "assets": [], "body": "Release notes."}
    b = json.dumps(d).encode()
    if cfg["big"] > len(b):
        d["padding"] = "x" * (cfg["big"] - len(b) - 14)
        b = json.dumps(d).encode()
    return b

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def answer(self, status, body=b"", headers=()):
        self.send_response(status)
        for k, v in headers: self.send_header(k, v)
        if cfg["setcookie"]: self.send_header("Set-Cookie", "sillfeed=1; Path=/")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body: self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        if u.path == "/__control":
            for k, vs in urllib.parse.parse_qs(u.query, keep_blank_values=True).items():
                v = vs[-1]
                if k not in cfg or k == "bind": continue
                if k in ("noetag", "draft", "prerelease", "setcookie"): cfg[k] = v in ("1", "true", "yes")
                elif v == "": cfg[k] = 0 if k in INTS or k in FLOATS else None
                else: cfg[k] = int(v) if k in INTS else float(v) if k in FLOATS else v
            print(f"{time.strftime('%H:%M:%S')} control: {u.query}", flush=True)
            self.answer(200, b"ok\n"); return
        h = self.headers
        seen = " ".join(f"{name}={h.get(name)!r}" for name in ("User-Agent", "Accept", "X-GitHub-Api-Version", "If-None-Match", "Cookie", "Authorization"))
        status = cfg["status"]
        if cfg["slow"]: time.sleep(cfg["slow"])
        body = release_body()
        tag_etag = etag(body)
        if cfg["redirect"]:
            status = 302; out = (b"", [("Location", cfg["redirect"])])
        elif status == 200 and tag_etag and h.get("If-None-Match") == tag_etag:
            status = 304; out = (b"", [("ETag", tag_etag)])
        elif status == 200:
            out = (body, [("Content-Type", "application/json; charset=utf-8")] + ([("ETag", tag_etag)] if tag_etag else []))
        elif status == 304:
            out = (b"", [("ETag", tag_etag)] if tag_etag else [])
        elif status in (403, 429):
            reset = int(cfg["reset"] or time.time() + 3600)
            out = (b'{"message":"API rate limit exceeded"}', [("Content-Type", "application/json"), ("X-RateLimit-Limit", "60"),
                                                            ("X-RateLimit-Remaining", "0"), ("X-RateLimit-Reset", str(reset))])
        elif status == 404:
            out = (b'{"message":"Not Found","status":"404"}', [("Content-Type", "application/json")])
        else:
            out = (b'{"message":"Server Error"}', [("Content-Type", "application/json")])
        t = time.time()
        print(f"{time.strftime('%H:%M:%S', time.localtime(t))}.{int(t % 1 * 1000):03d} GET {self.path} {seen} -> {status}"
              f" ({len(out[0])} bytes)", flush=True)
        try:
            self.answer(status, *out)
        except (BrokenPipeError, ConnectionResetError):
            print("  (the client went away)", flush=True)

class Server(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6 if ":" in cfg["bind"] else socket.AF_INET
    daemon_threads = True

httpd = Server((cfg["bind"], port), Handler)
host = cfg["bind"] if ":" not in cfg["bind"] else f"[{cfg['bind']}]"
print(f"sillfeed listening on {host}:{httpd.server_address[1]}", flush=True)
try:
    httpd.serve_forever()
except KeyboardInterrupt:
    pass
