using System.Diagnostics;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The app's one update check: <see cref="SillApp"/> makes it once for the whole run (the connect
/// screen and the viewer come and go, the checker stays) and disposes it as the app ends. Sill.exe
/// checks; the spike's Sill.Viewer.exe only with a test feed; a test run (SILL_TEST_IDENTITY_DIR)
/// never asks GitHub (<see cref="UpdatePolicy.ChecksThisRun"/>). Its state is <c>update.json</c>, its
/// lines <c>update.log</c>, in <c>%LOCALAPPDATA%\Sill</c> (a test run's own folder instead). What it
/// finds shows in place, never in a dialog: "Sill 0.6 Is Available…" on the connect screen, and the
/// update rows in Settings › This PC, as Sill.app's menu item and General pane.
/// </summary>
static class AppUpdates
{
    private static string LocalAppData => DataFolder.LocalAppData();

    /// <summary>The checker for this run, started with <paramref name="context"/> (the UI thread's), or
    /// null when this run does not check.</summary>
    public static UpdateChecker? Create(SynchronizationContext? context)
    {
        var testDir = Environment.GetEnvironmentVariable("SILL_TEST_IDENTITY_DIR");
        if (!UpdatePolicy.ChecksThisRun(SelfInstallPolicy.IsSillExe(Environment.ProcessPath),
                Environment.GetEnvironmentVariable("SILL_TEST_UPDATE_FEED"), testDir)) return null;
        var dir = UpdatePolicy.StateDirectory(LocalAppData, testDir);
        var logPath = Path.Combine(dir, "update.log");
        void Log(string line)
        {
            try
            {
                Directory.CreateDirectory(dir);
                File.AppendAllText(logPath, $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss} {line}{Environment.NewLine}");
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        var checker = new UpdateChecker(UpdateChecker.Configuration.FromEnvironment(Path.Combine(dir, "update.json"), Log), Log);
        checker.Start(context);
        return checker;
    }

    /// <summary>The release page in the default browser.</summary>
    public static void OpenPage(Uri url)
    {
        try { Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { }
    }

    /// <summary>Whether this process is the installed Sill.exe, whose Start menu shortcut Settings offers.</summary>
    public static bool RunsInstalled => SelfInstallPolicy.RunsInstalled(Environment.ProcessPath, LocalAppData);
}
