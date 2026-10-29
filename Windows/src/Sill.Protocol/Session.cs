using System.Buffers.Binary;
using System.Net.Security;
using System.Text.Json;
using System.Text;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>The session's message kinds this client sends or reads (StreamMessage.swift's <c>Kind</c>).</summary>
public static class SessionKinds
{
    public const byte ParameterSets = 0, Frame = 1, WindowList = 2, Thumbnail = 3, AppIcon = 4, AppList = 5,
        SelectSource = 6, LaunchApp = 7, WindowCommand = 15, Gesture = 28, Viewport = 9,
        Ping = 10, Pong = 11, ClientStats = 12, Tick = 13, CursorShape = 14, HostSettings = 16, MacInfo = 18, Goodbye = 22, Hello = 23, Clipboard = ClipboardPolicy.Kind;

    /// <summary>What a header from the Mac may announce (StreamMessage.swift's caps): frames
    /// 32 MiB, anything else 4 MiB. A reader refuses more and closes.</summary>
    public static int MaxPayload(byte kind) =>
        kind == Frame ? StreamHeader.MaxFramePayload : StreamHeader.MaxOtherHostPayload;
}

/// <summary>Kind 23: the device's first message on every session connection. Mirrors <c>Hello</c>
/// in Sources/StreamProtocol/Compatibility.swift.</summary>
public sealed record Hello(
    [property: JsonPropertyName("appVersion")] string? AppVersion,
    [property: JsonPropertyName("build")] string? Build,
    [property: JsonPropertyName("protocol")] int? Protocol,
    [property: JsonPropertyName("device")] string? Device)
{
    /// <summary><c>SillProtocol.current</c>.</summary>
    public const int CurrentProtocol = 1;
}

/// <summary>Kind 22: why the Mac is about to close the session. Mirrors <c>Goodbye</c> in Remote.swift.</summary>
public sealed record Goodbye(
    [property: JsonPropertyName("reason")] string Reason,
    [property: JsonPropertyName("message")] string? Message = null,
    [property: JsonPropertyName("minimumVersion")] string? MinimumVersion = null,
    [property: JsonPropertyName("reconnect")] bool? Reconnect = null);

/// <summary>One Mac window as the switcher shows it. Mirrors <c>WindowInfo</c> in Switcher.swift.</summary>
public sealed record WindowInfo(
    [property: JsonPropertyName("id")] uint Id,
    [property: JsonPropertyName("title")] string? Title,
    [property: JsonPropertyName("appName")] string? AppName,
    [property: JsonPropertyName("bundleID")] string? BundleId,
    [property: JsonPropertyName("width")] int Width,
    [property: JsonPropertyName("height")] int Height);

/// <summary>An installed app (kind 5 is a list of them). Mirrors <c>AppInfo</c>.</summary>
public sealed record AppInfo(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("bundleID")] string BundleId);

/// <summary>The parts of kind 2 the client reads. Mirrors <c>WindowList</c> in Switcher.swift
/// (the rest of its fields are skipped).</summary>
public sealed record WindowList(
    [property: JsonPropertyName("macName")] string MacName,
    [property: JsonPropertyName("windows")] IReadOnlyList<WindowInfo> Windows,
    [property: JsonPropertyName("active")] JsonElement Active,
    [property: JsonPropertyName("hostVersion")] string? HostVersion = null,
    [property: JsonPropertyName("protocol")] int? Protocol = null,
    [property: JsonPropertyName("gestures")] int? Gestures = null,
    [property: JsonPropertyName("clipboard")] int? Clipboard = null)
{
    /// <summary>The streamed window's id, null for the Desktop or nothing.</summary>
    public uint? ActiveWindowId => Active.ValueKind == JsonValueKind.Object && Active.TryGetProperty("window", out var w)
        && w.ValueKind == JsonValueKind.Object && w.TryGetProperty("_0", out var id) && id.TryGetUInt32(out uint v) ? v : null;

    /// <summary>"none", "desktop" or "window 1234": <c>StreamSource</c>'s synthesized JSON is an
    /// object with one key, the case.</summary>
    public string ActiveName => Active.ValueKind == JsonValueKind.Object && Active.EnumerateObject().FirstOrDefault() is var p && p.Name is { } n
        ? n == "window" && p.Value.ValueKind == JsonValueKind.Object && p.Value.TryGetProperty("_0", out var id) ? $"window {id}" : n
        : "?";
}

/// <summary>The session's outgoing payloads, as the Swift types encode them.</summary>
public static class SessionMessages
{
    internal static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    public static byte[] Hello(Hello hello) =>
        StreamHeader.Serialize(SessionKinds.Hello, 0, false, JsonSerializer.SerializeToUtf8Bytes(hello, Json));

    /// <summary>Kind 6 for the Desktop: Swift's synthesized <c>StreamSource.desktop</c>.</summary>
    public static byte[] SelectDesktop() => StreamHeader.Serialize(SessionKinds.SelectSource, 0, false, """{"desktop":{}}"""u8);

