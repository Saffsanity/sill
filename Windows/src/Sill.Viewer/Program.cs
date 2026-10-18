// The live viewer: the paired Mac's Desktop in a window, as it streams, with the mouse and keys
// sent to the Mac (left Ctrl is ⌘, right Ctrl ⌃, Alt ⌥; F11 toggles full screen).
//
//   Sill.Viewer [--identity <dir>] [--host <address>:<port>]…
//
// --identity is where `Sill.Spike pair` saved this device's key and the Mac (default
// %LOCALAPPDATA%\Sill\spike); each --host is an address to dial instead of the one saved at
// pairing, tried in order (the Mac's Wi-Fi address, then its Tailscale name, say).

using Sill.Viewer;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sill", "spike");
        var hosts = new List<string>();
        for (int i = 0; i + 1 < args.Length; i += 2)
        {
            if (args[i] == "--identity") dir = args[i + 1];
            else if (args[i] == "--host") hosts.Add(args[i + 1]);
            else { MessageBox.Show($"Unknown option {args[i]}.", "Sill Viewer"); return 2; }
        }
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ViewerForm(dir, hosts));
        return 0;
    }
}
