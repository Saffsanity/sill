using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>One way to reach the Mac from afar. Mirrors <c>MacAddress</c> in Remote.swift: plain
/// strings, never enums, so a kind an older reader doesn't know is kept, not refused.</summary>
public sealed record MacAddress(
    [property: JsonPropertyName("host")] string Host,
    [property: JsonPropertyName("port")] int? Port,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("via")] string Via)
{
    public const string Vpn = "vpn", Lan = "lan", Internet = "internet";
}

/// <summary>Inside kind 18: who this Mac is and how to reach it from afar. Mirrors <c>MacInfo</c>
/// in Remote.swift (the fields this client reads).</summary>
public sealed record MacInfo(
    [property: JsonPropertyName("v")] int V,
    [property: JsonPropertyName("macID")] string MacId,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("issuedAt")] double IssuedAt,
    [property: JsonPropertyName("remoteAccess")] bool RemoteAccess,
    [property: JsonPropertyName("remotePort")] int RemotePort,
    [property: JsonPropertyName("internet")] bool Internet,
    [property: JsonPropertyName("addresses")] IReadOnlyList<MacAddress> Addresses);

/// <summary>
/// Kind 18 (<c>SignedMacInfo</c> in Remote.swift): <c>info</c> is the exact JSON bytes of a
/// <see cref="MacInfo"/>, <c>key</c> the Mac's public key (X9.63, 65 bytes), <c>sig</c> a DER
/// ECDSA P-256 / SHA-256 signature over those bytes; all three plain base64.
/// </summary>
public sealed record SignedMacInfo(
    [property: JsonPropertyName("info")] string Info,
    [property: JsonPropertyName("key")] string Key,
    [property: JsonPropertyName("sig")] string Sig)
{
    public static SignedMacInfo? Decode(ReadOnlySpan<byte> payload) => SessionMessages.Decode<SignedMacInfo>(payload);

    /// <summary>The MacInfo and the fingerprint of the key that signed it, when the signature
    /// verifies over the exact <c>info</c> bytes, the key is a P-256 point, the JSON decodes and its
    /// <c>macID</c> is that key's Mac ID (<c>verified()</c> in Remote.swift, <c>verify_macinfo</c> in
    /// sillclient.py). Whether the key is the one this PC paired with is the caller's question
    /// (<see cref="SavedMacs.Taking"/>).</summary>
    public (MacInfo Info, byte[] Fingerprint)? Verified()
    {
        byte[] bytes, point, sig;
        try { bytes = Convert.FromBase64String(Info); point = Convert.FromBase64String(Key); sig = Convert.FromBase64String(Sig); }
        catch (FormatException) { return null; }
        if (point.Length != 65 || point[0] != 0x04) return null;
        try
        {
            using var key = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = point[1..33], Y = point[33..] },
            });
            if (!key.VerifyData(bytes, sig, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence)) return null;
        }
        catch (CryptographicException) { return null; }   // not a point on the curve, a malformed signature
        MacInfo? info;
        try { info = JsonSerializer.Deserialize<MacInfo>(bytes); }
        catch (JsonException) { return null; }
        if (info is null || info.MacId is null) return null;
        var fp = Spki.Fingerprint(point);
        return info.MacId == MacId.Make(fp) ? (info with { Addresses = info.Addresses ?? [] }, fp) : null;
    }

    /// <summary>A kind 18 signed with <paramref name="key"/> (a stand-in Mac, for the tests).</summary>
    public static SignedMacInfo Signing(MacInfo info, ECDsa key)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(info);
        var p = key.ExportParameters(false);
        return new SignedMacInfo(Convert.ToBase64String(bytes), Convert.ToBase64String([0x04, .. p.Q.X!, .. p.Q.Y!]),
            Convert.ToBase64String(key.SignData(bytes, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence)));
    }
}
