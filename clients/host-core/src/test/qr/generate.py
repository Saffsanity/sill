#!/usr/bin/env python3
# The pairing window's QR codes as a second implementation draws them: python-qrcode 8.0 (pure
# Python, BSD), in byte mode at error correction M, its version and mask chosen by itself. QrCodeTest
# holds host-core's QrCode to these matrices module for module.
#   pip download qrcode==8.0 --no-deps -d DIR && python3 -m zipfile -e DIR/qrcode-8.0-py3-none-any.whl LIB
#   PYTHONPATH=LIB python3 -I clients/host-core/src/test/qr/generate.py > clients/host-core/src/test/resources/sill/qr-vectors.json
# (-I ignores PYTHONPATH: run without it, PYTHONPATH set.)
import json
import random

import qrcode
from qrcode.util import QRData, MODE_8BIT_BYTE

rng = random.Random(7455)
b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"


def token(n):
    return "".join(rng.choice(b64) for _ in range(n))


def link(name, addresses, port=7455):
    items = [("v", "1"), ("m", token(10)), ("k", token(43)), ("s", token(22)), ("n", name), ("p", str(port))]
    items += [("a", a) for a in addresses]
    return "sill://pair?" + "&".join(f"{k}={v.replace(' ', '%20')}" for k, v in items)


texts = [
    "a", "HELLO WORLD", "https://getsill.app", "0123456789" * 3, "é ünïcode ✓",
    "x" * 100, "y" * 180, "z" * 300, "w" * 500,
    link("DESKTOP-4K2Q", ["192.168.1.20"]),
    link("noah-thinkpad", ["192.168.1.34", "100.101.102.103"]),
    link("Erick's PC", ["10.0.0.5", "172.16.4.9", "100.64.0.7", "192.168.50.2"]),
    link("build-box", ["192.168.0.10"], port=50123),
]

out = []
for t in texts:
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=0)
    qr.add_data(QRData(t.encode("utf-8"), mode=MODE_8BIT_BYTE))
    qr.make(fit=True)
    rows = ["".join("1" if m else "0" for m in row) for row in qr.modules]
    out.append({"text": t, "version": qr.version, "mask": qr.mask_pattern if qr.mask_pattern is not None else qr.best_mask_pattern(), "rows": rows})
print(json.dumps(out, indent=1, ensure_ascii=False))