    /// <summary>Kind 6 for one window: <c>{"window":{"_0":id}}</c>.</summary>
    public static byte[] SelectWindow(uint id) =>
        StreamHeader.Serialize(SessionKinds.SelectSource, 0, false, Encoding.UTF8.GetBytes("{\"window\":{\"_0\":" + id + "}}"));

    /// <summary>Kind 7: open an installed app; the host streams its first window.</summary>
    public static byte[] LaunchApp(string bundleId) =>
        StreamHeader.Serialize(SessionKinds.LaunchApp, 0, false, JsonSerializer.SerializeToUtf8Bytes(new { bundleID = bundleId }));

    /// <summary>Kind 15: a window's traffic light, "close", "minimize" or "fullScreen".</summary>
    public static byte[] WindowCommand(uint id, string action) =>
        StreamHeader.Serialize(SessionKinds.WindowCommand, 0, false, JsonSerializer.SerializeToUtf8Bytes(new { id, action }));

    /// <summary>Kind 28: a trackpad gesture by name (<see cref="Gestures"/>), which the host turns
    /// into the Mac's own shortcut. Only to a host whose window list says <c>gestures</c> 1 or more.</summary>
    public static byte[] Gesture(string name, int fingers = 3) =>
        StreamHeader.Serialize(SessionKinds.Gesture, 0, false, JsonSerializer.SerializeToUtf8Bytes(new { gesture = name, fingers }));

    /// <summary>Kind 10: the sender's clock, a big-endian Double, echoed back as kind 11.</summary>
    public static byte[] Ping(double seconds)
    {
        var payload = new byte[8];
        BinaryPrimitives.WriteUInt64BigEndian(payload, BitConverter.DoubleToUInt64Bits(seconds));
        return StreamHeader.Serialize(SessionKinds.Ping, 0, false, payload);
    }

    public static double PongTime(ReadOnlySpan<byte> payload) =>
        payload.Length == 8 ? BitConverter.UInt64BitsToDouble(BinaryPrimitives.ReadUInt64BigEndian(payload)) : double.NaN;

    public static T? Decode<T>(ReadOnlySpan<byte> payload) where T : class
    {
        try { return JsonSerializer.Deserialize<T>(payload, Json); } catch (JsonException) { return null; }
    }
}

/// <summary>
/// Kind 0: the HEVC parameter sets, <c>nalLen(1) count(1)</c> then per set <c>length(UInt16 BE)
/// bytes</c>. Mirrors <c>ParameterSets</c> in StreamMessage.swift.
/// </summary>
public sealed record ParameterSets(int NalUnitHeaderLength, IReadOnlyList<byte[]> Sets)
{
    /// <summary>Null for a payload that ends inside a set or announces one it lacks.</summary>
    public static ParameterSets? Parse(ReadOnlySpan<byte> d)
    {
        if (d.Length < 2) return null;
        int nalLen = d[0], count = d[1], offset = 2;
        var sets = new List<byte[]>(count);
        for (int i = 0; i < count; i++)
        {
            if (d.Length < offset + 2) return null;
            int len = BinaryPrimitives.ReadUInt16BigEndian(d[offset..]);
            offset += 2;
            if (d.Length < offset + len) return null;
            sets.Add(d.Slice(offset, len).ToArray());
            offset += len;
        }
        return new ParameterSets(nalLen, sets);
    }

    public byte[] Encode()
    {
        var bytes = new List<byte> { (byte)NalUnitHeaderLength, (byte)Sets.Count };
        foreach (var s in Sets) { bytes.Add((byte)(s.Length >> 8)); bytes.Add((byte)s.Length); bytes.AddRange(s); }
        return [.. bytes];
    }
}

/// <summary>Kind 1's payload: one HEVC access unit as length-prefixed NAL units (hvcC style),
/// each length <c>nalLen</c> bytes, big endian.</summary>
public static class AccessUnit
{
    /// <summary>Each NAL unit's offset and length in <paramref name="payload"/>, or null when a
    /// length runs past the end or the prefix is not 1 to 4 bytes.</summary>
    public static List<(int Offset, int Length)>? Nals(ReadOnlySpan<byte> payload, int nalLen)
    {
        if (nalLen is < 1 or > 4) return null;
        var nals = new List<(int, int)>();
        int at = 0;
        while (at < payload.Length)
        {
            if (payload.Length - at < nalLen) return null;
            long len = 0;
            for (int i = 0; i < nalLen; i++) len = (len << 8) | payload[at + i];
            at += nalLen;
            if (len > payload.Length - at) return null;
            nals.Add((at, (int)len));
            at += (int)len;
        }
        return nals;
    }

    /// <summary>The HEVC NAL unit type (ITU-T H.265 §7.3.1.2): bits 1–6 of the first byte.</summary>
    public static int NalType(ReadOnlySpan<byte> nal) => nal.Length == 0 ? -1 : (nal[0] >> 1) & 0x3F;

