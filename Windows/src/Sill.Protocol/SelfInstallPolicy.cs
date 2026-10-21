namespace Sill.Protocol;

/// <summary>
/// Where Sill for Windows installs itself and what it offers at a start, as pure decisions (the
/// Viewer's SelfInstall does the copying, the shortcut and the dialog). Per user, no administrator:
/// <c>%LOCALAPPDATA%\Programs\Sill\Sill.exe</c>, with <c>Sill.lnk</c> in the user's Start menu
/// Programs folder. Paths are Windows paths compared as Windows does (case-insensitive, either
/// slash), so the rules are tested on any OS.
/// </summary>
public static class SelfInstallPolicy
{
    public const string ExeName = "Sill.exe";
    public const string ShortcutName = "Sill.lnk";

    /// <summary><c>%LOCALAPPDATA%\Programs\Sill</c>, the per-user programs folder Windows itself uses.</summary>
    public static string InstallDir(string localAppData) => Join(localAppData, "Programs", "Sill");
    public static string InstalledPath(string localAppData) => Join(InstallDir(localAppData), ExeName);
    /// <summary>The Start menu entry, in <paramref name="programs"/> (the user's Start Menu\Programs).</summary>
    public static string ShortcutPath(string programs) => Join(programs, ShortcutName);
    /// <summary><c>%LOCALAPPDATA%\Sill\install.json</c>: the copies whose offer was turned down for good.</summary>
    public static string StatePath(string localAppData) => Join(localAppData, "Sill", "install.json");

    private static string Join(params string[] parts) =>
        string.Join('\\', parts.Select((p, i) => i == 0 ? p.TrimEnd('\\', '/') : p.Trim('\\', '/')));

    /// <summary>A path as Windows compares it: backslashes, no <c>\\?\</c> prefix, no trailing slash, lower case.</summary>
    public static string Normalize(string path)
    {
        var p = path.Trim().Replace('/', '\\');
        if (p.StartsWith(@"\\?\", StringComparison.Ordinal)) p = p[4..];
        while (p.Length > 3 && p.EndsWith('\\')) p = p[..^1];
        return p.ToLowerInvariant();
    }

    public static bool SamePath(string a, string b) => Normalize(a) == Normalize(b);

    /// <summary>Whether this start should consider installing at all: Sill.exe started with no
    /// arguments (a double-click, the Start menu), never the spike's Sill.Viewer.exe or a launch with
    /// options (a developer's, a test's), and not with SILL_NO_SELF_INSTALL=1.</summary>
    public static bool Applies(string? processPath, IReadOnlyList<string> args, string? noSelfInstall) =>
        processPath is not null && args.Count == 0 && noSelfInstall != "1"
        && string.Equals(FileName(processPath), ExeName, StringComparison.OrdinalIgnoreCase);

    private static string FileName(string path)
    {
        var p = path.Replace('/', '\\');
        int slash = p.LastIndexOf('\\');
        return slash >= 0 ? p[(slash + 1)..] : p;
    }

    public enum Decision
    {
        /// <summary>Run this copy, saying nothing: it is the installed one, or its offer was turned down for good.</summary>
        RunHere,
        /// <summary>Nothing is installed: offer to install this copy.</summary>
        OfferInstall,
        /// <summary>An older copy (or one with no version) is installed: offer to replace it.</summary>
        OfferReplace,
        /// <summary>The same or a newer version is installed: offer to open that one instead.</summary>
        OfferOpenInstalled,
    }

    /// <summary>What to offer, from where this copy runs, its version, and what is installed.</summary>
    public static Decision Decide(string runningPath, SillVersion? runningVersion, string installedPath, bool installedExists,
                                  SillVersion? installedVersion, IReadOnlyCollection<string>? declined = null)
    {
        if (SamePath(runningPath, installedPath)) return Decision.RunHere;
        if (declined is not null && declined.Any(d => SamePath(d, runningPath))) return Decision.RunHere;
        if (!installedExists) return Decision.OfferInstall;
        if (installedVersion is null) return Decision.OfferReplace;
        if (runningVersion is not null && installedVersion < runningVersion) return Decision.OfferReplace;
        return Decision.OfferOpenInstalled;
    }

    /// <summary>The dialog's words for a decision that offers something: its heading, its text, the
    /// button that accepts and the one that runs this copy as it is.</summary>
    public static (string Heading, string Text, string Accept, string Decline)? Words(Decision decision, SillVersion? running, SillVersion? installed) =>
        decision switch
        {
            Decision.OfferInstall => ("Install Sill on this PC?",
                "Sill copies itself to your Programs folder and adds Sill to the Start menu, for your account only: no administrator needed. Then it opens from there, and you can delete this copy.",
                "Install", "Run Without Installing"),
            Decision.OfferReplace => ($"Replace the installed Sill{(installed is null ? "" : $" {installed}")}?",
                $"This is Sill{(running is null ? "" : $" {running}")}. Sill replaces the copy in your Programs folder with this one and opens it from there. Your paired Macs and settings stay.",
                "Replace", "Run Without Installing"),
            Decision.OfferOpenInstalled => ($"Sill {installed} is already installed",
                $"This copy is Sill{(running is null ? "" : $" {running}")}. Open the installed Sill from your Programs folder instead?",
                "Open Installed Sill", "Run This Copy"),
            _ => null,
        };

    /// <summary>The line when the installed copy can't be replaced because it is running.</summary>
    public const string InstalledIsRunning = "The installed Sill is open, so it can’t be replaced now. Close its window, then open this copy again.";
}
