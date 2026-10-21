using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>
/// A Mac this PC paired with (iOSClient/SavedMacs.swift's <c>SavedMac</c>, the fields this client
/// uses): its key's SPKI SHA-256 (the pin), Mac ID, name, recognition key (all base64url), the
/// address and port the pairing reached, when it paired, the Bonjour name it was listed under, and
/// <see cref="NewKey"/>: another key answered as this Mac, so a click pairs it again. From its
/// signed kind 18 (<see cref="SavedMacs.Refreshed"/>): the Mac's own addresses for afar, in its
/// dial order, the remote door's port and the newest kind 18's time. <see cref="LastWorked"/> is
/// the saved address ("host|port") that last won a dial, dialed first next time, and
/// <see cref="LastConnectedAt"/> when a session last came up. The JSON names are the spike's
/// <c>mac.json</c>'s, so that file reads as one; every field after <see cref="PairedAt"/> is
/// optional, so a record written before it loads.
/// </summary>
public sealed record SavedMac(
    string Fingerprint,
    string MacId,
    string Name,
    string RecognitionKey,
    string Host,
    int Port,
    DateTimeOffset PairedAt,
    string? BonjourName = null,
    bool? NewKey = null,
    IReadOnlyList<MacAddress>? Addresses = null,
    int? RemotePort = null,
    double? InfoIssuedAt = null,
    string? LastWorked = null,
    DateTimeOffset? LastConnectedAt = null)
{
    [JsonIgnore] public byte[]? Pin => Base64Url.Decode(Fingerprint) is { Length: 32 } fp ? fp : null;

    /// <summary>Every saved address to dial: the Mac's own (kind 18), then the one the pairing
    /// reached (a typed or linked address; at home, the home door, whose port changes at each
    /// launch of Sill.app, so it is only a last try).</summary>
    [JsonIgnore] public IReadOnlyList<MacAddress> AllAddresses =>
        [.. Addresses ?? [], new MacAddress(Host, Port, RemoteDialPolicy.KindOfHost(Host), "")];

    /// <summary>What the connect screen needs to recognise its rows.</summary>
    [JsonIgnore] public KnownMac Known => new(MacId, Name, Base64Url.Decode(RecognitionKey) is { Length: 32 } rk ? rk : null, BonjourName, NewKey == true);
}

/// <summary>The saved Macs as a list, pure (SavedMacs.swift's rules this client uses).</summary>
public static class SavedMacs
{
    /// <summary>At most this many; the one used longest ago goes first.</summary>
    public const int Cap = 16;

    /// <summary><paramref name="mac"/> saved: a record of the same Mac ID replaced, the new one
    /// last (the newest). Over the cap, the one used longest ago (<c>LastConnectedAt ?? PairedAt</c>) goes.</summary>
    public static IReadOnlyList<SavedMac> Adding(SavedMac mac, IReadOnlyList<SavedMac> list)
    {
        var next = list.Where(m => m.MacId != mac.MacId).Append(mac).ToList();
        while (next.Count > Cap) next.Remove(next.MinBy(m => m.LastConnectedAt ?? m.PairedAt)!);
        return next;
    }

    /// <summary>Link-local and zone-scoped addresses work only on the network they came from, and
    /// loopback only on the Mac itself; none is saved (loopback only with
    /// <paramref name="allowLoopback"/>, for a test host reached through an SSH forward).</summary>
    public static bool Keepable(string host, bool allowLoopback)
    {
        string h = host.ToLowerInvariant();
        if (h.Length == 0 || h.Contains('%')) return false;
        if (h.StartsWith("169.254.") || h.StartsWith("fe8") || h.StartsWith("fe9") || h.StartsWith("fea") || h.StartsWith("feb")) return false;
        if (h.StartsWith("127.") || h == "::1" || h == "localhost") return allowLoopback;
        return true;
    }

    /// <summary>
    /// A verified kind 18 laid over <paramref name="mac"/> (<c>refreshed</c> in SavedMacs.swift):
    /// null unless the key that signed it is the pin, the Mac ID is the saved one and it is newer
    /// than the last taken. Refreshes the name, the remote door's port and the Mac's addresses; the
    /// address that last worked stays. An empty list, or one from a Mac with Remote Access off,
    /// leaves the saved addresses alone: the Mac sends none while off, and a PC that took that at
    /// home would have nothing to dial once away, after Remote Access came back on.
    /// </summary>
    public static SavedMac? Refreshed(SavedMac mac, MacInfo info, byte[] fingerprint, bool allowLoopback)
    {
        if (mac.Pin is not { } pin || !pin.AsSpan().SequenceEqual(fingerprint) || info.MacId != mac.MacId
            || info.IssuedAt <= (mac.InfoIssuedAt ?? 0)) return null;
        var next = mac with { InfoIssuedAt = info.IssuedAt };
        if (SafeText.Label(info.Name ?? "", SafeText.LabelLimit) is { Length: > 0 } name) next = next with { Name = name };
        if (info.RemotePort is >= 1 and <= 65535) next = next with { RemotePort = info.RemotePort };
        var addresses = info.Addresses.Where(a => a.Host is not null && Keepable(a.Host, allowLoopback)).ToList();
        if (info.RemoteAccess && addresses.Count > 0) next = next with { Addresses = addresses };
        return next;
    }

