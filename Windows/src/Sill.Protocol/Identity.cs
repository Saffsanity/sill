using System.Security.Cryptography;

namespace Sill.Protocol;

/// <summary>
/// base64url without padding (RFC 4648 §5): every byte string in the pairing link, kind 19 and
/// kind 20. Mirrors <c>Base64URL</c> in Sources/StreamProtocol/RemoteIdentity.swift.
/// </summary>
public static class Base64Url
{
    public static string Encode(ReadOnlySpan<byte> data) =>
        Convert.ToBase64String(data).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    /// <summary>Null for anything that is not canonical unpadded base64url (padding, + or /,
    /// whitespace, a length no encoding produces, trailing bits set).</summary>
    public static byte[]? Decode(string text)
    {
        foreach (char c in text)
            if (!(c is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '_')) return null;
        if (text.Length % 4 == 1) return null;
        string s = text.Replace('-', '+').Replace('_', '/');
        s += new string('=', (4 - s.Length % 4) % 4);
        byte[] d;
        try { d = Convert.FromBase64String(s); } catch (FormatException) { return null; }
        return Encode(d) == text ? d : null;
    }
}

/// <summary>
/// The SubjectPublicKeyInfo of a P-256 key and its SHA-256, the fingerprint every pin compares.
/// Mirrors <c>SPKI</c> in RemoteIdentity.swift.
/// </summary>
public static class Spki
{
    // SEQUENCE { SEQUENCE { OID 1.2.840.10045.2.1, OID 1.2.840.10045.3.1.7 }, BIT STRING (0x00 ‖ point) }:
    // for a 65-byte point every length is short, so the prefix is fixed.
    private static readonly byte[] Prefix =
    [
        0x30, 0x59, 0x30, 0x13,
        0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
        0x03, 0x42, 0x00,
    ];

    /// <summary>The SPKI DER of a 65-byte uncompressed X9.63 point (04 ‖ X ‖ Y).</summary>
    public static byte[] Der(ReadOnlySpan<byte> point)
    {
        if (point.Length != 65 || point[0] != 0x04)
            throw new ArgumentException("A P-256 point is 65 bytes starting 0x04.", nameof(point));
        return [.. Prefix, .. point];
    }

    /// <summary>SHA-256 of <see cref="Der"/>: 32 bytes.</summary>
    public static byte[] Fingerprint(ReadOnlySpan<byte> point) => SHA256.HashData(Der(point));

    /// <summary>The fingerprint of a P-256 key, null for any other curve.</summary>
    public static byte[]? Fingerprint(ECDsa key)
    {
        var p = key.ExportParameters(false);
        if (p.Curve.Oid?.Value != "1.2.840.10045.3.1.7" || p.Q.X is not { Length: 32 } x || p.Q.Y is not { Length: 32 } y)
            return null;
        return Fingerprint([0x04, .. x, .. y]);
    }
}

/// <summary>
/// The Mac ID: Crockford base32 of the fingerprint's first 10 bytes, 16 characters. Mirrors
/// <c>MacID</c> in RemoteIdentity.swift.
/// </summary>
public static class MacId
{
    public const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    public static string Make(ReadOnlySpan<byte> fingerprint)
    {
        if (fingerprint.Length < 10) return "";
        var chars = new char[16];
        int buffer = 0, bits = 0, n = 0;
        foreach (byte b in fingerprint[..10])
        {
            buffer = (buffer << 8) | b; bits += 8;
            while (bits >= 5) { bits -= 5; chars[n++] = Alphabet[(buffer >> bits) & 31]; }
            buffer &= (1 << bits) - 1;
        }
        return new string(chars);
    }

    public static bool IsWellFormed(string text) => text.Length == 16 && text.All(c => Alphabet.Contains(c));
}
