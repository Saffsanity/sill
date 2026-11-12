"""Tests/update-harness: a stand-in for GitHub's release API and its download hosts, on 127.0.0.1 only.

usage: server.py DIR PORTFILE
Serves, from DIR/control.json read at every request:
  GET /repos/test/releases/latest   the release (control "release", a JSON object) or control "releaseStatus"
  GET /repos/test/releases/tags/nightly   the nightly pre-release (control "nightly"), or 404 without one
  GET /download/<tag>/<name>        the asset DIR/assets/<name>, as control "modes"[name] says:
      normal (200), truncate (half of it, then the connection closed), oversize (100 bytes more, with a
      Content-Length that says so), nolength (100 bytes more, no Content-Length), redirect-same (302 to
      /assets/<name> here), redirect-other (302 to http://localhost:<port>/assets/<name>), redirect-path
      (302 to /elsewhere/<name> here), redirect-loop (302 to /assets/hop-<name>, which sends itself on and
      on), auth (401 asking for a password), status:N
  GET /assets/<name>                the asset, 200
Every request is one line in DIR/requests.log: the method, the Host header, the path, the User-Agent,
and whether an Authorization or Cookie header came. HTTP/1.0: one request per connection."""
import http.server, json, os, sys, socketserver

DIR, PORTFILE = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def control(self):
        with open(os.path.join(DIR, "control.json")) as f:
            return json.load(f)

    def record(self):
        line = "%s host=%s path=%s ua=%s auth=%s cookie=%s\n" % (
            self.command, self.headers.get("Host"), self.path, self.headers.get("User-Agent"),
            "yes" if self.headers.get("Authorization") else "no", "yes" if self.headers.get("Cookie") else "no")
        with open(os.path.join(DIR, "requests.log"), "a") as f:
            f.write(line)

    def send(self, status, body=b"", headers=None, length=True):
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if length:
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def asset(self, name):
        path = os.path.join(DIR, "assets", os.path.basename(name))
        with open(path, "rb") as f:
            return f.read()

    def do_GET(self):
        self.record()
        c = self.control()
        port = self.server.server_address[1]
        parts = self.path.split("?")[0].split("/")
        if self.path.split("?")[0] == "/repos/test/releases/latest":
            status = c.get("releaseStatus", 200)
            body = json.dumps(c.get("release", {})).encode() if status == 200 else b'{"message":"no"}'
            return self.send(status, body, {"Content-Type": "application/json"})
        if self.path.split("?")[0] == "/repos/test/releases/tags/nightly":
            status = c.get("nightlyStatus", 200 if "nightly" in c else 404)
            body = json.dumps(c.get("nightly", {})).encode() if status == 200 else b'{"message":"Not Found"}'
            return self.send(status, body, {"Content-Type": "application/json"})
        if len(parts) == 4 and parts[1] == "download":
            name = parts[3]
            mode = c.get("modes", {}).get(name, "normal")
            if mode.startswith("status:"):
                return self.send(int(mode[7:]), b"no")
            if mode == "auth":
                return self.send(401, b"who are you", {"WWW-Authenticate": 'Basic realm="harness"'})
            if mode == "redirect-same":
                return self.send(302, b"", {"Location": "http://127.0.0.1:%d/assets/%s" % (port, name)})
            if mode == "redirect-other":
                return self.send(302, b"", {"Location": "http://localhost:%d/assets/%s" % (port, name)})
            if mode == "redirect-path":
                return self.send(302, b"", {"Location": "http://127.0.0.1:%d/elsewhere/%s" % (port, name)})
            if mode == "redirect-loop":
                return self.send(302, b"", {"Location": "http://127.0.0.1:%d/assets/hop-%s" % (port, name)})
            data = self.asset(name)
            if mode == "truncate":
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data[: len(data) // 2])
                self.wfile.flush()
                self.close_connection = True
                return
            if mode == "oversize":
                return self.send(200, data + b"\0" * 100)
            if mode == "nolength":
                return self.send(200, data + b"\0" * 100, length=False)
            return self.send(200, data, {"Content-Type": "application/octet-stream"})
        if len(parts) == 3 and parts[1] == "assets" and parts[2].startswith("hop-"):
            return self.send(302, b"", {"Location": "http://127.0.0.1:%d%s" % (port, self.path)})
        if len(parts) == 3 and parts[1] in ("assets", "elsewhere"):
            return self.send(200, self.asset(parts[2]))
        return self.send(404, b"not here")

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

httpd = Server(("127.0.0.1", 0), Handler)
with open(PORTFILE + ".tmp", "w") as f:
    f.write(str(httpd.server_address[1]))
os.rename(PORTFILE + ".tmp", PORTFILE)
httpd.serve_forever()
