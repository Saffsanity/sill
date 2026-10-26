namespace Sill.Protocol;

/// <summary>
/// Where Sill for Windows keeps its data: <c>%LOCALAPPDATA%\Sill</c> (ticket 10d), with the device's
/// key (<c>device.p12</c>), the saved Macs (<c>macs.json</c>), this PC's name (<c>pc.json</c>), the
/// window (<c>window.json</c>), the update check's state (<c>update.json</c>, <c>update.log</c>), the
/// install offer's (<c>install.json</c>) and the log (<c>viewer.log</c>). The spike kept the first
/// ones in <c>%LOCALAPPDATA%\Sill\spike</c>: the first start of a build with this folder moves them up
/// (<see cref="Open"/>) and renames the old folder <c>spike.migrated</c>, as the spike's
/// <c>mac.json</c> became <c>mac.json.migrated</c>. A test run's SILL_TEST_IDENTITY_DIR is the folder
/// instead, and nothing moves. Paths are Windows paths, joined with backslashes, so the rules are
/// tested on any OS.
/// </summary>
public static class DataFolder
{
    public const string Name = "Sill", Spike = "spike", SpikeMigrated = "spike.migrated";

    /// <summary>What the spike's folder can hold that moves up: the key, the saved Macs (and the
    /// spike's own <c>mac.json</c>, should it never have been taken in), this PC's name, the window,
    /// the update check's state and the log. Anything else (<c>mac.json.migrated</c>, a
    /// <c>macs.json.bad</c>, a session's saved keyframe) stays in <c>spike.migrated</c>.</summary>
    public static readonly IReadOnlyList<string> Moved =
        [DeviceIdentity.FileName, SavedMacsFile.FileName, SavedMacsFile.OldFileName, ThisPc.FileName, "window.json", "update.json", "update.log", "viewer.log"];

    /// <summary>Files whose presence says the folder already holds a pairing: then nothing moves into it.</summary>
    private static readonly string[] Paired = [DeviceIdentity.FileName, SavedMacsFile.FileName, SavedMacsFile.OldFileName];

    /// <summary><c>%LOCALAPPDATA%\Sill</c>.</summary>
    public static string Root(string localAppData) => localAppData.TrimEnd('\\', '/') + "\\" + Name;
    /// <summary><c>%LOCALAPPDATA%\Sill\spike</c>, the spike's folder.</summary>
    public static string SpikeDir(string localAppData) => Root(localAppData) + "\\" + Spike;

    /// <summary>%LOCALAPPDATA%: Windows' own (which the LOCALAPPDATA variable doesn't change), or TEST
    /// ONLY SILL_TEST_LOCALAPPDATA, a scratch folder standing in for it whole (the data folder, the
    /// install place, the update check's state), so a test of the move never touches the PC's own.</summary>
    public static string LocalAppData() =>
        Environment.GetEnvironmentVariable("SILL_TEST_LOCALAPPDATA") is { Length: > 0 } test ? test
            : Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

    public enum Use
    {
        /// <summary>SILL_TEST_IDENTITY_DIR: that folder, nothing moved.</summary>
        Test,
        /// <summary><c>%LOCALAPPDATA%\Sill</c> as it is: no spike folder, or the new one already paired.</summary>
        Data,
        /// <summary>Move <see cref="Plan.Files"/> up from the spike's folder, then rename it.</summary>
        Migrate,
    }

    /// <param name="Files">The files to move up: those of <see cref="Moved"/> the spike's folder has
    /// and the new one doesn't (one already there is never overwritten).</param>
    public sealed record Plan(Use Use, IReadOnlyList<string> Files);

