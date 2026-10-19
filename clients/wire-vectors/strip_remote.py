#!/usr/bin/env python3
"""Writes Remote.swift without what needs Apple's Security and CryptoKit (SignedMacInfo's
`signing` and `verified`), so its payloads compile with Foundation alone, on Linux too. Every
other line is the file as it is: the JSON the generator writes is the host's own types' JSON.
Fails loudly when the markers move, rather than compiling something else.
    strip_remote.py Sources/StreamProtocol/Remote.swift OUT.swift"""
import sys

src = open(sys.argv[1]).read()
start = "    /// Signs `info` with the Mac's identity key"
end = "    /// The MacInfo without checking anything"
if src.count(start) != 1 or src.count(end) != 1 or src.index(start) > src.index(end):
    sys.exit("strip_remote.py: Remote.swift's markers moved; update this script")
src = src[:src.index(start)] + src[src.index(end):]
for imp in ("import Security\n", "import CryptoKit\n"):
    if imp not in src:
        sys.exit(f"strip_remote.py: no {imp.strip()!r} in Remote.swift; update this script")
    src = src.replace(imp, "")
open(sys.argv[2], "w").write(src)
