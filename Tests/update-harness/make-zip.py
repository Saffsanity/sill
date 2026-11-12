"""Tests/update-harness: zips of a signed test app, as a release would ship it or made hostile on purpose.

usage: make-zip.py APP_DIR OUT_ZIP CASE   (APP_DIR is the folder holding UpdTest.app)
CASE: plain, appledouble (AppleDouble entries beside the app: skipped, the app installs), traversal
(an entry under ../), absolute (/tmp/...), link-escape (a link out of the app and a file written
through it), case-duplicate (Info.plist and info.plist), setuid (the executable setuid), not-a-bundle
(UpdTest.app is a file), second-top (another top-level folder)."""
import os, stat, sys, zipfile

src, out, case = sys.argv[1], sys.argv[2], sys.argv[3]
TOP = "UpdTest.app"

def info(name, mode, method=zipfile.ZIP_DEFLATED):
    i = zipfile.ZipInfo(name, date_time=(2026, 11, 11, 12, 0, 0))
    i.create_system = 3
    i.external_attr = mode << 16
    i.compress_type = method
    return i

with zipfile.ZipFile(out, "w") as z:
    if case == "not-a-bundle":
        z.writestr(info(TOP, 0o100644), b"not a folder")
    else:
        for dirpath, dirnames, filenames in os.walk(os.path.join(src, TOP)):
            dirnames.sort()
            rel = os.path.relpath(dirpath, src)
            z.writestr(info(rel + "/", 0o040755, zipfile.ZIP_STORED), b"")
            for name in sorted(filenames):
                path = os.path.join(dirpath, name)
                mode = os.lstat(path).st_mode
                entry = os.path.join(rel, name)
                if case == "setuid" and name == "UpdTest" and os.path.basename(dirpath) == "MacOS":
                    mode |= stat.S_ISUID
                with open(path, "rb") as f:
                    z.writestr(info(entry, mode & 0o177777), f.read())
                if case == "case-duplicate" and name == "Info.plist":
                    with open(path, "rb") as f:
                        z.writestr(info(os.path.join(rel, "info.plist"), 0o100644), f.read())
        if case == "appledouble":
            z.writestr(info(TOP + "/Contents/._Info.plist", 0o100644), b"\x00\x05\x16\x07appledouble")
            z.writestr(info("__MACOSX/" + TOP + "/._Contents", 0o100644), b"\x00\x05\x16\x07appledouble")
        if case == "traversal":
            z.writestr(info(TOP + "/../../escaped.txt", 0o100644), b"written outside")
        if case == "absolute":
            z.writestr(info("/tmp/update-harness-absolute.txt", 0o100644), b"written outside")
        if case == "link-escape":
            z.writestr(info(TOP + "/Contents/Resources/escape", 0o120755, zipfile.ZIP_STORED), b"../../../../outside")
            z.writestr(info(TOP + "/Contents/Resources/escape/pwned.txt", 0o100644), b"written through the link")
        if case == "second-top":
            z.writestr(info("Other.app/", 0o040755, zipfile.ZIP_STORED), b"")
            z.writestr(info("Other.app/x", 0o100644), b"x")
