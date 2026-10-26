namespace Sill.Protocol;

/// <summary>
/// The automatic reconnect after a session with a saved Mac ended by itself (DiscoveryPolicy.swift's
/// <c>redialRow</c> and <c>reconnectLine</c>, issue #69). Each dial is the whole of
/// <see cref="RemoteDialPolicy.Plan"/>: the Mac's row on this network if it is listed, then its
/// saved addresses. Pure.
/// </summary>
public static class ReconnectPolicy
{
    /// <summary>The waits between dials that did not connect, from the last dial's start: 5, 10, 20, then 30 s.</summary>
    public static readonly double[] Retry = [5, 10, 20, 30];
    /// <summary>After this many, the line says the Mac may be asleep (about 20 s after the loss).</summary>
    public const int QuietAfter = 3;
    /// <summary>After this many the dials stop (about 4.6 minutes); a click, or the Mac's row
    /// listed afresh, starts again.</summary>
    public const int Dials = 12;

    /// <summary>Whether to dial now after <paramref name="failed"/> dials that did not connect, the
    /// last started at <paramref name="lastDialAt"/> (seconds), or when to look again: the first at
    /// once, each next <see cref="Retry"/> after the last started, none after <see cref="Dials"/>.</summary>
    public static (bool Dial, double? RecheckAt) Redial(int failed, double? lastDialAt, double now)
    {
        if (failed >= Dials) return (false, null);
        if (failed <= 0 || lastDialAt is not { } last) return (true, null);
        double due = last + Retry[Math.Min(failed, Retry.Length) - 1];
        return now >= due ? (true, null) : (false, due);
    }

    /// <summary>The status line while the reconnect dials (<paramref name="failed"/>: the dials that
    /// did not connect, one under way not counted), with "click" for "tap".</summary>
    public static string Line(string mac, int failed)
    {
        if (failed >= Dials) return $"Stopped trying to reach {mac}. Click it to try again.";
        if (failed >= QuietAfter) return $"{mac} isn’t answering. It may be asleep. Sill keeps trying, or click it to try now.";
        return $"Reconnecting to {mac}…";
    }
}

/// <summary>
/// What the window says, and whether this PC reconnects, when a session ends: with the Mac's
/// goodbye (kind 22) or without one (iOSClient/GoodbyePolicy.swift), with "click" for "tap" and
/// "this PC" for "this iPad". "update" and any reason this build doesn't know are notices: the
/// Mac's own words, and a reconnect only when it asks for one. Pure.
/// </summary>
public static class GoodbyePolicy
{
    public const string Quit = "quit", Removed = "removed", RemoteOff = "remoteOff", InternetOff = "internetOff", Busy = "busy",
        PairingRequired = "pairingRequired", Update = "update";

    /// <param name="Reconnect">This PC reconnects by itself.</param>
    /// <param name="IsNotice">The Mac's own words, shown as it wrote them.</param>
    public sealed record Outcome(string Text, bool Reconnect, bool IsNotice = false);

    public const int MessageLimit = 300;
    private static readonly HashSet<string> Known = [Quit, Removed, RemoteOff, InternetOff, Busy, PairingRequired];

    public static bool IsNotice(Goodbye goodbye) => !Known.Contains(goodbye.Reason ?? "");

    /// <summary>The session with <paramref name="mac"/> ended with <paramref name="goodbye"/> (null: none came).</summary>
    public static Outcome For(Goodbye? goodbye, string mac)
    {
        const string device = PairingCopy.Device;
        if (goodbye is null) return new($"{mac} disconnected. Sill will reconnect when it can reach it.", true);
        string? said = SafeText.Label(goodbye.Message ?? "", MessageLimit) is { Length: > 0 } m ? m : null;
        return goodbye.Reason switch
        {
            Quit => new($"{mac} quit Sill. This {device} reconnects when it’s back.", true),
            Removed => new($"{mac} removed this {device}. To use it again, pair it again.", false),
            // The remote door's ends: at home the row still reaches the Mac.
            RemoteOff => new($"{mac} turned off Remote Access.", true),
            InternetOff => new($"{mac} stopped accepting connections from the internet. Connect through your VPN.", true),
            Busy => new($"{mac} is already serving 8 devices.", true),
            PairingRequired => new($"{mac} now asks devices to pair. Click it to pair this {device}.", false),
            Update => new(said ?? $"Update Sill on this {device} to keep using {mac}."
                + (goodbye.MinimumVersion is { Length: > 0 } v ? $" It needs version {SafeText.Label(v, 20)} or later." : ""),
                goodbye.Reconnect == true, true),
            _ => new(said ?? (goodbye.Reconnect == true ? $"{mac} closed the connection. Sill will reconnect when it can."
                                                        : $"{mac} closed the connection. Click it to try again."),
                goodbye.Reconnect == true, true),
        };
    }
}

/// <summary>The connect screen's Remote rows (DiscoveryPolicy.swift's <c>remoteRows</c>). Pure.</summary>
public static class RemoteRows
{
    /// <summary>A saved Mac this network doesn't list shows as a Remote row once the network has had this long.</summary>
    public const double NetworkFirst = 3.0;

    /// <summary>Saved Macs that no row lists, oldest pairing first, once the browse has run
    /// <see cref="NetworkFirst"/> seconds. A Mac marked with a new key has none: its key is gone,
    /// and its row on this network pairs it again.</summary>
    public static IReadOnlyList<MacRow> Build(IReadOnlyList<SavedMac> saved, IReadOnlyList<MacRow> listed, double browsing)
    {
        if (browsing < NetworkFirst) return [];
        var here = listed.Select(r => r.MacId).OfType<string>().ToHashSet();
        return saved.Where(m => m.NewKey != true && !here.Contains(m.MacId))
            .OrderBy(m => m.PairedAt)
            .Select(MacRow.Remote)
            .ToList();
    }
}

/// <summary>
/// The dial a start makes by itself (no <c>--host</c>): the saved Mac this PC connected to last,
/// clicked as its row would be once the connect screen lists it, its row on this network or, after
/// <see cref="RemoteRows.NetworkFirst"/>, its Remote row. One dial: if it doesn't connect, the
/// connect screen stays with its words, and no reconnect follows. Pure.
/// </summary>
public static class LaunchDial
{
    /// <summary>The Mac to dial: the one with the newest <see cref="SavedMac.LastConnectedAt"/>, never
    /// one marked with a new key (its row pairs it again) or one never connected to.</summary>
    public static SavedMac? Mac(IReadOnlyList<SavedMac> saved) =>
        saved.Where(m => m.NewKey != true && m.LastConnectedAt is not null).MaxBy(m => m.LastConnectedAt);

    /// <summary>The row to click for <paramref name="macId"/>: its paired row on this network, or its
    /// Remote row; null while there is none yet.</summary>
    public static MacRow? Row(string macId, IReadOnlyList<MacRow> rows) =>
        rows.FirstOrDefault(r => r.MacId == macId && r.State == MacRow.Kind.Paired)
        ?? rows.FirstOrDefault(r => r.MacId == macId && r.State == MacRow.Kind.Remote);

    /// <summary>Whether to stop waiting for a row: the browse has had a second past the Remote rows'
    /// <see cref="RemoteRows.NetworkFirst"/> and the Mac is still listed some other way (Update
    /// Sill, say), so a click is the person's to make.</summary>
    public static bool GivesUp(string macId, IReadOnlyList<MacRow> rows, double browsing) =>
        browsing >= RemoteRows.NetworkFirst + 1 && Row(macId, rows) is null;
}
