using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>The Mac's streaming settings as kind 16 reports them (HostSettings.swift's
/// <c>StreamSettings</c>). <see cref="DirectWireless"/> is null from a host without it.</summary>
public sealed record StreamSettings(
    [property: JsonPropertyName("maxFPS")] int MaxFps,
    [property: JsonPropertyName("bitrate")] int Bitrate,
    [property: JsonPropertyName("captureScale")] double CaptureScale,
    [property: JsonPropertyName("prioritizeSpeed")] bool PrioritizeSpeed,
    [property: JsonPropertyName("virtualDisplay")] bool VirtualDisplay,
    [property: JsonPropertyName("directWireless")] bool? DirectWireless);

/// <summary>What streams now (<c>RunningStream</c>), for the panel's readout.</summary>
public sealed record RunningStream(
    [property: JsonPropertyName("width")] int Width,
    [property: JsonPropertyName("height")] int Height,
    [property: JsonPropertyName("fps")] int Fps,
    [property: JsonPropertyName("mbps")] int Mbps,
    [property: JsonPropertyName("onVirtualDisplay")] bool OnVirtualDisplay);

/// <summary>Away from home (<c>AwayQuality</c>): which quality this connection runs.</summary>
public sealed record AwayQuality(
    [property: JsonPropertyName("homeBitrate")] int HomeBitrate,
    [property: JsonPropertyName("homeCaptureScale")] double HomeCaptureScale,
    [property: JsonPropertyName("awayBitrate")] int AwayBitrate,
    [property: JsonPropertyName("awayCaptureScale")] double AwayCaptureScale,
    [property: JsonPropertyName("thisConnectionAway")] bool ThisConnectionAway,
    [property: JsonPropertyName("awayRunning")] bool AwayRunning);

/// <summary>Kind 16 (<c>HostSettingsState</c>): the Mac's settings, on connect, whenever they
/// change, and with <see cref="Answering"/> as the answer to one of this device's changes.</summary>
public sealed record HostSettingsState(
    [property: JsonPropertyName("settings")] StreamSettings Settings,
    [property: JsonPropertyName("persistent")] bool Persistent,
    [property: JsonPropertyName("virtualDisplayAvailable")] bool VirtualDisplayAvailable,
    [property: JsonPropertyName("virtualDisplayNote")] string? VirtualDisplayNote,
    [property: JsonPropertyName("softwareEncoder")] bool SoftwareEncoder,
    [property: JsonPropertyName("stream")] RunningStream? Stream,
    [property: JsonPropertyName("answering")] int? Answering,
    [property: JsonPropertyName("away")] AwayQuality? Away);

/// <summary>Kind 17 (<c>HostSettingsChange</c>): only the fields one control changed, as absolute
/// values, and a token the Mac's answer carries back. Null fields are left out of the JSON.</summary>
public sealed record HostSettingsChange(
    [property: JsonPropertyName("token")] int? Token = null,
    [property: JsonPropertyName("maxFPS")] int? MaxFps = null,
    [property: JsonPropertyName("bitrate")] int? Bitrate = null,
    [property: JsonPropertyName("captureScale")] double? CaptureScale = null,
    [property: JsonPropertyName("prioritizeSpeed")] bool? PrioritizeSpeed = null,
    [property: JsonPropertyName("virtualDisplay")] bool? VirtualDisplay = null,
    [property: JsonPropertyName("directWireless")] bool? DirectWireless = null)
{
    [JsonIgnore]
    public bool IsEmpty => MaxFps is null && Bitrate is null && CaptureScale is null && PrioritizeSpeed is null
                           && VirtualDisplay is null && DirectWireless is null;

    /// <summary><paramref name="s"/> with this change laid over it.</summary>
    public StreamSettings AppliedTo(StreamSettings s) => s with
    {
        MaxFps = MaxFps ?? s.MaxFps, Bitrate = Bitrate ?? s.Bitrate, CaptureScale = CaptureScale ?? s.CaptureScale,
        PrioritizeSpeed = PrioritizeSpeed ?? s.PrioritizeSpeed, VirtualDisplay = VirtualDisplay ?? s.VirtualDisplay,
        DirectWireless = DirectWireless ?? s.DirectWireless,
    };

    public byte[] Encode() => StreamHeader.Serialize(HostSettingsKinds.ChangeSettings, 0, false, JsonSerializer.SerializeToUtf8Bytes(this, SessionMessages.Json));
}

public static class HostSettingsKinds
{
    public const byte HostSettings = 16, ChangeSettings = 17;
}

/// <summary>What a device may pick (<c>SettingsChoices</c>, the Mac menu's own), and the quality
/// presets (<c>QualityPreset</c>): bitrates per 60 fps.</summary>
public static class SettingsChoices
{
    public static readonly int[] MaxFps = [60, 120];
    public static readonly double[] CaptureScale = [2, 1];
    public static readonly (string Name, int Bitrate)[] Presets =
    [
        ("Low", 4_000_000), ("Efficient", 8_000_000), ("Balanced", 15_000_000), ("High", 25_000_000),
        ("Pro", 40_000_000), ("Ultra", 80_000_000), ("Extreme", 150_000_000),
    ];

