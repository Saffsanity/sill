using System.Reflection;

namespace Sill.Protocol;

/// <summary>
/// A Sill version as tags, bundles and the wire write it ("v0.4.0", "0.4", "0.3.0 (85)"): an
/// optional "v", then the digits-and-dots prefix, compared part by part ("0.10" is newer than
/// "0.9"), trailing zeros dropped ("0.4" equals "0.4.0"). Mirrors <c>SillVersion</c> in
/// Compatibility.swift. Pure.
/// </summary>
public sealed class SillVersion : IComparable<SillVersion>, IEquatable<SillVersion>
{
    /// <summary>The parts, trailing zeros dropped; empty is 0.</summary>
    public IReadOnlyList<int> Components { get; }

    public SillVersion(IEnumerable<int> components)
    {
        var c = components.ToList();
        while (c.Count > 0 && c[^1] == 0) c.RemoveAt(c.Count - 1);
        Components = c;
    }

    /// <summary>The version in <paramref name="text"/>, or null when it has none.</summary>
    public static SillVersion? Parse(string? text)
    {
        if (text is null) return null;
        var s = text.Trim();
        if (s.Length > 0 && (s[0] == 'v' || s[0] == 'V')) s = s[1..];
        int end = 0;
        while (end < s.Length && (s[end] is >= '0' and <= '9' || s[end] == '.')) end++;
        var prefix = s[..end].TrimEnd('.');
        if (prefix.Length == 0 || prefix[0] is < '0' or > '9') return null;
        var parts = prefix.Split('.');
        if (parts.Length > 8) return null;
        var numbers = new List<int>();
        foreach (var part in parts)
        {
            if (part.Length is < 1 or > 9 || !int.TryParse(part, out int n)) return null;
            numbers.Add(n);
        }
        return new SillVersion(numbers);
    }

    /// <summary>"0.4", "0.4.1": at least two parts.</summary>
    public override string ToString()
    {
        var c = Components.ToList();
        while (c.Count < 2) c.Add(0);
        return string.Join('.', c);
    }

    public int CompareTo(SillVersion? other)
    {
        if (other is null) return 1;
        for (int i = 0; i < Math.Max(Components.Count, other.Components.Count); i++)
        {
            int x = i < Components.Count ? Components[i] : 0, y = i < other.Components.Count ? other.Components[i] : 0;
            if (x != y) return x.CompareTo(y);
        }
        return 0;
    }

    public bool Equals(SillVersion? other) => other is not null && CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is SillVersion v && Equals(v);
    public override int GetHashCode() => string.Join('.', Components).GetHashCode();
    public static bool operator >(SillVersion a, SillVersion b) => a.CompareTo(b) > 0;
    public static bool operator <(SillVersion a, SillVersion b) => a.CompareTo(b) < 0;
    public static bool operator >=(SillVersion a, SillVersion b) => a.CompareTo(b) >= 0;
    public static bool operator <=(SillVersion a, SillVersion b) => a.CompareTo(b) <= 0;
    public static bool operator ==(SillVersion? a, SillVersion? b) => a is null ? b is null : a.Equals(b);
    public static bool operator !=(SillVersion? a, SillVersion? b) => !(a == b);
}

/// <summary>This build's version: Directory.Build.props' <c>Version</c> (the release workflow sets it
/// from the tag), as the entry assembly's informational version without its "+commit" suffix.</summary>
public static class AppVersion
{
    /// <summary>"0.5.1", or null for a process with no entry assembly.</summary>
    public static string? Current { get; } = Read(Assembly.GetEntryAssembly());

    public static string? Read(Assembly? assembly)
    {
        var text = assembly?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? assembly?.GetName().Version?.ToString(3);
        if (text is null) return null;
        int plus = text.IndexOf('+');
        return plus >= 0 ? text[..plus] : text;
    }
}
