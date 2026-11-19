#!/usr/bin/env python3
"""A stand-in App Store Connect API on 127.0.0.1 for Scripts/asc.swift's check (run.sh). TEST ONLY.

Every request's bearer token is checked as App Store Connect would: an ES256 JWT whose header says
alg ES256, kid KID, typ JWT, whose claims say iss ISS, aud appstoreconnect-v1, an iat not in the
future, an exp after now and at most 20 minutes after iat, and whose signature verifies with the
throwaway public key (openssl dgst -verify, the raw r||s turned into DER). A bad token gets 401.
Each request is logged as one JSON line: method, path, query, body, the token's verdict and its
claims (the token itself too: a throwaway key's, so the check can look for it in asc's output).
With --state, the build's What to Test localizations and the groups' builds are written there after
every change, so the check reads what a run left.

  standin.py --port-file F --log F --pubkey pub.pem --kid KID --iss ISS [--state F] [--scenario NAME ...]

From the nightly's harness of 2026-10-29 (PR #246; ~/Downloads/sill-handoff/nightly/tests/asc-test), with
the build's localizations as a list (What to Test's scenarios, 2026-11-09) and no reverse lookup at bind.
"""
import argparse, base64, json, os, socketserver, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, urlencode

ap = argparse.ArgumentParser()
ap.add_argument('--port-file', required=True)
ap.add_argument('--log', required=True)
ap.add_argument('--state')
ap.add_argument('--pubkey', required=True)
ap.add_argument('--kid', required=True)
ap.add_argument('--iss', required=True)
ap.add_argument('--scenario', action='append', default=[])
ap.add_argument('--appear-after', type=int, default=2, help='GET /v1/builds answers without the build this many times')
ap.add_argument('--processing', type=int, default=2, help='then PROCESSING this many times')
ap.add_argument('--appear-at-seconds', type=float, default=0, help='or: the build appears only this long after start')
ap.add_argument('--page-size', type=int, default=0)
args = ap.parse_args()
S = set(args.scenario)
START = time.time()
lock = threading.Lock()

APP = {'type': 'apps', 'id': '6816359860', 'attributes': {'bundleId': 'me.saffer.sill', 'name': 'Sill – Mac Streaming'}}
OTHER_APP = {'type': 'apps', 'id': '1111111111', 'attributes': {'bundleId': 'me.saffer.sill.other', 'name': 'Another'}}
GROUPS = [
    {'id': 'g-insiders', 'name': 'Insiders', 'isInternalGroup': True, 'hasAccessToAllBuilds': False, 'publicLinkEnabled': False},
    {'id': 'g-team', 'name': 'Team', 'isInternalGroup': True, 'hasAccessToAllBuilds': True, 'publicLinkEnabled': False},
    {'id': 'g-public', 'name': 'Public Beta', 'isInternalGroup': False, 'hasAccessToAllBuilds': None, 'publicLinkEnabled': True},
    {'id': 'g-friends', 'name': 'Friends', 'isInternalGroup': False, 'hasAccessToAllBuilds': None, 'publicLinkEnabled': False},
]
if 'two-public' in S:
    GROUPS[3]['publicLinkEnabled'] = True
if 'no-public' in S:
    GROUPS[2]['publicLinkEnabled'] = False
if 'no-internal' in S:
    GROUPS = [g for g in GROUPS if not g['isInternalGroup']]

# The build's What to Test, one entry per language. A text given by hand (build 1304, 2026-11-09):
HAND = "What to Test in 0.6.1 (1304): the Duo's laptop pose with the keyboard up, and the Pencil's lift.\nThank you!"
localizations = []
if 'other-locale' in S:   # first, so a build with text in both is told by English (U.S.)'s
    localizations.append({'id': 'l-2', 'locale': 'en-GB', 'whatsNew': 'Colour and the Duo.'})
if 'existing-localization' in S:
    localizations.append({'id': 'l-1', 'locale': 'en-US', 'whatsNew': 'old'})
if 'hand-text' in S:
    localizations.append({'id': 'l-1', 'locale': 'en-US', 'whatsNew': HAND})
if 'empty-localization' in S:
    localizations.append({'id': 'l-1', 'locale': 'en-US', 'whatsNew': ''})
