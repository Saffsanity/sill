using System.Diagnostics;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The update check in the app, for now: Sill.exe (never the spike's Sill.Viewer.exe, unless a test
/// feed is set) runs <see cref="UpdateChecker"/> with its state in <c>%LOCALAPPDATA%\Sill\update.json</c>
/// and its lines in <c>update.log</c> beside it, and when a newer release is first found says
/// "Sill 0.6 Is Available…" once, offering its page on GitHub in the browser. Nothing downloads.
/// The connect screen and Settings take over from this dialog: they read <see cref="Checker"/>
/// (<c>Offer</c>, <c>Pane</c>, <c>Changed</c>, <c>SetAutomatic</c>, <c>CheckNow</c>, <c>UpdatePolicy.Footnote</c>).
/// </summary>
static class UpdatePrompt
{
    /// <summary>The app's one checker, or null when this run does not check.</summary>
    public static UpdateChecker? Checker { get; private set; }

    public static string Directory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sill");

    /// <summary>Starts the checker on the UI thread's context once <paramref name="owner"/> exists.</summary>
    public static UpdateChecker? Start(Form owner)
    {
        bool testFeed = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SILL_TEST_UPDATE_FEED"));
        bool product = string.Equals(Path.GetFileName(Environment.ProcessPath), SelfInstallPolicy.ExeName, StringComparison.OrdinalIgnoreCase);
        if (!product && !testFeed) return null;
        // A test run (SILL_TEST_IDENTITY_DIR) never asks GitHub: only a test feed, if it gives one.
        if (!testFeed && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SILL_TEST_IDENTITY_DIR"))) return null;
        var logPath = Path.Combine(Directory, "update.log");
        void Log(string line)
        {
            try
            {
                System.IO.Directory.CreateDirectory(Directory);
                File.AppendAllText(logPath, $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss} {line}{Environment.NewLine}");
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        var checker = new UpdateChecker(UpdateChecker.Configuration.FromEnvironment(Path.Combine(Directory, "update.json"), Log), Log);
        checker.Changed += () => Offer(owner, checker);
        Microsoft.Win32.SystemEvents.PowerModeChanged += (_, e) =>
        {
            if (e.Mode == Microsoft.Win32.PowerModes.Resume) checker.SystemDidWake();
        };
        owner.FormClosed += (_, _) => checker.Dispose();
        Checker = checker;
        checker.Start(SynchronizationContext.Current);
        // A release found by an earlier run and not yet shown: once the window is up.
        owner.Shown += (_, _) => Offer(owner, checker);
        return checker;
    }

    private static bool showing;

    private static void Offer(Form owner, UpdateChecker checker)
    {
        if (showing || owner.IsDisposed || !owner.IsHandleCreated || checker.UnshownOffer is not { } offer) return;
        showing = true;
        try
        {
            checker.NoteShown(offer);
            var open = new TaskDialogButton("Open Release Page");
            var later = new TaskDialogButton("Not Now");
            var page = new TaskDialogPage
            {
                Caption = "Sill",
                Heading = UpdatePolicy.MenuTitle(offer),
                Text = (checker.Running is { } running ? UpdatePolicy.MenuSubtitle(running) : "Opens its download page")
                    + ". Download the Windows zip there and open the new Sill.exe: it replaces this one.",
                Icon = TaskDialogIcon.Information,
                Buttons = { open, later },
                DefaultButton = open,
            };
            if (TaskDialog.ShowDialog(owner, page) == open) OpenPage(offer.Url);
        }
        finally { showing = false; }
    }

    /// <summary>The release page in the default browser.</summary>
    public static void OpenPage(Uri url)
    {
        try { Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { }
    }
}