    /// <summary>"VPS", "IDR_W_RADL", "TRAIL_R"…, else the number.</summary>
    public static string NalName(int type) => type switch
    {
        0 => "TRAIL_N", 1 => "TRAIL_R", 19 => "IDR_W_RADL", 20 => "IDR_N_LP", 21 => "CRA",
        32 => "VPS", 33 => "SPS", 34 => "PPS", 35 => "AUD", 39 => "SEI", 40 => "SEI_SUFFIX",
        _ => type.ToString(),
    };
}

/// <summary>
/// A session connection (ALPN <c>sill/1</c>) to a paired Mac, pinned to the key saved at
/// pairing. Its first message is the hello, sent here before anything else can be.
/// </summary>
public sealed class SessionClient : IAsyncDisposable
{
    private readonly SslStream ssl;
    private readonly SemaphoreSlim writing = new(1, 1);

    private SessionClient(SslStream ssl) { this.ssl = ssl; }

    public static async Task<SessionClient> ConnectAsync(string host, int port, DeviceIdentity identity, byte[] macFingerprint,
        Hello hello, CancellationToken ct)
    {
        var (ssl, _) = await SillTls.ConnectAsync(host, port, SillTls.Session, identity, macFingerprint, ct).ConfigureAwait(false);
        var session = new SessionClient(ssl);
        try { await session.SendAsync(SessionMessages.Hello(hello), ct).ConfigureAwait(false); }
        catch { await session.DisposeAsync().ConfigureAwait(false); throw; }
        return session;
    }

    /// <summary>One whole message (header and payload); safe from several tasks at once.</summary>
    public async Task SendAsync(byte[] message, CancellationToken ct)
    {
        await writing.WaitAsync(ct).ConfigureAwait(false);
        try { await ssl.WriteAsync(message, ct).ConfigureAwait(false); await ssl.FlushAsync(ct).ConfigureAwait(false); }
        finally { writing.Release(); }
    }

    /// <summary>The next message, or null when the Mac ends the connection cleanly. Every kind is
    /// returned, those this build does not know included, for the caller to skip.</summary>
    public Task<(StreamHeader Header, byte[] Payload)?> ReadAsync(CancellationToken ct) =>
        MessageStream.ReadAsync(ssl, SessionKinds.MaxPayload, ct);

    public async ValueTask DisposeAsync()
    {
        await ssl.DisposeAsync().ConfigureAwait(false);
        writing.Dispose();
    }
}

/// <summary>Kind 28's names (Gesture.swift) and what the Mac does with each (GestureChords.swift).</summary>
public static class Gestures
{
    public const string MissionControl = "swipeUp", AppExpose = "swipeDown",
        SpaceRight = "swipeLeft", SpaceLeft = "swipeRight", Apps = "pinch", ShowDesktop = "spread";
}

/// <summary>Kinds 3 and 4: an image after a key. Mirrors <c>ImageBlob</c> in Switcher.swift.</summary>
public static class ImageBlobs
{
    /// <summary>Kind 3: windowID (4 bytes, big endian), then a JPEG.</summary>
    public static (uint WindowId, byte[] Jpeg)? Thumbnail(ReadOnlySpan<byte> d) =>
        d.Length > 4 ? (BinaryPrimitives.ReadUInt32BigEndian(d), d[4..].ToArray()) : null;

    /// <summary>Kind 4: the bundle ID's length (2 bytes, big endian), the ID in UTF-8, then a PNG.</summary>
    public static (string BundleId, byte[] Png)? Icon(ReadOnlySpan<byte> d)
    {
        if (d.Length <= 2) return null;
        int len = BinaryPrimitives.ReadUInt16BigEndian(d);
        if (d.Length <= 2 + len) return null;
        return (Encoding.UTF8.GetString(d.Slice(2, len)), d[(2 + len)..].ToArray());
    }

    /// <summary>Kind 14, the Mac's cursor (Viewport.swift's <c>CursorShapeBlob</c>): its hotspot
    /// and size in Mac points, four Float32 big endian, then a PNG (usually at 2×). Null for a
    /// blob too short, or a size that is not a positive, finite number.</summary>
    public static (float HotX, float HotY, float Width, float Height, byte[] Png)? Cursor(ReadOnlySpan<byte> d)
    {
        if (d.Length <= 16) return null;
        float hx = BinaryPrimitives.ReadSingleBigEndian(d), hy = BinaryPrimitives.ReadSingleBigEndian(d[4..]),
            w = BinaryPrimitives.ReadSingleBigEndian(d[8..]), h = BinaryPrimitives.ReadSingleBigEndian(d[12..]);
        if (!(w > 0 && h > 0 && float.IsFinite(w) && float.IsFinite(h) && float.IsFinite(hx) && float.IsFinite(hy))) return null;
        return (hx, hy, w, h, d[16..].ToArray());
    }
}
