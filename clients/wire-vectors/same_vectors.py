#!/usr/bin/env python3
"""Whether two vectors.json files say the same, whatever order a Swift release writes JSON keys in:
each message's `json` (the Mac's own encoder's bytes) compared as parsed JSON, everything else as is.
SafeText's class of every scalar comes from the Swift toolchain's own Unicode tables, so two Swift
releases may differ where one Unicode version assigns a character the other does not have yet: a
scalar kept (0) by one and removed (2) by the other is tolerated, up to 8,000 of them (Unicode 15.1
and 16.0 assigned about 5,500); any other difference is a real one.
    same_vectors.py A.json B.json     exit 0 when they agree, 1 with the first difference"""
import json, sys

def load(path):
    d = json.load(open(path))
    for m in d["messages"]:
        m["json"] = json.loads(m["json"])
        m["sorted"] = json.loads(m["sorted"])
    return d

def classes(runs):
    out = {}
    for start, end, cls in runs:
        for cp in range(start, end + 1):
            out[cp] = cls
    return out

def same_classes(x, y):
    cx, cy = classes(x), classes(y)
    if cx.keys() != cy.keys():
        print("differs: safeTextClasses covers other scalars")
        return False
    newer = 0
    for cp, c in cx.items():
        d = cy[cp]
        if c == d:
            continue
        if {c, d} == {0, 2}:
            newer += 1
            continue
        print(f"differs: safeTextClasses at U+{cp:04X}: {c} against {d}")
        return False
    if newer > 8000:
        print(f"differs: safeTextClasses: {newer} scalars kept by one and removed by the other")
        return False
    if newer:
        print(f"safeTextClasses: {newer} scalars differ by Unicode version (tolerated)")
    return True

a, b = load(sys.argv[1]), load(sys.argv[2])
for key in sorted(set(a) | set(b)):
    if key == "safeTextClasses" and key in a and key in b:
        if not same_classes(a[key], b[key]):
            sys.exit(1)
        continue
    if a.get(key) != b.get(key):
        if key == "messages":
            for x, y in zip(a[key], b[key]):
                if x != y:
                    print(f"differs: message {x.get('name')}:\n  {x}\n  {y}")
                    sys.exit(1)
        print(f"differs: {key}")
        sys.exit(1)
print("same content")
