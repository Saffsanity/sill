using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;

namespace Sill.Protocol;

/// <summary>
/// The one TLS builder for every connection to a Mac (the iOS device's <c>DeviceTLS</c>; the
/// rules are RemoteTLS.swift's): TLS 1.3 only, this device's certificate, exactly one ALPN, and
/// trust by the Mac's SPKI SHA-256, never by name or chain.
/// </summary>
public static class SillTls
{
    public const string Session = "sill/1", Pairing = "sill-pair/1";

    /// <summary>The Mac presented another key than the pin: nothing was sent.</summary>
    public sealed class PinMismatchException(byte[] presented, byte[] expected)
        : AuthenticationException($"The Mac presented key {Base64Url.Encode(presented)[..10]}…, not the expected {Base64Url.Encode(expected)[..10]}…; nothing sent.")
    {
        public byte[] Presented { get; } = presented;
    }

    /// <summary>A TLS 1.3 connection with <paramref name="alpn"/> to <paramref name="host"/>.
    /// <paramref name="pin"/> null accepts any P-256 key (the typed code's path: its proofs bind
    /// both keys); otherwise the handshake fails unless the Mac's key is the pin.</summary>
    public static async Task<(SslStream Stream, byte[] MacFingerprint)> ConnectAsync(
        string host, int port, string alpn, DeviceIdentity identity, byte[]? pin, CancellationToken ct)
    {
        var tcp = new TcpClient { NoDelay = true };
        try
        {
            await tcp.ConnectAsync(host, port, ct).ConfigureAwait(false);
            var ssl = new SslStream(tcp.GetStream(), leaveInnerStreamOpen: false);
            byte[]? seen = null;
            try
            {
                await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
                {
                    TargetHost = "sill",
                    ClientCertificates = [identity.Certificate],
                    EnabledSslProtocols = SslProtocols.Tls13,
                    ApplicationProtocols = [new SslApplicationProtocol(alpn)],
                    CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
                    RemoteCertificateValidationCallback = (_, cert, _, _) =>
                    {
                        seen = cert is null ? null : Fingerprint(cert);
                        return seen is not null && (pin is null || seen.AsSpan().SequenceEqual(pin));
                    },
                }, ct).ConfigureAwait(false);
            }
            // SChannel ends a refused handshake with an IOException ("The decryption operation failed"),
            // other platforms with an AuthenticationException: either way the pin decides.
            catch (Exception e) when (e is AuthenticationException or IOException
                                      && seen is not null && pin is not null && !seen.AsSpan().SequenceEqual(pin))
            {
                ssl.Dispose();
                throw new PinMismatchException(seen, pin);
            }
            catch { ssl.Dispose(); throw; }

            if (ssl.SslProtocol != SslProtocols.Tls13 || ssl.NegotiatedApplicationProtocol.ToString() != alpn)
            {
                string got = $"{ssl.SslProtocol}, ALPN '{ssl.NegotiatedApplicationProtocol}'";
                ssl.Dispose();
                throw new AuthenticationException($"The Mac negotiated {got}, not TLS 1.3 with {alpn}.");
            }
            return (ssl, seen!);
        }
        catch { tcp.Dispose(); throw; }
    }

    /// <summary>The SPKI SHA-256 of a peer's certificate, null unless its key is P-256.</summary>
    public static byte[]? Fingerprint(X509Certificate cert)
    {
        var c2 = cert as X509Certificate2;
        using var owned = c2 is null ? new X509Certificate2(cert) : null;
        using var key = (c2 ?? owned!).GetECDsaPublicKey();
        return key is null ? null : Spki.Fingerprint(key);
    }
}