    /// <summary>What to do at a start, from whether a test folder is set, whether the spike's folder
    /// exists, and the file names in it and in <c>%LOCALAPPDATA%\Sill</c>. Pure.</summary>
    public static Plan Decide(bool testDir, bool spikeExists, IReadOnlyCollection<string> inSpike, IReadOnlyCollection<string> inData)
    {
        if (testDir) return new(Use.Test, []);
        if (!spikeExists) return new(Use.Data, []);
        var there = new HashSet<string>(inData, StringComparer.OrdinalIgnoreCase);
        if (Paired.Any(there.Contains)) return new(Use.Data, []);
        var spike = new HashSet<string>(inSpike, StringComparer.OrdinalIgnoreCase);
        return new(Use.Migrate, Moved.Where(f => spike.Contains(f) && !there.Contains(f)).ToList());
    }

    /// <summary>The name the spike's folder takes once moved: <c>spike.migrated</c>, or
    /// <c>spike.migrated 2</c> and on when one is already there.</summary>
    public static string MigratedName(IReadOnlyCollection<string> inRoot)
    {
        var there = new HashSet<string>(inRoot, StringComparer.OrdinalIgnoreCase);
        if (!there.Contains(SpikeMigrated)) return SpikeMigrated;
        for (int n = 2; ; n++) if (!there.Contains($"{SpikeMigrated} {n}")) return $"{SpikeMigrated} {n}";
    }

    /// <param name="Directory">The folder this run uses.</param>
    /// <param name="Line">One line for the log, when something moved or a move failed.</param>
    public sealed record Opened(string Directory, string? Line);

    /// <summary>The folder this run uses, after moving the spike's files up when <see cref="Decide"/>
    /// says so. Call it once, at the start, before anything reads the folder.</summary>
    public static Opened Open(string localAppData, string? testDir) =>
        !string.IsNullOrEmpty(testDir) ? new(testDir, null) : MoveUp(SpikeDir(localAppData), Root(localAppData));

    /// <summary>
    /// The move itself, between two real folders: each file copied beside its new place, then renamed
    /// into it (never over a file there), then the spike's folder renamed (<see cref="MigratedName"/>)
    /// and the copied originals deleted from it. Should any step before the folder's rename fail,
    /// what was put in <paramref name="data"/> is taken out again and this run uses
    /// <paramref name="spike"/>, as it was; the next start tries again.
    /// </summary>
    public static Opened MoveUp(string spike, string data)
    {
        static IReadOnlyList<string> Names(string dir) =>
            Directory.Exists(dir) ? Directory.EnumerateFileSystemEntries(dir).Select(p => Path.GetFileName(p)).ToList() : [];
        Plan plan;
        try { plan = Decide(false, Directory.Exists(spike), Names(spike), Names(data)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return new(Directory.Exists(spike) ? spike : data, $"Data folder: couldn’t look at {spike} ({e.Message}).");
        }
        if (plan.Use != Use.Migrate) return new(data, null);

        var placed = new List<string>();
        string? migrated = null;
        try
        {
            Directory.CreateDirectory(data);
            foreach (var f in plan.Files)
            {
                string temp = Path.Combine(data, f + ".migrating");
                File.Copy(Path.Combine(spike, f), temp, overwrite: true);
                placed.Add(temp);
                File.Move(temp, Path.Combine(data, f), overwrite: false);
                placed[^1] = Path.Combine(data, f);
            }
            migrated = Path.Combine(Path.GetDirectoryName(spike)!, MigratedName(Names(Path.GetDirectoryName(spike)!)));
            Directory.Move(spike, migrated);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            foreach (var p in placed)
                try { File.Delete(p); } catch (Exception d) when (d is IOException or UnauthorizedAccessException) { }
            return new(spike, $"Data folder: couldn’t move {spike} to {data} ({e.Message}); using {spike} for now.");
        }
        foreach (var f in plan.Files)
            try { File.Delete(Path.Combine(migrated, f)); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return new(data, $"Data folder: moved {(plan.Files.Count == 0 ? "nothing" : string.Join(", ", plan.Files))} from {spike} to {data}; "
            + $"the old folder is now {Path.GetFileName(migrated)}.");
    }
}