    /// <summary>
    /// A kind 18 received on a session with <paramref name="id"/>, a connection that showed
    /// <paramref name="connectionKey"/> in its handshake: the list with that Mac refreshed, or null
    /// when nothing changes. Only a signature that verifies, by the key the connection itself showed
    /// (DiscoveryPolicy's <c>macInfoNamesSession</c>: a Mac hands its kind 18 to every session, so
    /// another Mac can replay it), which is that saved Mac's pin, and newer than the last taken.
    /// </summary>
    public static IReadOnlyList<SavedMac>? Taking(SignedMacInfo signed, string id, byte[] connectionKey, IReadOnlyList<SavedMac> list,
        bool allowLoopback)
    {
        if (signed.Verified() is not { } v || !v.Fingerprint.AsSpan().SequenceEqual(connectionKey)) return null;
        var (info, fp) = v;
        int i = list.ToList().FindIndex(m => m.MacId == id);
        if (i < 0 || Refreshed(list[i], info, fp, allowLoopback) is not { } next) return null;
        return list.Select((m, j) => j == i ? next : m).ToList();
    }

    /// <summary>A session with <paramref name="id"/> came up: when, and the saved address that won
    /// (null for a row's address, whose port is the home door's of the moment).</summary>
    public static IReadOnlyList<SavedMac> Connected(string id, string? lastWorked, DateTimeOffset at, IReadOnlyList<SavedMac> list) =>
        list.Select(m => m.MacId == id ? m with { LastConnectedAt = at, LastWorked = lastWorked ?? m.LastWorked } : m).ToList();

    /// <summary><see cref="SavedMac.NewKey"/> set on <paramref name="id"/>; null when it isn't saved
    /// or already marked.</summary>
    public static IReadOnlyList<SavedMac>? MarkingNewKey(string id, IReadOnlyList<SavedMac> list) =>
        list.Any(m => m.MacId == id && m.NewKey != true) ? list.Select(m => m.MacId == id ? m with { NewKey = true } : m).ToList() : null;

    /// <summary>After a pairing that a click on a row of <paramref name="old"/>, marked
    /// <see cref="SavedMac.NewKey"/>, started: <paramref name="old"/> goes once <paramref name="new"/>
    /// (another Mac ID: the Mac's new key) is saved. Nothing changes when <paramref name="old"/>
    /// isn't marked, or is <paramref name="new"/> itself (the same key after all: Adding replaced it).</summary>
    public static IReadOnlyList<SavedMac> ReplacingNewKey(string old, string @new, IReadOnlyList<SavedMac> list) =>
        old != @new && list.Any(m => m.MacId == @new) && list.Any(m => m.MacId == old && m.NewKey == true)
            ? list.Where(m => m.MacId != old).ToList()
            : list;

    public static IReadOnlyList<SavedMac> Forgetting(string id, IReadOnlyList<SavedMac> list) => list.Where(m => m.MacId != id).ToList();

    /// <summary>The newest record, for a dial with no row (the spike's session, <c>--host</c>).</summary>
    public static SavedMac? Newest(IReadOnlyList<SavedMac> list) => list.Count == 0 ? null : list[^1];
}

/// <summary>Where the saved Macs live. One file today (<see cref="SavedMacsFile"/>); ticket 10c's
/// list of Macs with their kind 18 addresses can sit behind the same calls.</summary>
public interface ISavedMacs
{
    IReadOnlyList<SavedMac> Load();
    void Save(IReadOnlyList<SavedMac> macs);
}

public static class SavedMacsStore
{
    public static SavedMac? Find(this ISavedMacs store, string id) => store.Load().FirstOrDefault(m => m.MacId == id);

    /// <summary>A pairing's Mac saved; <paramref name="replaces"/>, the record a newKey re-pairing came from.</summary>
    public static void Add(this ISavedMacs store, SavedMac mac, string? replaces = null)
    {
        var next = SavedMacs.Adding(mac, store.Load());
        if (replaces is not null) next = SavedMacs.ReplacingNewKey(replaces, mac.MacId, next);
        store.Save(next);
    }

