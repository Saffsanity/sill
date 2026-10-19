#!/usr/bin/env python3
"""Actual loopback admission/capture routing check. No real screen capture or input is posted.
Run: python3 Tests/independent-sessions/check.py .build/debug/SillHost
The child host is synthetic, loopback-only, software-encoder-only, with its own pasteboard.
"""
import json, os, pathlib, queue, re, select, socket, struct, subprocess, sys, threading, time

exe = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/SillHost').resolve())
env = dict(os.environ, SILL_TEST_LOOPBACK='1', SILL_TEST_SOFTWARE_ENCODER='1', SILL_TEST_INPUT_LOG='1',
           SILL_TEST_CLIPBOARD_ACCESS='allowed')
host = subprocess.Popen([exe, '--synthetic'], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
lines = []
threading.Thread(target=lambda: lines.extend(iter(host.stdout.readline, '')), daemon=True).start()
peers = []

class Peer:
    def __init__(self, port, independent=True, generation=1, send_hello=True):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=3)
        self.sock.setblocking(False)
        self.buf = b''
        self.messages = []
        peers.append(self)
        hello = dict(appVersion='1.0', protocol=1, device='Independent synthetic check')
        if independent: hello['independentSession'] = generation
        if send_hello: self.send(23, hello)
    def send(self, kind, payload):
        blob = json.dumps(payload, separators=(',', ':')).encode()
        self.sock.sendall(struct.pack('>BdBI', kind, time.time(), 0, len(blob)) + blob)
    def pump(self):
        try: data = self.sock.recv(1 << 20)
        except (BlockingIOError, ConnectionResetError): return
        if not data: return
        self.buf += data
        while len(self.buf) >= 14:
            kind, ts, key, size = struct.unpack('>BdBI', self.buf[:14])
            if len(self.buf) < 14 + size: break
            payload = self.buf[14:14 + size]
            self.buf = self.buf[14 + size:]
            self.messages.append((kind, payload))
    def wait(self, kind, predicate=lambda value: True, timeout=12):
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            for i, (found, payload) in enumerate(self.messages):
                if found != kind: continue
                try: value = json.loads(payload)
                except (ValueError, UnicodeDecodeError): value = payload
                if predicate(value):
                    self.messages.pop(i)
                    return value
            for peer in peers: peer.pump()
            time.sleep(.01)
        raise AssertionError(f'timeout waiting for kind {kind}')
    def source(self, source): self.send(6, {source: {}})
    def ready(self, independent=True):
        found = self.wait(2, lambda value: (value.get('independentSessions') == 1) if independent else value.get('independentSessions') is None)
        self.wait(16)
        return found
    def clear(self): self.messages.clear()
    def close(self):
        self.sock.close()
        peers.remove(self)

def drain(seconds=.4):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        for peer in peers: peer.pump()
        time.sleep(.01)

def frame_count(peer): return sum(kind == 1 for kind, _ in peer.messages)

