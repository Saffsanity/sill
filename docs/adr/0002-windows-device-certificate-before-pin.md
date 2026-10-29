---
status: accepted
---

# The Windows client sends its certificate before it judges the Mac's key

On Windows the client uses .NET's SslStream over SChannel (ADR 0001). SChannel's TLS 1.3 sends the
device's client certificate in its last handshake flight and only then hands the Mac's certificate to
.NET's validation callback (`SillTls.ConnectAsync`, `RemoteCertificateValidationCallback`). So a Mac
the PC has not pinned (one being paired, a link naming another key, an impostor at a saved address)
learns the PC's certificate before the handshake is refused. We accept this (Windows/README.md,
2026-10-19; Jericho, 2026-10-25, ticket 11): the certificate holds a public key and fixed fields (`CN=Sill for Windows`, a random
serial), which prove nothing without the private key in `device.p12`; the key is Sill's alone, so it
links the PC to nothing outside Sill (at most an impostor recognises the same PC trying again); and
nothing else is sent: the callback fails the handshake before any kind 19, hello or input, since the
Mac must prove the pinned key with TLS 1.3's CertificateVerify first. The test
`ALinkToAnotherKeySendsNothing` pins the behaviour down. Windows/README.md, Security notes, has the
details.

## Considered options

- Judge the Mac's key first, as the iPhone and iPad do (Network.framework's verify block runs when
  the Mac's certificate arrives, so a refused Mac never gets the device's). SslStream on SChannel
  offers no hook at that point.
- Another TLS stack (a bundled OpenSSL, say) that verifies before sending: buys that order at the
  cost of a third-party dependency, against the zero-dependency rule, to protect a key that is
  already public.

## Consequences

- The two device platforms differ here on purpose: don't "fix" the Windows order without one of the
  options above, and don't read it as a weakness in the pairing proofs, which bind both keys on the
  typed code's path as on iOS.
- Anything secret added to the client's certificate later (a name, an account) would change this
  trade-off: keep the certificate's fields fixed and anonymous.
