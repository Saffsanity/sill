namespace Sill.Protocol;

/// <summary>
/// The QR code's content, also a link pasted by hand:
/// <c>sill://pair?v=1&amp;m=&lt;macID&gt;&amp;k=&lt;fp&gt;&amp;s=&lt;secret&gt;&amp;n=&lt;name&gt;&amp;p=&lt;port&gt;&amp;a=&lt;address&gt;…</c>.
/// Mirrors <c>PairLink.parse</c> in Sources/StreamProtocol/Pairing.swift.
/// </summary>
/// <remarks>
/// The spike keeps each <c>a</c> as the text the link carried (decoded, non-empty), as
/// Scripts/sillclient.py does: it dials a typed address, and the Swift address parser's rules
/// are not ported. A link the Swift parser refuses for its addresses alone is taken here.
/// </remarks>
public sealed record PairLink(string MacId, byte[] Fingerprint, byte[] Secret, string Name, int Port, IReadOnlyList<string> Addresses)
{
    public const int MaxAddresses = 5;
    public const int NameLimit = 64;

    public enum Failure { None, NotALink, Version, Field, MacIdMismatch, Address }

    public static Failure Parse(string text, out PairLink? link, out string? field)
    {
        link = null; field = null;
        string s = text.Trim();
        const string scheme = "sill://pair";
        if (!s.StartsWith(scheme, StringComparison.OrdinalIgnoreCase)) return Failure.NotALink;
        string rest = s[scheme.Length..];
        int hash = rest.IndexOf('#');
        if (hash >= 0) rest = rest[..hash];
        if (rest.StartsWith('/')) rest = rest[1..];
        if (!rest.StartsWith('?')) return Failure.NotALink;

        var items = new List<(string Name, string? Value)>();
        foreach (string part in rest[1..].Split('&'))
        {
            if (part.Length == 0) continue;
            int eq = part.IndexOf('=');
            string key = Unescape(eq < 0 ? part : part[..eq]);
            items.Add((key, eq < 0 ? null : Unescape(part[(eq + 1)..])));
        }

        string? Single(string key)
        {
            var values = items.Where(i => i.Name == key).ToList();
            return values.Count == 1 && !string.IsNullOrEmpty(values[0].Value) ? values[0].Value : null;
        }

        if (Single("v") != "1") return Failure.Version;
        string? m = Single("m");
        if (m is null || !Sill.Protocol.MacId.IsWellFormed(m)) { field = "m"; return Failure.Field; }
        byte[]? fp = Single("k") is { } k ? Base64Url.Decode(k) : null;
        if (fp is not { Length: 32 }) { field = "k"; return Failure.Field; }
        byte[]? secret = Single("s") is { } sec ? Base64Url.Decode(sec) : null;
        if (secret is not { Length: 16 }) { field = "s"; return Failure.Field; }
        string? p = Single("p");
        if (p is null || p.Length > 5 || !p.All(char.IsAsciiDigit) || int.Parse(p) is < 1 or > 65535)
        { field = "p"; return Failure.Field; }
        if (m != Sill.Protocol.MacId.Make(fp)) return Failure.MacIdMismatch;

        var addresses = new List<string>();
        foreach (var item in items.Where(i => i.Name == "a"))
        {
            if (string.IsNullOrWhiteSpace(item.Value)) { field = "a"; return Failure.Address; }
            addresses.Add(item.Value);
        }
        string name = SafeText.Label(items.FirstOrDefault(i => i.Name == "n").Value ?? "", NameLimit);
        link = new PairLink(m, fp, secret, name.Length == 0 ? "Mac" : name, int.Parse(p),
                            addresses.Take(MaxAddresses).ToList());
        return Failure.None;
    }

    // URLComponents' queryItems: percent-decoding only, "+" stays "+".
    private static string Unescape(string s)
    {
        try { return Uri.UnescapeDataString(s); } catch (UriFormatException) { return s; }
    }
}
