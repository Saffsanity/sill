using System.Security.Cryptography;
using System.Text;

namespace Sill.Protocol;

/// <summary>
/// The Bonjour TXT record's recognition tag <c>r</c> (Sources/StreamProtocol/Pairing.swift's
/// <c>RecognitionTag</c>): <c>base64url(p ‖ HMAC-SHA256(recognitionKey, "sill-tag-v1" ‖ p)[0..&lt;6])</c>,
/// <c>p</c> six random bytes. Only a device holding the Mac's recognition key (from pairing) can
/// tell that a row is that Mac; anyone else sees noise that changes at every launch.
/// </summary>
public static class RecognitionTag
{
    public const string TxtKey = "r";
    private static readonly byte[] Label = Encoding.UTF8.GetBytes("sill-tag-v1");

    /// <summary>A tag for <paramref name="recognitionKey"/>; <paramref name="nonce"/> (6 bytes) is
    /// for the tests' vector, else a fresh random one.</summary>
    public static string Make(byte[] recognitionKey, byte[]? nonce = null)
    {
        var p = nonce is { Length: 6 } ? nonce : RandomNumberGenerator.GetBytes(6);
        return Base64Url.Encode([.. p, .. Mac(recognitionKey, p)]);
    }

    /// <summary>Whether <paramref name="tag"/> was made with <paramref name="recognitionKey"/>;
    /// constant time in the six compared bytes.</summary>
    public static bool Matches(string? tag, byte[] recognitionKey)
    {
        if (tag is null || Base64Url.Decode(tag) is not { Length: 12 } bytes) return false;
        return CryptographicOperations.FixedTimeEquals(Mac(recognitionKey, bytes.AsSpan(0, 6)), bytes.AsSpan(6, 6));
    }

    private static byte[] Mac(byte[] key, ReadOnlySpan<byte> nonce) =>
        HMACSHA256.HashData(key, (byte[])[.. Label, .. nonce])[..6];
}

/// <summary>
/// How a home door speaks, from its TXT record's <c>p</c> (Pairing.swift's <c>HomeDoorTXT</c>):
/// no <c>p</c>, a plain door (Sill from before pairing at home, which this client can't speak);
/// "0", TLS for any device; anything else, a key with no value included, TLS for paired devices.
/// </summary>
public static class HomeDoorTxt
{
    public const string Key = "p";

    public enum Door { Plain, PairingRequired, Open }

    /// <summary>The door a record's entries describe. A value of null is a key without one
    /// (a boolean attribute), which reads as "1". Keys are case-insensitive (RFC 6763 §6.4).</summary>
    public static Door Read(IReadOnlyDictionary<string, string?> txt)
    {
        if (!TryGet(txt, Key, out var value)) return Door.Plain;
        return value == "0" ? Door.Open : Door.PairingRequired;
    }

    internal static bool TryGet(IReadOnlyDictionary<string, string?> txt, string key, out string? value)
    {
        foreach (var (k, v) in txt)
            if (string.Equals(k, key, StringComparison.OrdinalIgnoreCase)) { value = v; return true; }
        value = null;
        return false;
    }
}

/// <summary>The link this PC sees a Mac on, from the interface the answer came in on: the iPad's
/// Wired and Wi‑Fi words (DiscoveryPolicy.swift's <c>Method</c>). Anything else says nothing.</summary>
public enum MacLink { Wired, WiFi }

/// <summary>One service the network browser found and resolved: its instance name (the Mac's
/// name as Bonjour gives it), host, port, addresses (IPv4 first), TXT entries and the link.</summary>
public sealed record FoundService(
    string ServiceType,
    string Name,
    string Host,
    int Port,
    IReadOnlyList<string> Addresses,
    IReadOnlyDictionary<string, string?> Txt,
    MacLink? Link)
{
    /// <summary>The row's identity while it is listed: one instance of one service type.</summary>
    public string Id => $"{Name}.{ServiceType}";
}

