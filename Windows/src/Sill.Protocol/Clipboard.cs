using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>
/// Kind 32, both ways: the clipboard. Mirrors <c>Clipboard</c> in Clipboard.swift. From this PC:
/// any kind 32 subscribes the connection to the Mac's copies (<c>{}</c> is text alone), <c>text</c>
/// also becomes the Mac's clipboard, <c>stop</c> ends the subscription. From the Mac: <c>text</c>
/// copied there, or sent by another device. <c>image</c> is reserved for a later generation (base64,
/// as Swift writes <c>Data</c>); this PC sends none. Null fields are left out.
/// </summary>
public sealed record Clipboard(
    [property: JsonPropertyName("text")] string? Text = null,
    [property: JsonPropertyName("image")] byte[]? Image = null,
    [property: JsonPropertyName("stop")] bool? Stop = null)
{
    /// <summary>The most text either way: 256 KB of UTF-8.</summary>
    public const int MaxTextBytes = 256 * 1024;
}

/// <summary>
/// The clipboard's rules for this PC, ported from ClipboardPolicy.swift's device side (the
/// subscription, the stop, what from the Mac is written, what is sent), with Windows' own markers
/// in place of the Mac's pasteboard types. Pure.
/// </summary>
public static class ClipboardPolicy
{
    public const byte Kind = 32;
    /// <summary><c>WindowList.clipboard</c> from a Mac that takes and sends text.</summary>
    public const int Generation = 1;
    /// <summary>The most a kind 32's JSON may be, either way: the Mac's cap on a device's message.</summary>
    public const int MaxPayload = StreamHeader.MaxClientPayload;
    /// <summary>The Mac takes a device's subscriptions and texts at most 4 in any second, and drops the rest.</summary>
    public const int PerSecond = 4;

    // Swift's JSONEncoder writes non-ASCII as UTF-8, not \uXXXX: so does this, so text near the cap
    // fits the same 1 MiB as on the iPad (it escapes "/" as "\/", which this leaves; both read either).
    private static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static byte[] Encode(Clipboard c) => JsonSerializer.SerializeToUtf8Bytes(c, Json);

    public static Clipboard? Decode(ReadOnlySpan<byte> payload)
    {
        try { return JsonSerializer.Deserialize<Clipboard>(payload, Json); } catch (JsonException) { return null; }
    }

    /// <summary>A kind 32 whole (header and payload).</summary>
    public static byte[] Message(byte[] payload) => StreamHeader.Serialize(Kind, 0, false, payload);

    /// <summary>A subscription: <c>{}</c> (Swift's <c>subscription</c>).</summary>
    public static byte[] Subscribing => Encode(new Clipboard());
    /// <summary>The switch going off: <c>{"stop":true}</c>.</summary>
    public static byte[] Stopping => Encode(new Clipboard(Stop: true));

    /// <summary>A kind 32 that sets the Mac's clipboard to <paramref name="text"/>, or null when it is
    /// empty, over <see cref="Clipboard.MaxTextBytes"/>, or its JSON over <see cref="MaxPayload"/>.</summary>
    public static byte[]? Payload(string text)
    {
        if (text.Length == 0 || Encoding.UTF8.GetByteCount(text) > Clipboard.MaxTextBytes) return null;
        var data = Encode(new Clipboard(text));
        return data.Length <= MaxPayload ? data : null;
    }

    /// <summary>Whether the Mac's window list says it takes and sends the clipboard.</summary>
    public static bool HostTakes(int? hostClipboard) => (hostClipboard ?? 0) >= Generation;

    public enum Subscription { None, Subscribe, Stop }

    /// <summary>Subscribe while the Mac takes the clipboard, the switch is on and this connection has
    /// not; stop when it has and the switch went off. A Mac that stopped saying it forgot every
    /// subscription. What to send, and whether the connection is subscribed after it.</summary>
    public static (Subscription Send, bool Subscribed) DeviceSubscription(int? hostClipboard, bool switchOn, bool subscribed)
    {
        if (!HostTakes(hostClipboard)) return (Subscription.None, false);
        if (switchOn && !subscribed) return (Subscription.Subscribe, true);
        if (!switchOn && subscribed) return (Subscription.Stop, false);
        return (Subscription.None, subscribed);
    }

    /// <summary>What this PC sent last, Windows' clipboard sequence number with it, and when (seconds).</summary>
    public sealed record Sent(string Text, uint Sequence, double At = 0);

