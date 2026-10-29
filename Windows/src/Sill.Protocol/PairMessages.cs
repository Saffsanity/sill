using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>Message kinds this client sends or reads (StreamMessage.swift's <c>Kind</c>).</summary>
public static class Kinds
{
    public const byte PairRequest = 19;
    public const byte PairResult = 20;
}

/// <summary>
/// Kind 19: the device's one message on a <c>sill-pair/1</c> connection. Mirrors
/// <c>PairRequest</c> in Sources/StreamProtocol/Remote.swift. Null fields are left out of the
/// JSON, as Swift's synthesized Codable leaves out nil optionals.
/// </summary>
public sealed record PairRequest(
    [property: JsonPropertyName("v")] int V,
    [property: JsonPropertyName("method")] string Method,
    [property: JsonPropertyName("proof")] string Proof,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("model")] string? Model,
    [property: JsonPropertyName("cable")] bool? Cable = null)
{
    /// <summary>The one generation of kind 19; a host answers any other <c>closed</c>.</summary>
    public const int Version = 1;
    public const string Qr = "qr", Code = "code";
    /// <summary>At the home door: "show your code" (no proof). The Mac answers "shown",
    /// "openOnMac" or "locked" (<see cref="PairResult"/>).</summary>
    public const string Ask = "ask";
    /// <summary>At the home door, after an ask answered "shown": the device's Cancel, no proof;
    /// the window that ask opened closes.</summary>
    public const string Cancel = "cancel";
}

/// <summary>Kind 20: the Mac's answer; it closes the connection after it. Mirrors <c>PairResult</c>.</summary>
public sealed record PairResult(
    [property: JsonPropertyName("ok")] bool Ok,
    [property: JsonPropertyName("proof")] string? Proof = null,
    [property: JsonPropertyName("macID")] string? MacId = null,
    [property: JsonPropertyName("name")] string? Name = null,
    [property: JsonPropertyName("recognitionKey")] string? RecognitionKey = null,
    [property: JsonPropertyName("reason")] string? Reason = null,
    [property: JsonPropertyName("triesLeft")] int? TriesLeft = null,
    [property: JsonPropertyName("retryAfter")] double? RetryAfter = null,
    [property: JsonPropertyName("method")] string? Method = null,
    [property: JsonPropertyName("message")] string? Message = null)
{
    public const string WrongCode = "code", Closed = "closed", Expired = "expired", Stopped = "stopped", Busy = "busy",
        Shown = "shown", OpenOnMac = "openOnMac", Locked = "locked";

    /// <summary>The reasons this build words itself (<c>PairResult.knownReasons</c>); for any other the
    /// Mac's <see cref="Message"/> shows, when it sent one.</summary>
    public static readonly string[] KnownReasons = [WrongCode, Closed, Expired, Stopped, Busy, Shown, OpenOnMac, Locked];
}

/// <summary>
/// One pairing exchange, without the socket: the kind 19 to send, and the judgement of the kind
/// 20 that comes back, as the iOS device judges it (StreamClient+Remote.swift): nothing is
/// trusted unless proof_M checks for this connection's two keys, the Mac ID is the Mac's key's,
/// and the recognition key is 32 bytes.
/// </summary>
public sealed class PairingExchange
{
    private readonly byte[] key;
    private readonly byte[] macFingerprint;
    private readonly byte[] deviceFingerprint;
    public string Method { get; }

    private PairingExchange(string method, byte[] key, byte[] macFingerprint, byte[] deviceFingerprint)
    {
        Method = method; this.key = key; this.macFingerprint = macFingerprint; this.deviceFingerprint = deviceFingerprint;
    }

    /// <summary>The typed path. <paramref name="macFingerprint"/> is the key the Mac presented in
    /// this TLS session; the code must already have passed <see cref="PairingCode.Check"/>.</summary>
    public static PairingExchange ForCode(string code, byte[] macFingerprint, byte[] deviceFingerprint) =>
        new(PairRequest.Code,
            PairingProof.CodeKey(code, macFingerprint) ?? throw new ArgumentException("Not a 12-digit code.", nameof(code)),
            macFingerprint, deviceFingerprint);

    /// <summary>The link's path. The TLS session must already have pinned the Mac to
    /// <c>link.Fingerprint</c>, so no proof goes to another key. (SChannel's TLS 1.3 sends the
    /// device's certificate before the pin is judged; the iOS device's verify block runs first.)</summary>
    public static PairingExchange ForLink(PairLink link, byte[] deviceFingerprint) =>
        new(PairRequest.Qr, link.Secret, link.Fingerprint, deviceFingerprint);