try:
    port = None
    for _ in range(100):
        result = subprocess.run(['lsof', '-nP', '-a', '-p', str(host.pid), '-iTCP', '-sTCP:LISTEN', '-Fn'], capture_output=True, text=True)
        match = re.search(r'n127\.0\.0\.1:(\d+)', result.stdout)
        if match: port = int(match.group(1)); break
        if host.poll() is not None: raise AssertionError('host exited before listening')
        time.sleep(.05)
    assert port, 'synthetic host listener not found'
    a, b = Peer(port), Peer(port)
    a.ready(); b.ready()
    a.send(9, dict(width=800, height=600, fps=30, scale=1))
    b.send(9, dict(width=400, height=300, fps=24, scale=2))
    a.source('desktop')
    a.wait(2, lambda value: 'desktop' in value['active'])
    a.wait(0); a.wait(1)
    drain(); assert frame_count(b) == 0, 'A video leaked into idle B'
    b.source('desktop')
    b.wait(2, lambda value: 'desktop' in value['active'])
    b.wait(0); b.wait(1)
    a.send(17, dict(token=100, maxFPS=60))
    b.send(17, dict(token=200, maxFPS=120))
    state_a = a.wait(16, lambda value: value.get('answering') == 100)
    state_b = b.wait(16, lambda value: value.get('answering') == 200)
    assert state_a['settings']['maxFPS'] == 60 and state_b['settings']['maxFPS'] == 120, 'quality settings coupled'
    a.send(17, dict(token=101))
    again_a = a.wait(16, lambda value: value.get('answering') == 101)
    assert again_a['settings']['maxFPS'] == 60, 'B changed A settings'
    assert again_a['stream']['fps'] == 30 and state_b['stream']['fps'] == 24, 'viewport rates coupled'
    assert not state_a['virtualDisplayAvailable'] and not state_b['virtualDisplayAvailable']
    legacy = Peer(port, independent=False); legacy.ready(independent=False); legacy.source('desktop'); legacy.wait(1)
    legacy.send(17, dict(token=500, prioritizeSpeed=True))
    legacy.wait(16, lambda value: value.get('answering') == 500)
    a.send(17, dict(token=102)); b.send(17, dict(token=202))
    inherited_a = a.wait(16, lambda value: value.get('answering') == 102)
    inherited_b = b.wait(16, lambda value: value.get('answering') == 202)
    assert inherited_a['settings']['prioritizeSpeed'] and inherited_b['settings']['prioritizeSpeed'], 'root quality change failed to reach children'
    assert inherited_a['settings']['maxFPS'] == 60 and inherited_b['settings']['maxFPS'] == 120, 'unrelated root setting overwrote session quality'

    pending = Peer(port, send_hello=False)
    drain(.5)
    assert not pending.messages, 'unresolved hello received legacy frames/catalog/ticks'
    pending.send(23, dict(appVersion='1.0', protocol=1, independentSession=1))
    independent_list = pending.ready()
    assert 'none' in independent_list['active'], 'child acknowledged parent source'
    drain(.2); assert frame_count(pending) == 0, 'root stream leaked before child selection'
    pending.close()
    late = Peer(port, send_hello=False)
    fallback = late.ready(independent=False)
    assert 'desktop' in fallback['active'], 'old client without hello lost legacy source'
    late.send(23, dict(appVersion='1.0', protocol=1, independentSession=1))
    assert late.wait(22)['reconnect'] is False, 'late independent opt-in silently migrated shared stream'
    late.close()

    a.source('none'); a.wait(2, lambda value: 'none' in value['active'])
    drain(.6); a.clear(); b.clear(); legacy.clear(); drain(.6)
    assert frame_count(a) == 0, 'stopped A still receives another stream'
    assert frame_count(b) > 0 and frame_count(legacy) > 0, 'A stop interrupted B or legacy'
    # One shared synthetic clipboard poller/marker, subscriptions remain per connection.
    a.send(32, {}); b.send(32, {}); drain(.3)
    a.send(32, dict(text='synthetic independent clipboard'))
    b.wait(32, lambda value: value.get('text') == 'synthetic independent clipboard')
    # Foreground ownership changes release held keys before another connection's key is posted.
    a.source('desktop'); a.wait(1)
    a.send(8, {'key': {'hidUsage': 225, 'down': True, 'modifiers': 2}})
    b.send(8, {'key': {'hidUsage': 4, 'down': True, 'modifiers': 0}})
    drain(.2)
    assert 'Test input: key 0 down (none)' in ''.join(lines), 'B key-down did not reach dry injector'
    a.send(8, {'key': {'hidUsage': 225, 'down': False, 'modifiers': 0}})
    drain(.2)
    assert 'Test input: key 0 up (none)' not in ''.join(lines), 'late A key-up released B held key'
    b.send(8, {'key': {'hidUsage': 4, 'down': False, 'modifiers': 0}})
    drain(.3)
    b.close(); drain(.5); a.clear(); drain(.4)
    assert frame_count(a) > 0, 'closing B stopped A'
    extras = [Peer(port) for _ in range(3)]
    for peer in extras: peer.ready()
    legacy.source('none'); legacy.wait(2, lambda value: 'none' in value['active'])
    refused = Peer(port)
    refused.source('desktop')
    goodbye = refused.wait(22)
    assert goodbye['reason'] == 'independentSession' and goodbye['reconnect'] is False
    drain(.4)
    assert not any(kind in (0, 1, 2) for kind, _ in refused.messages), 'refused peer received legacy output'
    legacy.clear(); drain(.3)
    assert frame_count(legacy) == 0, 'refused peer changed legacy selection'
    refused.close(); extras[0].close(); drain(.3)
    replacement = Peer(port); replacement.ready()
    unknown = Peer(port, generation=2)
    goodbye = unknown.wait(22)
    assert goodbye['reconnect'] is False
    log_text = ''.join(lines)
    released = log_text.find('Test input: key 56 flags changed (none)')
    other_down = log_text.find('Test input: key 0 down (none)')
    assert released >= 0 and other_down > released, 'foreground handoff did not release held modifier before next owner'
    print('PASS: independent source/video/settings/viewport routing; legacy coexistence; shared clipboard; close isolation; cap and unknown-generation refusal; slot reclaimed')
finally:
    for peer in list(peers): peer.close()
    host.terminate()
    try: host.wait(timeout=5)
    except subprocess.TimeoutExpired: host.kill(); host.wait()
    pathlib.Path('/tmp/sill-independent-sessions-host.log').write_text(''.join(lines))
