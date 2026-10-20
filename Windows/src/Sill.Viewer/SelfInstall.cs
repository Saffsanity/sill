using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text.Json;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// Sill.exe installs itself, per user and without an administrator: started from anywhere else (the
/// Downloads folder, the unzipped release), it offers to copy itself to
/// <c>%LOCALAPPDATA%\Programs\Sill\Sill.exe</c>, add <c>Sill</c> to the user's Start menu, and open
/// from there; an older installed copy is replaced, a same or newer one offered instead.
/// <see cref="SelfInstallPolicy"/> decides; this class asks (a task dialog), copies, makes the
/// shortcut and relaunches. Nothing is written to the registry; uninstalling is deleting the folder
/// and the shortcut (<see cref="RemoveShortcut"/> is Settings' half).
/// </summary>
static class SelfInstall
{
    private static string LocalAppData => Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    /// <summary>The user's Start Menu\Programs folder (not All Users': no administrator).</summary>
    private static string Programs => Environment.GetFolderPath(Environment.SpecialFolder.Programs);

    public static string InstalledPath => SelfInstallPolicy.InstalledPath(LocalAppData);
    public static string ShortcutPath => SelfInstallPolicy.ShortcutPath(Programs);
    public static bool ShortcutExists => File.Exists(ShortcutPath);

    /// <summary>At startup, before any window: offers to install when <see cref="SelfInstallPolicy.Applies"/>.
    /// True when the installed copy was started and this process should exit at once.</summary>
    public static bool OfferAtStartup(string[] args)
    {
        var running = Environment.ProcessPath;
        if (!SelfInstallPolicy.Applies(running, args, Environment.GetEnvironmentVariable("SILL_NO_SELF_INSTALL"))) return false;
        var installed = InstalledPath;
        var runningVersion = SillVersion.Parse(AppVersion.Current);
        bool exists = File.Exists(installed);
        var installedVersion = exists ? SillVersion.Parse(FileVersionInfo.GetVersionInfo(installed).ProductVersion) : null;
        var statePath = SelfInstallPolicy.StatePath(LocalAppData);
        var declined = LoadDeclined(statePath);
        var decision = SelfInstallPolicy.Decide(running!, runningVersion, installed, exists, installedVersion, declined);
        if (SelfInstallPolicy.Words(decision, runningVersion, installedVersion) is not { } words) return false;

        var accept = new TaskDialogButton(words.Accept);
        var decline = new TaskDialogButton(words.Decline);
        var never = new TaskDialogVerificationCheckBox("Don’t ask again for this copy");
        var page = new TaskDialogPage
        {
            Caption = "Sill",
            Heading = words.Heading,
            Text = words.Text,
            Icon = TaskDialogIcon.Information,
            Buttons = { accept, decline },
            DefaultButton = accept,
            Verification = decision == SelfInstallPolicy.Decision.OfferOpenInstalled ? null : never,
            AllowCancel = true,
        };
        var answer = TaskDialog.ShowDialog(page, TaskDialogStartupLocation.CenterScreen);
        if (answer != accept)
        {
            if (never.Checked) SaveDeclined(statePath, [.. declined, running!]);
            return false;
        }
        if (decision == SelfInstallPolicy.Decision.OfferOpenInstalled) return Launch(installed);
        try
        {
            Install(running!, installed);
        }
        catch (Exception e) when (exists && e is IOException or UnauthorizedAccessException)
        {
            // Windows refuses to replace an exe that is running.
            Tell(SelfInstallPolicy.InstalledIsRunning, TaskDialogIcon.Warning);
            return false;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or COMException)
        {
            Tell($"Sill couldn’t install itself: {e.Message} This copy opens instead.", TaskDialogIcon.Error);
            return false;
        }
        return Launch(installed);
    }

    /// <summary>Copies this exe into place (through a temporary file beside it, so a failed copy never
    /// leaves half an exe) and makes the Start menu shortcut.</summary>
    public static void Install(string from, string to)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(to)!);
        var temp = to + ".new";
        File.Copy(from, temp, overwrite: true);
        try { File.Move(temp, to, overwrite: true); }
        catch { try { File.Delete(temp); } catch (IOException) { } throw; }
        MakeShortcut(ShortcutPath, to);
    }

    /// <summary>Settings' "Remove from Start menu": deletes the shortcut (the installed exe stays).</summary>
    public static bool RemoveShortcut()
    {
        try { File.Delete(ShortcutPath); return true; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary>Settings' "Add to Start menu", for an installed copy whose shortcut was removed.</summary>
    public static void AddShortcut() => MakeShortcut(ShortcutPath, InstalledPath);

    private static bool Launch(string exe)
    {
        try
        {
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(exe)! });
            return true;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or IOException)
        {
            Tell($"Sill couldn’t open {exe}: {e.Message}", TaskDialogIcon.Error);
            return false;
        }
    }

    private static void Tell(string text, TaskDialogIcon icon) =>
        TaskDialog.ShowDialog(new TaskDialogPage { Caption = "Sill", Text = text, Icon = icon, Buttons = { TaskDialogButton.OK } },
            TaskDialogStartupLocation.CenterScreen);

    private sealed record State(List<string> Declined);

    private static List<string> LoadDeclined(string path)
    {
        try { return JsonSerializer.Deserialize<State>(File.ReadAllText(path))?.Declined ?? []; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return []; }
    }

    private static void SaveDeclined(string path, List<string> declined)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, JsonSerializer.Serialize(new State(declined)));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    // The shortcut, through the shell's own IShellLink (no WScript, no package).

    private static void MakeShortcut(string lnk, string target)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lnk)!);
        var link = (IShellLinkW)new ShellLink();
        try
        {
            link.SetPath(target);
            link.SetWorkingDirectory(Path.GetDirectoryName(target)!);
            link.SetDescription("Sill: your Mac’s windows on this PC");
            link.SetIconLocation(target, 0);
            ((IPersistFile)link).Save(lnk, true);
        }
        finally { Marshal.FinalReleaseComObject(link); }
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder file, int max, IntPtr findData, uint flags);
        void GetIDList(out IntPtr idl);
        void SetIDList(IntPtr idl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder name, int max);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder dir, int max);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string dir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder args, int max);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int show);
        void SetShowCmd(int show);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder path, int max, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr hwnd, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
    }
}
