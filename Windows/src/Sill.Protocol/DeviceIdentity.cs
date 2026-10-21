using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace Sill.Protocol;

/// <summary>
/// This device's key: a P-256 key in a self-signed certificate, presented at every TLS
/// connection to a Mac, which pins its SPKI SHA-256 once paired (the iOS device's
/// <c>DeviceIdentity</c>). Kept in a directory as <c>device.p12</c>, made on first use.
/// </summary>
/// <remarks>
/// The spike keeps the key in an unprotected PKCS #12 file in the user's own folder, as
/// Scripts/sillclient.py keeps its PEM. A product keeps it non-exportable (CNG, or DPAPI over the
/// file). SChannel cannot use a key that exists only in memory, so the certificate is always
/// loaded from PKCS #12 bytes, never used straight from <c>CreateSelfSigned</c>.
/// </remarks>
public sealed class DeviceIdentity : IDisposable
{
    public const string FileName = "device.p12";

    public X509Certificate2 Certificate { get; }

    /// <summary>The SPKI SHA-256 of this device's key: fp_device in the proofs.</summary>
    public byte[] Fingerprint { get; }

    private DeviceIdentity(X509Certificate2 certificate)
    {
        Certificate = certificate;
        using var key = certificate.GetECDsaPublicKey()
            ?? throw new InvalidDataException("The device certificate's key is not ECDSA.");
        Fingerprint = Spki.Fingerprint(key) ?? throw new InvalidDataException("The device key is not P-256.");
    }

    /// <summary>The identity in <paramref name="directory"/>, made there if it has none.</summary>
    public static DeviceIdentity LoadOrCreate(string directory)
    {
        Directory.CreateDirectory(directory);
        string path = Path.Combine(directory, FileName);
        if (!File.Exists(path))
        {
            byte[] made = Create();
            // CreateNew: two processes making one at once keep the first.
            try { using var f = new FileStream(path, FileMode.CreateNew, FileAccess.Write); f.Write(made); }
            catch (IOException) when (File.Exists(path)) { }
        }
        return FromPkcs12(File.ReadAllBytes(path));
    }

    /// <summary>A fresh identity that is never saved (tests).</summary>
    public static DeviceIdentity CreateEphemeral() => FromPkcs12(Create());

    public static DeviceIdentity FromPkcs12(byte[] pkcs12) => new(X509CertificateLoader.LoadPkcs12(pkcs12, null));

    private static byte[] Create()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var request = new CertificateRequest("CN=Sill for Windows", key, HashAlgorithmName.SHA256);
        using var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(10));
        return cert.Export(X509ContentType.Pkcs12);
    }

    public void Dispose() => Certificate.Dispose();
}