    /// <summary>A kind 32 from the Mac: the text to write to Windows' clipboard, or null. Only with the
    /// switch on, from a Mac that takes the clipboard, text not empty and within the cap, and never the
    /// text this PC sent while its clipboard still holds it (the Mac's echo).</summary>
    public static string? DeviceWrites(ReadOnlySpan<byte> payload, bool switchOn, int? hostClipboard, Sent? lastSent, uint sequence)
    {
        if (!switchOn || !HostTakes(hostClipboard) || Decode(payload) is not { Text: { Length: > 0 } text }
            || Encoding.UTF8.GetByteCount(text) > Clipboard.MaxTextBytes) return null;
        if (lastSent is not null && lastSent.Text == text && lastSent.Sequence == sequence) return null;
        return text;
    }

    // ---- Windows' clipboard ----

    /// <summary>Windows' registered formats that keep a copy private: present at all
    /// (<see cref="ExcludeFormat"/>), or a DWORD of 0 (the other two). Password managers set them
    /// (1Password, Bitwarden, KeePass), as Windows' own clipboard history and cloud clipboard honour.</summary>
    public const string ExcludeFormat = "ExcludeClipboardContentFromMonitorProcessing";
    public const string HistoryFormat = "CanIncludeInClipboardHistory";
    public const string CloudFormat = "CanUploadToCloudClipboard";

    public enum Skip { Own, Marked, NoText, Empty, TooLong, Repeat }

    /// <summary>A copy of the text just sent, this soon after it, is the same copy again: a WinForms
    /// or OLE copy puts it on the clipboard and then flushes it, two changes (found on the PC: one copy
    /// sent twice in the same millisecond).</summary>
    public const double RepeatWindow = 1.0;

    /// <summary>A change of Windows' clipboard: the kind 32 to send, or why not (one of the two is null). This viewer's own write
    /// first (its sequence number), then the markers, from the formats alone, so a password manager's
    /// text is never read; only then the text, and not the text just sent again (<see cref="RepeatWindow"/>).</summary>
    public static (byte[]? Send, Skip? Why) PcDecides(uint sequence, uint? ownSequence, bool excluded, uint? canIncludeInHistory,
        uint? canUploadToCloud, Func<string?> text, Sent? lastSent = null, double now = 0)
    {
        if (ownSequence == sequence) return (null, Skip.Own);
        if (excluded || canIncludeInHistory == 0 || canUploadToCloud == 0) return (null, Skip.Marked);
        if (text() is not { } t) return (null, Skip.NoText);
        if (t.Length == 0) return (null, Skip.Empty);
        if (lastSent is not null && lastSent.Text == t && now - lastSent.At < RepeatWindow) return (null, Skip.Repeat);
        return Payload(t) is { } data ? (data, null) : (null, Skip.TooLong);
    }
}

/// <summary>
/// What this PC sends of the clipboard, kept to the Mac's rate: a subscription or text at most
/// <see cref="ClipboardPolicy.PerSecond"/> in any <see cref="Window"/>, the rest held and coalesced
/// to the newest (a text also subscribes, so a held text is never replaced by a subscription). A
/// stop goes at once, past the rate (the Mac never limits it), and drops what is held. Pure; one thread.
/// </summary>
public sealed class ClipboardOutbox
{
    /// <summary>A little over the Mac's second, so sends spaced here still are there after the
    /// network bunches them up.</summary>
    public const double Window = 1.25;

    private readonly Queue<double> sent = new();
    private byte[]? held;
    private bool heldIsText;

    /// <summary>A payload to send at <paramref name="now"/>: it, if it may go now; else null and it waits.</summary>
    public byte[]? Offer(byte[] payload, bool isText, double now)
    {
        if (held is not null && heldIsText && !isText) return null;   // the held text subscribes too
        held = payload; heldIsText = isText;
        return Due(now);
    }

    /// <summary>What is held, if it may go now.</summary>
    public byte[]? Due(double now)
    {
        while (sent.Count > 0 && now - sent.Peek() >= Window) sent.Dequeue();
        if (held is null || sent.Count >= ClipboardPolicy.PerSecond) return null;
        var send = held;
        held = null;
        sent.Enqueue(now);
        return send;
    }

    /// <summary>When what is held may go, or null with nothing held.</summary>
    public double? NextAt => held is null ? null : sent.Count < ClipboardPolicy.PerSecond ? 0 : sent.Peek() + Window;

    /// <summary>A stop: drops what is held; the stop itself goes at once and counts for nothing.</summary>
    public void Stop() { held = null; }

    public void Reset() { held = null; sent.Clear(); }
}
