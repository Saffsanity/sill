---
status: accepted
---

# The Windows client is C# on .NET, an exception to Swift only

Sill is Swift and Apple frameworks only (CLAUDE.md, Conventions), but the Windows client in
`Windows/` is C# on .NET 10 (Jericho, 2026-10-17; the spike's question 3). A Windows client needs
TLS 1.3 with a client certificate, one ALPN and a pin on the peer's SPKI, P-256 keys and PBKDF2, and
Windows' own Media Foundation and Direct3D 11 for HEVC. .NET has the first two in the box (SslStream
over SChannel, System.Security.Cryptography) and reaches the third through plain COM calls, with no
third-party package; Swift on Windows has neither Network.framework nor the Security framework the
Mac and iOS code is built on, so little of `Sources/StreamProtocol` would have carried over, and TLS
and the Windows media APIs would have needed bindings of its own. The wire format and the pairing
rules stay defined by the Swift code: the C# port follows `Sources/StreamProtocol/` and is tested
against byte fixtures from it.

## Considered options

- Swift on Windows: one language, but no TLS stack with client certificates and ALPN, and C interop
  for every Windows API.
- C++ or Rust: native, but TLS through SChannel by hand or a bundled OpenSSL or rustls, a
  dependency the zero-dependency rule argues against.

## Consequences

- Two implementations of the protocol: a wire change lands in Swift first, then in
  `Windows/src/Sill.Protocol`, with a fixture from the Swift serializer.
- The Windows code builds and tests on its own solution and CI job (`.github/workflows/windows.yml`),
  outside `swift build` and `Tests/checks`.
- SChannel's TLS 1.3 sends the device's certificate before .NET judges the Mac's key
  (Windows/README.md, Security notes).