    public PairRequest Request(string deviceName, string? model) =>
        new(PairRequest.Version, Method, Base64Url.Encode(PairingProof.DeviceProof(key, deviceFingerprint, macFingerprint)),
            deviceName, model);

    /// <summary>The whole kind 19 message: header and JSON.</summary>
    public byte[] RequestMessage(string deviceName, string? model) =>
        StreamHeader.Serialize(Kinds.PairRequest, 0, false, JsonSerializer.SerializeToUtf8Bytes(Request(deviceName, model), SessionMessages.Json));

    public enum Verdict { Paired, Refused, NoProof, Malformed }

    /// <summary>A kind 20's payload judged. <paramref name="result"/> is null only when it does
    /// not decode.</summary>
    public Verdict Judge(ReadOnlySpan<byte> payload, out PairResult? result)
    {
        try { result = JsonSerializer.Deserialize<PairResult>(payload, SessionMessages.Json); }
        catch (JsonException) { result = null; }
        if (result is null) return Verdict.Malformed;
        if (!result.Ok) return Verdict.Refused;
        byte[]? proof = result.Proof is { } p ? Base64Url.Decode(p) : null;
        byte[]? recognition = result.RecognitionKey is { } r ? Base64Url.Decode(r) : null;
        if (proof is null || !PairingProof.IsValidMacProof(proof, key, macFingerprint, deviceFingerprint)
            || result.MacId != MacId.Make(macFingerprint) || recognition is not { Length: 32 })
            return Verdict.NoProof;
        return Verdict.Paired;
    }

    /// <summary>
    /// A refusal in the iOS device's words (StreamClient+Remote.swift: <c>problem(for:mac:)</c>
    /// and <c>PairingProblem.text</c>). A reason this build does not know shows the Mac's
    /// <c>message</c> when it has one (<c>PairResult.unknownReasonMessage</c>).
    /// </summary>
    public static string Words(PairResult r, string mac)
    {
        if (!r.Ok && !PairResult.KnownReasons.Contains(r.Reason) && SafeText.Label(r.Message ?? "", 300) is { Length: > 0 } said) return said;
        switch (r.Reason)
        {
            case PairResult.WrongCode:
                int left = Math.Max(0, r.TriesLeft ?? 0);
                return $"That code didn’t work. Check the code on your Mac. {left}\u00A0tr{(left == 1 ? "y" : "ies")} left.";
            case PairResult.Expired:
                return "This code expired. Choose Pair iPhone or iPad… on your Mac for a new one.";
            case PairResult.Stopped:
                return $"{mac} stopped pairing after too many wrong codes. Choose Pair iPhone or iPad… on your Mac for a new code.";
            // An ask's answers (DiscoveryPolicy.swift's HomeCopy, the device's words for each).
            case PairResult.Shown:
                return $"{mac} is showing a code.";
            case PairResult.OpenOnMac:
                return $"{mac} didn’t show a code by itself. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then try again.";
            case PairResult.Locked:
                return $"Unlock {mac}, then try again.";
            default:
                return $"{mac} isn’t pairing right now. On your Mac, choose Pair iPhone or iPad… first.";
        }
    }
}

/// <summary>Reads whole messages from any stream (an <c>SslStream</c> in the client).</summary>
public static class MessageStream
{
    /// <summary>The next message, or null at a clean end before a header. Throws
    /// <see cref="InvalidDataException"/> for a payload over <paramref name="maxPayload"/> and
    /// <see cref="EndOfStreamException"/> for an end mid-message.</summary>
    public static Task<(StreamHeader Header, byte[] Payload)?> ReadAsync(Stream stream, int maxPayload, CancellationToken ct = default) =>
        ReadAsync(stream, _ => maxPayload, ct);

    /// <summary>As above, with a cap for each kind (<see cref="SessionKinds.MaxPayload"/>).</summary>
    public static async Task<(StreamHeader Header, byte[] Payload)?> ReadAsync(Stream stream, Func<byte, int> maxPayload, CancellationToken ct = default)
    {
        var head = new byte[StreamHeader.Length];
        int got = 0;
        while (got < head.Length)
        {
            int n = await stream.ReadAsync(head.AsMemory(got), ct).ConfigureAwait(false);
            if (n == 0)
            {
                if (got == 0) return null;
                throw new EndOfStreamException("The connection ended inside a header.");
            }
            got += n;
        }
        var header = StreamHeader.Parse(head);
        int cap = maxPayload(header.Kind);
        if (header.PayloadLength > (uint)cap)
            throw new InvalidDataException($"A kind {header.Kind} of {header.PayloadLength} bytes is over the {cap}-byte cap.");
        var payload = new byte[header.PayloadLength];
        await stream.ReadExactlyAsync(payload, ct).ConfigureAwait(false);
        return (header, payload);
    }
}
