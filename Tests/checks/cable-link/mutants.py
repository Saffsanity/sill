"""H3 (step 1) CableLink mutants: each must compile and make cable-link/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/CableLink.swift"
M = [
    ("any vendor", F, "guard let a, a.ncm, a.vendor == appleVendor, let name = a.productName else { return false }",
     "guard let a, a.ncm, let name = a.productName else { return false }"),
    ("no NCM interface needed", F, "guard let a, a.ncm, a.vendor == appleVendor, let name = a.productName else { return false }",
     "guard let a, a.vendor == appleVendor, let name = a.productName else { return false }"),
    ("any product name", F, "        return products.contains(name)\n", "        return !name.isEmpty\n"),
    ("a product name that starts with iPhone or iPad", F, "        return products.contains(name)\n", "        return products.contains { name.hasPrefix($0) }\n"),
    ("case-insensitive product name", F, "        return products.contains(name)\n", "        return products.contains { $0.lowercased() == name.lowercased() }\n"),
    ("an IPv4 link-local source counts", F, "guard source.count == 16, IPBytes.isLinkLocal(source), let scope, !scope.isEmpty else { return nil }",
     "guard IPBytes.isLinkLocal(source), let scope, !scope.isEmpty else { return nil }"),
    ("a routed IPv6 source counts", F, "guard source.count == 16, IPBytes.isLinkLocal(source), let scope, !scope.isEmpty else { return nil }",
     "guard source.count == 16, let scope, !scope.isEmpty else { return nil }"),
    ("an empty scope is an interface", F, "guard source.count == 16, IPBytes.isLinkLocal(source), let scope, !scope.isEmpty else { return nil }",
     "guard source.count == 16, IPBytes.isLinkLocal(source), let scope else { return nil }"),
    ("this Mac's own addresses not checked", F, "        guard !ownAddresses.contains(where: { IPBytes.unscoped($0) == s }) else { return nil }\n", ""),
    ("own addresses compared with the embedded scope", F, "guard !ownAddresses.contains(where: { IPBytes.unscoped($0) == s }) else { return nil }",
     "guard !ownAddresses.contains(source) else { return nil }"),
    ("no serial needed", F, "guard let a = cables[scope], isPhoneOrPadCable(a), let serial = a.serial, !serial.isEmpty else { return nil }",
     "guard let a = cables[scope], isPhoneOrPadCable(a) else { return nil }"),
    ("an empty serial is one", F, "guard let a = cables[scope], isPhoneOrPadCable(a), let serial = a.serial, !serial.isEmpty else { return nil }",
     "guard let a = cables[scope], isPhoneOrPadCable(a), let serial = a.serial else { return nil }"),
    ("the stand-in before the link-local rule", F,
     "        guard source.count == 16, IPBytes.isLinkLocal(source), let scope, !scope.isEmpty else { return nil }\n        if let standIn, scope == standIn { return testAncestry }",
     "        if let standIn, let scope, scope == standIn { return testAncestry }\n        guard source.count == 16, IPBytes.isLinkLocal(source), let scope, !scope.isEmpty else { return nil }"),
    ("the stand-in keeps rule 2", F, "        if let standIn, scope == standIn { return testAncestry }\n",
     "        if let standIn, scope == standIn, !ownAddresses.contains(where: { IPBytes.unscoped($0) == IPBytes.unscoped(source) }) { return testAncestry }\n"),
    ("the stand-in on any host", F, "guard testHost, let name = environment[\"SILL_TEST_CABLE_INTERFACE\"]", "guard let name = environment[\"SILL_TEST_CABLE_INTERFACE\"]"),
    ("the stand-in takes any text", F, "        guard testHost, let name = environment[\"SILL_TEST_CABLE_INTERFACE\"], let first = name.first, first.isLetter,\n              name.count <= 15, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }",
     "        guard testHost, let name = environment[\"SILL_TEST_CABLE_INTERFACE\"], !name.isEmpty else { return nil }"),
    ("deviceID keeps 32 bytes", F, "SHA256.hash(data: input).prefix(16)", "SHA256.hash(data: input).prefix(32)"),
    ("deviceID without its label", F, "var input = Data(\"sill-cable-v1\".utf8)", "var input = Data()"),
    ("deviceID is the serial", F, "return Base64URL.encode(Data(SHA256.hash(data: input).prefix(16)))", "return Base64URL.encode(Data(serial.utf8))"),
    ("the stand-in device has no serial", F, "productName: \"iPad\", serial: \"TEST\", session: 1)", "productName: \"iPad\", serial: nil, session: 1)"),
]
sys.exit(0 if module.mutate("cable-link", M, sys.argv[1]) else 1)