    /// <summary>"Balanced — 15 Mbps", or "Custom — 12 Mbps" for a bitrate set by hand.</summary>
    public static string QualityTitle(int bitrate) =>
        (Presets.FirstOrDefault(p => p.Bitrate == bitrate).Name ?? "Custom") + " — " + Mbps(bitrate) + " Mbps";

    public static string Mbps(int bps) =>
        bps % 1_000_000 == 0 ? (bps / 1_000_000).ToString(CultureInfo.InvariantCulture)
                             : (bps / 1_000_000.0).ToString("0.0", CultureInfo.InvariantCulture);

    /// <summary>The sentence under Quality on both ends.</summary>
    public const string FastLinkNote = "Ultra and Extreme need the USB cable or very fast Wi‑Fi; if the picture lags, step down.";
}

/// <summary>
/// The Mac's settings as this device shows them: the Mac's last state on this connection with this
/// device's unanswered picks laid over it (iOSClient/HostSettingsLedger.swift, the same rules).
/// A pick sends only the fields that change what is shown, and nothing before the first state; an
/// answer clears only the picks that carried its token, and a pick the answer does not hold was
/// refused (it goes back); a pick unanswered past the timeout goes back too. Pure; one thread.
/// </summary>
public sealed class SettingsLedger
{
    public enum Field { MaxFps, Bitrate, CaptureScale, PrioritizeSpeed, VirtualDisplay, DirectWireless }

    private sealed record Entry(HostSettingsChange Change, int Token, double SentAt);
    private readonly Dictionary<Field, Entry> pending = [];

    public HostSettingsState? Host { get; private set; }

    /// <summary>What to show: the Mac's settings with this device's picks over them; null before the first state.</summary>
    public StreamSettings? Displayed =>
        Host is null ? null : pending.Values.Aggregate(Host.Settings, (s, e) => e.Change.AppliedTo(s));

    public bool IsPending(Field f) => pending.ContainsKey(f);

    /// <summary>A control's pick; the change to send (with <paramref name="token"/>), or null when it changes nothing shown.</summary>
    public HostSettingsChange? Pick(HostSettingsChange change, int token, double now)
    {
        if (Displayed is not { } shown) return null;
        var output = new HostSettingsChange(Token: token);
        foreach (var (field, single) in Fields(change))
        {
            if (field == Field.DirectWireless && shown.DirectWireless is null) continue;   // a host without it
            if (single.AppliedTo(shown) == shown) continue;
            pending[field] = new Entry(single, token, now);
            output = Add(output, single);
        }
        return output.IsEmpty ? null : output;
    }

    /// <summary>A state from the Mac; the fields of this device's picks that it refused.</summary>
    public IReadOnlySet<Field> Receive(HostSettingsState state)
    {
        Host = state with { Answering = null };
        var refused = new HashSet<Field>();
        if (state.Answering is not { } token) return refused;
        foreach (var (field, entry) in pending.Where(p => p.Value.Token == token).ToList())
        {
            pending.Remove(field);
            if (entry.Change.AppliedTo(state.Settings) != state.Settings) refused.Add(field);
        }
        return refused;
    }

    /// <summary>Drops picks unanswered for longer than <paramref name="timeout"/>; true if any went.</summary>
    public bool Expire(double now, double timeout)
    {
        var late = pending.Where(p => now - p.Value.SentAt > timeout).Select(p => p.Key).ToList();
        foreach (var f in late) pending.Remove(f);
        return late.Count > 0;
    }

    public void Reset() { Host = null; pending.Clear(); }

    private static IEnumerable<(Field, HostSettingsChange)> Fields(HostSettingsChange c)
    {
        if (c.MaxFps is { } a) yield return (Field.MaxFps, new HostSettingsChange(MaxFps: a));
        if (c.Bitrate is { } b) yield return (Field.Bitrate, new HostSettingsChange(Bitrate: b));
        if (c.CaptureScale is { } s) yield return (Field.CaptureScale, new HostSettingsChange(CaptureScale: s));
        if (c.PrioritizeSpeed is { } p) yield return (Field.PrioritizeSpeed, new HostSettingsChange(PrioritizeSpeed: p));
        if (c.VirtualDisplay is { } v) yield return (Field.VirtualDisplay, new HostSettingsChange(VirtualDisplay: v));
        if (c.DirectWireless is { } d) yield return (Field.DirectWireless, new HostSettingsChange(DirectWireless: d));
    }

    private static HostSettingsChange Add(HostSettingsChange to, HostSettingsChange more) => to with
    {
        MaxFps = more.MaxFps ?? to.MaxFps, Bitrate = more.Bitrate ?? to.Bitrate, CaptureScale = more.CaptureScale ?? to.CaptureScale,
        PrioritizeSpeed = more.PrioritizeSpeed ?? to.PrioritizeSpeed, VirtualDisplay = more.VirtualDisplay ?? to.VirtualDisplay,
        DirectWireless = more.DirectWireless ?? to.DirectWireless,
    };
}
