// The live viewer: the paired Mac's Desktop in a window, as it streams, with the mouse and keys
// sent to the Mac (left Ctrl is ⌘, right Ctrl ⌃, Alt ⌥; F11 toggles full screen).
//
//   Sill.Viewer [--identity <dir>] [--host <address>:<port>]… [--decoder auto|gpu|software] [--adapter N]
//
// --identity is where `Sill.Spike pair` saved this device's key and the Mac (default
// %LOCALAPPDATA%\Sill\spike); each --host is an address to dial instead of the one saved at
// pairing, tried in order (the Mac's Wi-Fi address, then its Tailscale name, say). The picture is
// decoded and drawn on the GPU unless --decoder software (auto and gpu both fall back to software
// when the GPU path can't start or fails); --adapter picks DXGI's Nth adapter instead of Windows'
// default (0 drives the display; 1 is often a laptop's discrete GPU).

using Sill.Viewer;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        // Sill.exe started with no options from anywhere but its installed place offers to install
        // itself (SelfInstall); the spike's Sill.Viewer.exe and any launch with options skip this.
        if (SelfInstall.OfferAtStartup(args)) return 0;
        // TEST ONLY: SILL_TEST_IDENTITY_DIR is the default --identity, so a test of Sill.exe started
        // with no options (the install offer, the update check) never dials the PC's own paired Mac.
        string dir = Environment.GetEnvironmentVariable("SILL_TEST_IDENTITY_DIR") is { Length: > 0 } testDir ? testDir
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sill", "spike");
        var hosts = new List<string>();
        string decoder = "auto"; int? adapter = null;
        for (int i = 0; i + 1 < args.Length; i += 2)
        {
            if (args[i] == "--identity") dir = args[i + 1];
            else if (args[i] == "--host") hosts.Add(args[i + 1]);
            else if (args[i] == "--decoder" && args[i + 1] is "auto" or "gpu" or "software") decoder = args[i + 1];
            else if (args[i] == "--adapter" && int.TryParse(args[i + 1], out int n)) adapter = n;
            else { MessageBox.Show($"Unknown option {args[i]}.", "Sill Viewer"); return 2; }
        }
        var form = new ViewerForm(dir, hosts, new ViewerOptions(decoder, adapter));
        // Sill.exe checks GitHub for a newer release (UpdatePrompt); the spike's Sill.Viewer.exe doesn't.
        UpdatePrompt.Start(form);
        Application.Run(form);
        return 0;
    }
}

/// <summary>How the viewer decodes: auto, gpu or software, and which DXGI adapter (null: Windows' default).</summary>
sealed record ViewerOptions(string Decoder, int? Adapter);
