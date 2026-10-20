// The live viewer: the paired Mac's Desktop in a window, as it streams, with the mouse and keys
// sent to the Mac (left Ctrl is ⌘, right Ctrl ⌃, Alt ⌥; F11 toggles full screen).
//
//   Sill.Viewer [--identity <dir>] [--host <address>:<port>]… [--decoder auto|gpu|software] [--adapter N]
//               [--service-type <type>]…
//
// --identity is where `Sill.Spike pair` saved this device's key and the Mac (default
// %LOCALAPPDATA%\Sill\spike). Without --host the viewer opens on the connect screen: the Macs
// Windows' DNS-SD finds on this network (_sill._tcp; TEST ONLY --service-type, repeatable, browses
// others instead, such as a synthetic host's _silltest._tcp), a paired one connected with a click
// at the address and port it resolved. Each --host is an address to dial straight away instead,
// tried in order (the Mac's Wi-Fi address, then its Tailscale name, say). The picture is
// decoded and drawn on the GPU unless --decoder software (auto and gpu both fall back to software
// when the GPU path can't start or fails); --adapter picks DXGI's Nth adapter instead of Windows'
// default (0 drives the display; 1 is often a laptop's discrete GPU).

using Sill.Viewer;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sill", "spike");
        var hosts = new List<string>();
        var serviceTypes = new List<string>();
        string decoder = "auto"; int? adapter = null;
        for (int i = 0; i + 1 < args.Length; i += 2)
        {
            if (args[i] == "--identity") dir = args[i + 1];
            else if (args[i] == "--host") hosts.Add(args[i + 1]);
            else if (args[i] == "--service-type" && args[i + 1].EndsWith("._tcp", StringComparison.Ordinal)) serviceTypes.Add(args[i + 1]);
            else if (args[i] == "--decoder" && args[i + 1] is "auto" or "gpu" or "software") decoder = args[i + 1];
            else if (args[i] == "--adapter" && int.TryParse(args[i + 1], out int n)) adapter = n;
            else { MessageBox.Show($"Unknown option {args[i]}.", "Sill Viewer"); return 2; }
        }
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SillApp(dir, hosts, new ViewerOptions(decoder, adapter), serviceTypes.Count > 0 ? serviceTypes : ["_sill._tcp"]));
        return 0;
    }
}

/// <summary>How the viewer decodes: auto, gpu or software, and which DXGI adapter (null: Windows' default).</summary>
sealed record ViewerOptions(string Decoder, int? Adapter);
