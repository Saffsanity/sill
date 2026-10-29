using System.Security.Cryptography;
using System.Text;

namespace Sill.Protocol;

/// <summary>
/// The 12-digit typed code: 11 digits, then a Damm check digit. Mirrors <c>PairingCode</c> in
/// Sources/StreamProtocol/Pairing.swift.
/// </summary>
public static class PairingCode
{
    private static readonly int[,] Table =
    {
        { 0, 3, 1, 7, 5, 9, 8, 6, 4, 2 }, { 7, 0, 9, 2, 1, 5, 4, 8, 6, 3 }, { 4, 2, 0, 6, 8, 7, 1, 3, 5, 9 },
        { 1, 7, 5, 0, 9, 8, 3, 4, 2, 6 }, { 6, 1, 2, 3, 0, 4, 5, 9, 7, 8 }, { 3, 6, 7, 4, 2, 0, 9, 5, 8, 1 },
        { 5, 8, 6, 9, 7, 2, 0, 1, 3, 4 }, { 8, 9, 4, 5, 3, 6, 2, 0, 1, 7 }, { 9, 4, 3, 8, 6, 1, 7, 2, 0, 5 },
        { 2, 5, 8, 1, 4, 3, 6, 7, 9, 0 },
    };

    public const int Length = 12;

    /// <summary>The check digit for <paramref name="digits"/> (each 0–9); a valid code gives 0.</summary>
    public static int CheckDigit(IEnumerable<int> digits) => digits.Aggregate(0, (interim, d) => Table[interim, d]);

    public enum Problem { None, Length, Typo }

    /// <summary>
    /// <paramref name="input"/> as a code: spaces, hyphens and no-break spaces removed, exactly 12
    /// ASCII digits, the check digit valid. A typo is caught here and never costs one of the Mac's
    /// five tries.
    /// </summary>
    public static Problem Check(string input, out string code)
    {
        code = new string(input.Where(c => c is not (' ' or '-' or ' ')).ToArray());
        if (code.Length != Length || !code.All(char.IsAsciiDigit)) return Problem.Length;
        return CheckDigit(code.Select(c => c - '0')) == 0 ? Problem.None : Problem.Typo;
    }

    /// <summary>"4829 1355 7208".</summary>
    public static string Grouped(string code) =>
        string.Join(' ', Enumerable.Range(0, (code.Length + 3) / 4).Select(i => code.Substring(i * 4, Math.Min(4, code.Length - i * 4))));
}

/// <summary>
/// The keys and proofs of one pairing exchange. Mirrors <c>PairingProof</c> in Pairing.swift.
/// Each side takes the other's fingerprint from the TLS session, never from a message.
/// </summary>
public static class PairingProof
{
    public const int Rounds = 600_000;
    private const string Label = "sill-pair-v1";

    /// <summary>The typed path's key: PBKDF2-HMAC-SHA256(the 12 ASCII digits,
    /// "sill-pair-v1" ‖ fp_mac, 600,000 rounds, 32 bytes). Null for a code that is not 12 digits.</summary>
    public static byte[]? CodeKey(string code, ReadOnlySpan<byte> macFingerprint)
    {
        if (code.Length != PairingCode.Length || !code.All(char.IsAsciiDigit)) return null;
        byte[] salt = [.. Encoding.UTF8.GetBytes(Label), .. macFingerprint];
        return Rfc2898DeriveBytes.Pbkdf2(Encoding.ASCII.GetBytes(code), salt, Rounds, HashAlgorithmName.SHA256, 32);
    }

    private static byte[] Message(string who, ReadOnlySpan<byte> first, ReadOnlySpan<byte> second) =>
        [.. Encoding.UTF8.GetBytes($"{Label} {who}"), 0, .. first, .. second];

    /// <summary>proof_D = HMAC-SHA256(key, "sill-pair-v1 device" ‖ 0x00 ‖ fp_device ‖ fp_mac).</summary>
    public static byte[] DeviceProof(byte[] key, ReadOnlySpan<byte> deviceFingerprint, ReadOnlySpan<byte> macFingerprint) =>
        HMACSHA256.HashData(key, Message("device", deviceFingerprint, macFingerprint));

    /// <summary>proof_M = HMAC-SHA256(key, "sill-pair-v1 mac" ‖ 0x00 ‖ fp_mac ‖ fp_device).</summary>
    public static byte[] MacProof(byte[] key, ReadOnlySpan<byte> macFingerprint, ReadOnlySpan<byte> deviceFingerprint) =>
        HMACSHA256.HashData(key, Message("mac", macFingerprint, deviceFingerprint));

    /// <summary>The device's check of proof_M, in constant time.</summary>
    public static bool IsValidMacProof(ReadOnlySpan<byte> proof, byte[] key, ReadOnlySpan<byte> macFingerprint, ReadOnlySpan<byte> deviceFingerprint) =>
        CryptographicOperations.FixedTimeEquals(proof, MacProof(key, macFingerprint, deviceFingerprint));
}