if 'null-localization' in S:
    localizations.append({'id': 'l-1', 'locale': 'en-US', 'whatsNew': None})
if 'blank-localization' in S:
    localizations.append({'id': 'l-1', 'locale': 'en-US', 'whatsNew': ' \n\t \n'})

state = {
    'builds_calls': 0, 'detail_calls': 0, 'build_id': 'b-983', 'version': os.environ.get('STANDIN_BUILD', '983'),
    'marketing': os.environ.get('STANDIN_VERSION', '0.6.0'),
    'members': {g['id']: set() for g in GROUPS},
    'external': 'READY_FOR_BETA_SUBMISSION', 'submitted': 0, 'throttled': False, 'flaked': False,
}
if 'already-approved' in S:
    state['external'] = 'BETA_APPROVED'
if 'external-stuck' in S:
    state['external'] = 'PROCESSING'


def save_state():
    if args.state:
        with open(args.state, 'w') as f:
            json.dump({'localizations': localizations, 'members': {k: sorted(v) for k, v in state['members'].items()},
                       'submitted': state['submitted']}, f)


def b64d(part):
    return base64.urlsafe_b64decode(part + '=' * (-len(part) % 4))


def der_int(b):
    b = b.lstrip(b'\x00') or b'\x00'
    if b[0] & 0x80:
        b = b'\x00' + b
    return b'\x02' + bytes([len(b)]) + b


def verify_token(token):
    """(ok, reason, header, claims)"""
    parts = token.split('.')
    if len(parts) != 3:
        return False, 'not three parts', None, None
    try:
        header = json.loads(b64d(parts[0])); claims = json.loads(b64d(parts[1])); sig = b64d(parts[2])
    except Exception as e:
        return False, 'undecodable: %s' % e, None, None
    now = time.time()
    if header != {'alg': 'ES256', 'kid': args.kid, 'typ': 'JWT'}:
        return False, 'header %r' % header, header, claims
    if set(claims) != {'iss', 'iat', 'exp', 'aud'}:
        return False, 'claims keys %r' % sorted(claims), header, claims
    if claims['iss'] != args.iss or claims['aud'] != 'appstoreconnect-v1':
        return False, 'iss or aud', header, claims
    if not (isinstance(claims['iat'], int) and isinstance(claims['exp'], int)):
        return False, 'iat/exp not integers', header, claims
    if claims['iat'] > now + 60 or claims['exp'] <= now or claims['exp'] - claims['iat'] > 1200:
        return False, 'times iat=%s exp=%s now=%d' % (claims['iat'], claims['exp'], now), header, claims
    if len(sig) != 64:
        return False, 'signature length %d' % len(sig), header, claims
    der = der_int(sig[:32]) + der_int(sig[32:])
    der = b'\x30' + bytes([len(der)]) + der
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, 'in'), 'wb').write((parts[0] + '.' + parts[1]).encode())
        open(os.path.join(d, 'sig'), 'wb').write(der)
        r = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', args.pubkey, '-signature',
                            os.path.join(d, 'sig'), os.path.join(d, 'in')], capture_output=True, text=True)
    if 'Verified OK' not in r.stdout:
        return False, 'signature: %s' % (r.stdout + r.stderr).strip(), header, claims
    return True, 'ok', header, claims


def page(items, query, path):
    size = args.page_size or int(query.get('limit', ['200'])[0])
    cursor = int(query.get('cursor', ['0'])[0])
    chunk = items[cursor:cursor + size]
    links = {'self': 'http://127.0.0.1:%d%s' % (PORT, path)}
    if cursor + size < len(items):
        q = dict((k, v[0]) for k, v in query.items()); q['cursor'] = str(cursor + size)
        host = 'http://evil.example' if 'bad-next' in S else 'http://127.0.0.1:%d' % PORT
        links['next'] = '%s%s?%s' % (host, path, urlencode(q))
    return {'data': chunk, 'links': links}