/// <summary>What this PC knows of a Mac it paired with, enough to recognise its row: its Mac ID,
/// its name, the recognition key from pairing (32 bytes; null for a record without one), and the
/// Bonjour name it was last reached under (for a row that carries no tag at all), and whether
/// another key answered as it since (<c>NewKey</c>: its rows pair again).</summary>
public sealed record KnownMac(string MacId, string Name, byte[]? RecognitionKey, string? BonjourName, bool NewKey = false);

/// <summary>A row of the connect screen. <c>MacId</c> is the saved Mac the row is: set for
/// <see cref="Kind.Paired"/>, and for a <see cref="Kind.NotPaired"/> row of a saved Mac another key
/// answered as (a Mac set up again), whose pairing replaces that record (<see cref="Replaces"/>).</summary>
public sealed record MacRow(FoundService Service, MacRow.Kind State, string? MacId, bool TagNamed)
{
    public enum Kind
    {
        /// <summary>A Mac this PC paired with on a TLS door: a click connects, pinned to its key.</summary>
        Paired,
        /// <summary>Not paired with this PC (or another key's Mac under a saved Mac's name, or a saved
        /// Mac with a new key): a click asks the Mac for its code.</summary>
        NotPaired,
        /// <summary>Not paired, and the Mac lets any device in (<c>p=0</c>). "Not paired" too, so it
        /// never reads like a paired Mac's row; a click pairs as well.</summary>
        OpenDoor,
        /// <summary>No <c>p</c>: the Mac's Sill is from before pairing at home. Nothing is dialed.</summary>
        UpdateSill,
        /// <summary>A saved Mac this network doesn't list (<see cref="RemoteRows"/>): a click dials
        /// its saved addresses, through a VPN or the internet.</summary>
        Remote,
    }

    /// <summary>A Remote row: no service, only the saved Mac.</summary>
    public static MacRow Remote(SavedMac mac) =>
        new(new FoundService("remote", mac.Name, "", 0, [], new Dictionary<string, string?>(), null), Kind.Remote, mac.MacId, false);

    public string Name => Service.Name;

    /// <summary>The row's identity while it is shown: its service's, or a Remote row's Mac ID.</summary>
    public string Key => State == Kind.Remote ? "remote:" + MacId : Service.Id;

    /// <summary>The saved record a pairing from this row replaces: a Mac set up again.</summary>
    public string? Replaces => State == Kind.NotPaired ? MacId : null;

    /// <summary>The word at the end of the row: Wired or Wi‑Fi for a paired Mac when the link says,
    /// "Not paired", "Update Sill", "Remote".</summary>
    public string? Word => State switch
    {
        Kind.Paired => Service.Link switch { MacLink.Wired => "Wired", MacLink.WiFi => "Wi‑Fi", _ => null },
        Kind.NotPaired or Kind.OpenDoor => "Not paired",
        Kind.Remote => "Remote",
        _ => "Update Sill",
    };

    /// <summary>The addresses to dial, as <c>host:port</c> (IPv6 in brackets), IPv4 first, then the
    /// host name when no address resolved.</summary>
    public IReadOnlyList<string> DialTargets()
    {
        var list = Service.Addresses.Select(a => a.Contains(':') ? $"[{a}]:{Service.Port}" : $"{a}:{Service.Port}").ToList();
        if (list.Count == 0 && Service.Host.Length > 0) list.Add($"{Service.Host.TrimEnd('.')}:{Service.Port}");
        return list;
    }
}

/// <summary>
/// The connect screen's rows from what the browser lists (DiscoveryPolicy.swift's <c>rowMac</c>
/// and <c>rowWord</c>, for a client that speaks only TLS). Pure.
/// </summary>
public static class ConnectRows
{
    /// <summary>The saved Mac a row is: the one whose recognition key made the row's tag; for a row
    /// that carries no tag at all, the saved Mac last reached under its Bonjour name (a Sill with an
    /// identity always advertises its tag, so this is only an older record's case). A row whose tag
    /// names no saved Mac is none, whatever its name: a Mac set up again, or a look-alike.</summary>
    public static (string MacId, bool TagNamed)? RowMac(FoundService service, IReadOnlyList<KnownMac> saved)
    {
        HomeDoorTxt.TryGet(service.Txt, RecognitionTag.TxtKey, out var tag);
        if (!string.IsNullOrEmpty(tag))
        {
            foreach (var mac in saved)
                if (mac.RecognitionKey is { Length: 32 } key && RecognitionTag.Matches(tag, key)) return (mac.MacId, true);
            return null;
        }
        var byName = saved.FirstOrDefault(m => (m.BonjourName ?? m.Name) == service.Name);
        return byName is null ? null : (byName.MacId, false);
    }