    public static void MarkNewKey(this ISavedMacs store, string id)
    {
        if (SavedMacs.MarkingNewKey(id, store.Load()) is { } next) store.Save(next);
    }

    public static void Forget(this ISavedMacs store, string id) => store.Save(SavedMacs.Forgetting(id, store.Load()));

    /// <summary>A session's kind 18 taken (<see cref="SavedMacs.Taking"/>); whether anything changed.</summary>
    public static bool TakeMacInfo(this ISavedMacs store, SignedMacInfo signed, string id, byte[] connectionKey, bool allowLoopback)
    {
        if (SavedMacs.Taking(signed, id, connectionKey, store.Load(), allowLoopback) is not { } next) return false;
        store.Save(next);
        return true;
    }

    public static void Connected(this ISavedMacs store, string id, string? lastWorked) =>
        store.Save(SavedMacs.Connected(id, lastWorked, DateTimeOffset.UtcNow, store.Load()));
}

/// <summary>
/// The saved Macs in <c>macs.json</c> beside the device's key: <c>{"Macs":[…]}</c>, each entry
/// shaped as the spike's <c>mac.json</c> was. The first load in a folder that has only
/// <c>mac.json</c> takes it in, writes <c>macs.json</c> and renames the old file
/// <c>mac.json.migrated</c>, so nothing reads it again. A file that doesn't parse reads as no Macs
/// (and is kept aside as <c>macs.json.bad</c> at the next save).
/// </summary>
public sealed class SavedMacsFile(string directory) : ISavedMacs
{
    public const string FileName = "macs.json", OldFileName = "mac.json";
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    private sealed record Book(List<SavedMac> Macs);

    private string PathOf(string name) => Path.Combine(directory, name);
    private bool unreadable;

    public IReadOnlyList<SavedMac> Load()
    {
        string path = PathOf(FileName);
        try
        {
            if (File.Exists(path))
            {
                unreadable = false;
                var book = JsonSerializer.Deserialize<Book>(File.ReadAllText(path), Json);
                return book?.Macs?.Where(Valid).ToList() ?? [];
            }
            string old = PathOf(OldFileName);
            if (!File.Exists(old)) return [];
            var mac = JsonSerializer.Deserialize<SavedMac>(File.ReadAllText(old), Json);
            IReadOnlyList<SavedMac> list = mac is not null && Valid(mac) ? [mac] : [];
            Save(list);
            File.Move(old, PathOf(OldFileName + ".migrated"), overwrite: true);
            return list;
        }
        catch (JsonException) { unreadable = File.Exists(path); return []; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
    }

    public void Save(IReadOnlyList<SavedMac> macs)
    {
        Directory.CreateDirectory(directory);
        string path = PathOf(FileName);
        if (unreadable && File.Exists(path)) { File.Move(path, PathOf(FileName + ".bad"), overwrite: true); unreadable = false; }
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(new Book([.. macs]), Json));
        File.Move(temp, path, overwrite: true);
    }

    private static bool Valid(SavedMac m) =>
        m.Pin is not null && MacId.IsWellFormed(m.MacId) && !string.IsNullOrEmpty(m.Name) && m.RecognitionKey is not null;
}

/// <summary>
/// This PC as the Mac sees it: the name it pairs and says hello under, editable in Settings › This
/// PC and kept in <c>pc.json</c> beside the device's key. Empty, or never set, is the computer's
/// name. The Mac keeps the name it was given at pairing (Settings › Devices renames it there).
/// </summary>
public sealed record ThisPc(string? Name)
{
    public const string FileName = "pc.json";

    /// <summary>The name to send: the saved one, else <paramref name="computer"/> (Environment.MachineName).</summary>
    public string NameOr(string computer) => Clean(Name) is { Length: > 0 } n ? n : Clean(computer) is { Length: > 0 } c ? c : "Windows PC";

    /// <summary>A name as the Mac would show it: one line, at most 64 characters (SafeText).</summary>
    public static string Clean(string? name) => SafeText.Label(name ?? "", SafeText.LabelLimit);

    public static ThisPc Load(string directory)
    {
        try { return JsonSerializer.Deserialize<ThisPc>(File.ReadAllText(Path.Combine(directory, FileName))) ?? new((string?)null); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new((string?)null); }
    }

    public void Save(string directory)
    {
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, FileName), JsonSerializer.Serialize(this with { Name = Clean(Name) is { Length: > 0 } n ? n : null }));
    }
}