def build_resource():
    st = state
    calls = st['builds_calls']
    if 'never' in S:
        return None
    if args.appear_at_seconds:
        if time.time() - START < args.appear_at_seconds:
            return None
        processing = 'VALID'
    else:
        if calls <= args.appear_after:
            return None
        processing = 'PROCESSING' if calls <= args.appear_after + args.processing else 'VALID'
        if processing == 'VALID' and 'invalid' in S:
            processing = 'INVALID'
    return {'type': 'builds', 'id': st['build_id'],
            'attributes': {'version': st['version'], 'processingState': processing, 'expired': False,
                           'uploadedDate': '2026-10-30T03:30:00Z'}}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, status, obj=None, headers=None):
        body = b'' if obj is None else json.dumps(obj).encode()
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if obj is not None:
            self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, code, title, detail):
        self.reply(status, {'errors': [{'status': str(status), 'code': code, 'title': title, 'detail': detail}]})

    def handle_any(self, method):
        u = urlparse(self.path)
        query = parse_qs(u.query)
        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length) if length else b''
        try:
            body = json.loads(raw) if raw else None
        except Exception:
            body = {'unparsable': raw.decode('utf-8', 'replace')}
        auth = self.headers.get('Authorization', '')
        token = auth[7:] if auth.startswith('Bearer ') else ''
        ok, reason, header, claims = verify_token(token) if token else (False, 'no bearer token', None, None)
        entry = {'t': round(time.time() - START, 3), 'method': method, 'path': u.path,
                 'query': {k: v[0] for k, v in query.items()}, 'body': body,
                 'jwt_ok': ok, 'jwt_reason': reason, 'jwt_header': header, 'jwt_claims': claims, 'token': token,
                 'user_agent': self.headers.get('User-Agent', '')}
        with lock:
            with open(args.log, 'a') as f:
                f.write(json.dumps(entry) + '\n')
            if not ok:
                return self.error(401, 'NOT_AUTHORIZED', 'Authentication credentials are missing or invalid.', reason)
            if 'revoked' in S:
                return self.error(401, 'NOT_AUTHORIZED', 'Authentication credentials are missing or invalid.',
                                  'Provide a properly configured and signed bearer token.')
            try:
                return self.route(method, u.path, query, body)
            finally:
                save_state()

    def route(self, method, path, query, body):
        st = state
        if method == 'GET' and path == '/v1/apps' and 'redirect' in S:
            return self.reply(302, None, {'Location': 'http://127.0.0.1:%d/v1/elsewhere' % PORT})
        if method == 'GET' and path == '/v1/apps':
            if 'throttle' in S and not st['throttled']:
                st['throttled'] = True
                return self.reply(429, {'errors': [{'status': '429', 'code': 'RATE_LIMIT_EXCEEDED', 'title': 'Too many', 'detail': 'slow down'}]}, {'Retry-After': '0'})
            want = query.get('filter[bundleId]', [''])[0]
            apps = [a for a in (OTHER_APP, APP) if a['attributes']['bundleId'].startswith(want)]
            if 'no-app' in S:
                apps = [OTHER_APP]
            return self.reply(200, page(apps, query, path))
        if method == 'GET' and path == '/v1/betaGroups':
            if query.get('filter[app]', [''])[0] != APP['id']:
                return self.reply(200, page([], query, path))
            fields = query.get('fields[betaGroups]', [''])[0].split(',')
            items = [{'type': 'betaGroups', 'id': g['id'],
                      'attributes': {k: g[k] for k in ('name', 'isInternalGroup', 'hasAccessToAllBuilds', 'publicLinkEnabled') if k in fields}}
                     for g in GROUPS]
            return self.reply(200, page(items, query, path))
        if method == 'GET' and path == '/v1/builds':
            if 'flaky' in S and not st['flaked']:
                st['flaked'] = True
                return self.error(500, 'UNEXPECTED_ERROR', 'An unexpected error occurred.', 'try again')
            st['builds_calls'] += 1
            b = build_resource()
            match = (b is not None and query.get('filter[app]', [''])[0] == APP['id']
                     and query.get('filter[version]', [''])[0] == st['version']
                     and query.get('filter[preReleaseVersion.version]', [''])[0] == st['marketing'])
            return self.reply(200, page([b] if match else [], query, path))
        if method == 'GET' and path == '/v1/builds/%s/buildBetaDetail' % st['build_id']:
            st['detail_calls'] += 1
            internal = 'PROCESSING' if st['detail_calls'] == 1 else 'READY_FOR_BETA_TESTING'
            if 'compliance' in S:
                internal = 'MISSING_EXPORT_COMPLIANCE'
            return self.reply(200, {'data': {'type': 'buildBetaDetails', 'id': 'd-983',
                                             'attributes': {'internalBuildState': internal, 'externalBuildState': st['external']}}})
        if method == 'GET' and path == '/v1/builds/%s/betaBuildLocalizations' % st['build_id']:
            items = [{'type': 'betaBuildLocalizations', 'id': loc['id'],
                      'attributes': {'locale': loc['locale'], 'whatsNew': loc['whatsNew']}} for loc in localizations]
            return self.reply(200, page(items, query, path))
        if method == 'POST' and path == '/v1/betaBuildLocalizations':
            d = body['data']
            assert d['type'] == 'betaBuildLocalizations' and d['relationships']['build']['data'] == {'type': 'builds', 'id': st['build_id']}
            text = d['attributes']['whatsNew']
            if len(text.encode('utf-16-le')) // 2 > 4000:
                return self.error(409, 'ENTITY_ERROR.ATTRIBUTE.INVALID.TOO_LONG', 'too long', 'whatsNew')
            if any(loc['locale'] == d['attributes']['locale'] for loc in localizations):
                return self.error(409, 'ENTITY_ERROR.RELATIONSHIP.INVALID', 'duplicate', 'a localization in this locale exists')
            localizations.append({'id': 'l-new', 'locale': d['attributes']['locale'], 'whatsNew': text})
            return self.reply(201, {'data': {'type': 'betaBuildLocalizations', 'id': 'l-new', 'attributes': d['attributes']}})
        if method == 'PATCH' and path.startswith('/v1/betaBuildLocalizations/'):
            loc = next((l for l in localizations if l['id'] == path.rsplit('/', 1)[1]), None)
            if loc is None or body['data']['id'] != loc['id']:
                return self.error(404, 'NOT_FOUND', 'no such localization', path)
            loc['whatsNew'] = body['data']['attributes']['whatsNew']
            return self.reply(200, {'data': {'type': 'betaBuildLocalizations', 'id': loc['id'], 'attributes': loc}})
        if method == 'POST' and path.startswith('/v1/betaGroups/') and path.endswith('/relationships/builds'):
            gid = path.split('/')[3]
            g = next((g for g in GROUPS if g['id'] == gid), None)
            if g is None:
                return self.error(404, 'NOT_FOUND', 'no such group', gid)
            if g['hasAccessToAllBuilds']:
                return self.error(409, 'ENTITY_ERROR.RELATIONSHIP.INVALID', 'group has access to all builds', gid)
            ids = [x['id'] for x in body['data'] if x['type'] == 'builds']
            st['members'][gid].update(ids)
            return self.reply(204)
        if method == 'POST' and path == '/v1/betaAppReviewSubmissions':
            if 'review-conflict' in S:
                return self.error(409, 'ENTITY_ERROR.RELATIONSHIP.INVALID', 'Another build is in review',
                                  'You cannot submit this build while another build of this version is in review.')
            if st['external'] != 'READY_FOR_BETA_SUBMISSION':
                return self.error(409, 'STATE_ERROR', 'not ready', st['external'])
            st['submitted'] += 1
            st['external'] = 'WAITING_FOR_BETA_REVIEW'
            return self.reply(201, {'data': {'type': 'betaAppReviewSubmissions', 'id': 's-1',
                                             'attributes': {'betaReviewState': 'WAITING_FOR_REVIEW'}}})
        return self.error(404, 'NOT_FOUND', 'The specified resource does not exist', '%s %s' % (method, path))

    def do_GET(self): self.handle_any('GET')
    def do_POST(self): self.handle_any('POST')
    def do_PATCH(self): self.handle_any('PATCH')
    def do_DELETE(self): self.handle_any('DELETE')


class Server(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer's own asks socket.getfqdn('127.0.0.1'), a reverse lookup: 35 s on a Mac whose DNS
        # was slow to answer (2026-11-09), past run.sh's wait for the port.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


server = Server(('127.0.0.1', 0), H)
PORT = server.server_address[1]
save_state()
with open(args.port_file, 'w') as f:
    f.write(str(PORT))
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