    public static MacRow Row(FoundService service, IReadOnlyList<KnownMac> saved)
    {
        var door = HomeDoorTxt.Read(service.Txt);
        // No `p`: this client dials no plain door (a Release iPad's rule), whoever the Mac is.
        if (door == HomeDoorTxt.Door.Plain) return new MacRow(service, MacRow.Kind.UpdateSill, null, false);
        var mac = RowMac(service, saved);
        // A saved Mac another key answered as: paired again with a click (an ask with any key), as
        // the iPad's homeDial does for SavedMac.newKey.
        if (mac is { } n && saved.Any(s => s.MacId == n.MacId && s.NewKey)) return new MacRow(service, MacRow.Kind.NotPaired, n.MacId, n.TagNamed);
        if (mac is { } m) return new MacRow(service, MacRow.Kind.Paired, m.MacId, m.TagNamed);
        return new MacRow(service, door == HomeDoorTxt.Door.Open ? MacRow.Kind.OpenDoor : MacRow.Kind.NotPaired, null, false);
    }

    /// <summary>Every listed service as a row: the paired Macs first, then by name.</summary>
    public static IReadOnlyList<MacRow> Build(IEnumerable<FoundService> services, IReadOnlyList<KnownMac> saved) =>
        services.Select(s => Row(s, saved))
            .OrderBy(r => r.State == MacRow.Kind.Paired ? 0 : 1)
            .ThenBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(r => r.Service.ServiceType, StringComparer.Ordinal)
            .ToList();

    /// <summary>The status line after a click on an "Update Sill" row (DiscoveryPolicy's <c>updateSillStatus</c>).</summary>
    public static string UpdateSillStatus(string mac) => $"{mac} runs an older Sill. Update Sill on the Mac to connect.";
}

/// <summary>DNS-SD names as the system gives them.</summary>
public static class DnsSdName
{
    /// <summary>The instance's own name from a full one (<c>Mac\.mini._sill._tcp.local</c>):
    /// what comes before <c>.serviceType.domain</c>, its escapes undone (<c>\.</c>, <c>\\</c>, and
    /// <c>\DDD</c> as UTF-8 bytes). Null when the full name is not of that type.</summary>
    public static string? Instance(string fullName, string serviceType)
    {
        string name = fullName.TrimEnd('.');
        int at = name.IndexOf("." + serviceType + ".", StringComparison.OrdinalIgnoreCase);
        if (at <= 0)
        {
            if (!name.EndsWith("." + serviceType, StringComparison.OrdinalIgnoreCase)) return null;
            at = name.Length - serviceType.Length - 1;
        }
        return Unescape(name[..at]);
    }

    public static string Unescape(string label)
    {
        if (!label.Contains('\\')) return label;
        var bytes = new List<byte>();
        var text = new StringBuilder();
        void Flush() { if (text.Length > 0) { bytes.AddRange(Encoding.UTF8.GetBytes(text.ToString())); text.Clear(); } }
        for (int i = 0; i < label.Length; i++)
        {
            if (label[i] != '\\' || i + 1 >= label.Length) { text.Append(label[i]); continue; }
            if (i + 3 < label.Length && char.IsAsciiDigit(label[i + 1]) && char.IsAsciiDigit(label[i + 2]) && char.IsAsciiDigit(label[i + 3])
                && int.Parse(label.AsSpan(i + 1, 3)) is var b and <= 255)
            {
                Flush();
                bytes.Add((byte)b);
                i += 3;
            }
            else text.Append(label[++i]);
        }
        Flush();
        return Encoding.UTF8.GetString([.. bytes]);
    }
}
