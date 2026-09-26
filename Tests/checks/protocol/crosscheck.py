"""H3 cross-checks of what protocolcheck wrote, in Python and the system openssl (LibreSSL):
the certificate parses with a named curve, the SPKI fingerprint agrees, the Mac ID agrees, the tag
vector agrees, and kind 18's signature verifies with `openssl dgst -sha256 -verify`."""
import base64, hashlib, hmac, json, os, subprocess, sys, tempfile
D = sys.argv[1] if len(sys.argv) > 1 else "."
fails = 0
def check(name, ok):
    global fails
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails += 1
def b64u(b): return base64.urlsafe_b64encode(b).decode().rstrip("=")
def tlv(b, i):
    tag = b[i]; n = b[i + 1]; i += 2
    if n & 0x80:
        k = n & 0x7F; n = int.from_bytes(b[i:i + k], "big"); i += k
    return tag, i, i + n
def spki(der):
    _, cs, _ = tlv(der, 0); _, ts, te = tlv(der, cs)
    fields, i = [], ts
    while i < te:
        tag, _, end = tlv(der, i); fields.append((tag, i, end)); i = end
    if fields[0][0] == 0xA0: fields = fields[1:]
    _, start, end = fields[5]
    return der[start:end]
CROCK = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
def macid(fp):
    n = int.from_bytes(fp[:10], "big")
    return "".join(CROCK[(n >> (75 - 5 * i)) & 31] for i in range(16))

der = open(os.path.join(D, "cert.der"), "rb").read()
fp_swift = open(os.path.join(D, "cert.fp")).read().strip()
fp_py = b64u(hashlib.sha256(spki(der)).digest())
check(f"fingerprint agrees in Swift and Python ({fp_py[:10]}…)", fp_py == fp_swift)
text = subprocess.run(["/usr/bin/openssl", "x509", "-inform", "der", "-in", os.path.join(D, "cert.der"), "-noout", "-text"],
                      capture_output=True, text=True).stdout
check("openssl x509 parses it: version 3, ecdsa-with-SHA256, a named curve (prime256v1)",
      "Version: 3" in text and "ecdsa-with-SHA256" in text and "prime256v1" in text)
check("openssl x509: no extensions", "X509v3 extensions" not in text)
check("Mac ID vector in Python", macid(bytes.fromhex("50d858e0985ecc7f6041") + bytes(22)) == "A3C5HR4RBV67YR21")
rk = bytes([0x11]) * 32; p = bytes.fromhex("a1a2a3a4a5a6")
check("tag vector in Python", b64u(p + hmac.new(rk, b"sill-tag-v1" + p, hashlib.sha256).digest()[:6]) == "oaKjpKWmL4V47Ctm")

signed = json.load(open(os.path.join(D, "signed-macinfo.json")))
info = base64.b64decode(signed["info"]); point = base64.b64decode(signed["key"]); sig = base64.b64decode(signed["sig"])
# SPKI DER for the point, as a PEM public key for openssl
spki_der = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200") + point
pem = "-----BEGIN PUBLIC KEY-----\n" + base64.encodebytes(spki_der).decode() + "-----END PUBLIC KEY-----\n"
with tempfile.TemporaryDirectory() as t:
    open(os.path.join(t, "pub.pem"), "w").write(pem)
    open(os.path.join(t, "info.bin"), "wb").write(info)
    open(os.path.join(t, "sig.der"), "wb").write(sig)
    r = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-verify", os.path.join(t, "pub.pem"), "-signature", os.path.join(t, "sig.der"),
                        os.path.join(t, "info.bin")], capture_output=True, text=True)
    check(f"kind 18 verifies with openssl dgst ({r.stdout.strip()})", r.returncode == 0 and "Verified OK" in r.stdout)
    bad = bytearray(info); bad[3] ^= 1
    open(os.path.join(t, "info.bin"), "wb").write(bytes(bad))
    r = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-verify", os.path.join(t, "pub.pem"), "-signature", os.path.join(t, "sig.der"),
                        os.path.join(t, "info.bin")], capture_output=True, text=True)
    check(f"kind 18 with one flipped byte fails with openssl ({r.stdout.strip()})", r.returncode != 0)
decoded = json.loads(info)
check("kind 18's macID is MacID(SHA-256(SPKI(key))) in Python", decoded["macID"] == macid(hashlib.sha256(spki_der).digest()))
print("ALL PASS" if fails == 0 else f"{fails} FAILED")
sys.exit(fails)
