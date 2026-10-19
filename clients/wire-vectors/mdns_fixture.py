#!/usr/bin/env python3
"""Writes clients/core/src/test/resources/sill/mdns-response.hex: an mDNS response for one Sill Mac,
built by python-zeroconf (pip install zeroconf), an implementation that shares nothing with the
core's DNS code: PTR, SRV, TXT (r, p and a boolean key), A and AAAA, with zeroconf's own name
compression, as a responder answers a one-shot query. MdnsTest parses it.
    python3 clients/wire-vectors/mdns_fixture.py"""
import os, socket
from zeroconf import DNSOutgoing, DNSPointer, DNSService, DNSText, DNSAddress
from zeroconf.const import _FLAGS_QR_RESPONSE, _FLAGS_AA, _TYPE_PTR, _TYPE_SRV, _TYPE_TXT, _TYPE_A, _TYPE_AAAA, _CLASS_IN, _CLASS_UNIQUE

stype = "_sill._tcp.local."
name = "Noah’s Mac mini." + stype
host = "Noahs-Mac-mini.local."
out = DNSOutgoing(_FLAGS_QR_RESPONSE | _FLAGS_AA, multicast=False)
out.id = 0
out.add_answer_at_time(DNSPointer(stype, _TYPE_PTR, _CLASS_IN, 10, name), 0)
out.add_additional_answer(DNSService(name, _TYPE_SRV, _CLASS_IN | _CLASS_UNIQUE, 10, 0, 0, 52144, host))
txt = b"".join(bytes([len(s)]) + s for s in [b"r=oaKjpKWmL4V47Ctm", b"p=1", "n=café".encode(), b"flag"])
out.add_additional_answer(DNSText(name, _TYPE_TXT, _CLASS_IN | _CLASS_UNIQUE, 10, txt))
out.add_additional_answer(DNSAddress(host, _TYPE_A, _CLASS_IN | _CLASS_UNIQUE, 10, socket.inet_aton("192.168.1.20")))
out.add_additional_answer(DNSAddress(host, _TYPE_AAAA, _CLASS_IN | _CLASS_UNIQUE, 10, socket.inet_pton(socket.AF_INET6, "fe80::1c2b:3d4e:5f60:7182")))
packet = out.packets()[0]
path = os.path.join(os.path.dirname(__file__), "../core/src/test/resources/sill/mdns-response.hex")
open(path, "w").write(packet.hex() + "\n")
print(f"wrote {len(packet)} bytes")
