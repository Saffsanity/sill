using System.Diagnostics;
using System.Text.Json;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The window the viewer opens on when no <c>--host</c> is given: the <see cref="ConnectScreen"/>
/// over a <see cref="MacBrowser"/> per service type. A paired Mac's row connects at the addresses
/// and port the browser resolved (<see cref="Connect"/>, which <see cref="SillApp"/> turns into a
/// <see cref="ViewerForm"/>, pinned to the saved key as before). "Not paired" and Add a Mac… raise
/// <see cref="PairRequested"/> and <see cref="AddMacRequested"/>, which ticket 10b fills; until
/// then the status line says to pair with the spike.
/// </summary>
sealed class ConnectForm : Form
{
    /// <summary>A paired Mac clicked: the addresses to dial (<c>host:port</c>, in order) and its name.</summary>
    public event Action<IReadOnlyList<string>, string>? Connect;
    /// <summary>A "Not paired" row clicked (10b: the ask, then the code card).</summary>
    public event Action<MacRow>? PairRequested;
    /// <summary>Add a Mac… clicked (10b: a pasted link, or an address and a code).</summary>
    public event Action? AddMacRequested;

    public const string LookingOnNetwork = "Looking for Macs on this network";

    private readonly string dir;
    private readonly ConnectScreen screen = new() { Dock = DockStyle.Fill };
    private readonly List<MacBrowser> browsers = [];
    private readonly IReadOnlyList<string> serviceTypes;
    private readonly Stopwatch since = Stopwatch.StartNew();
    private readonly WindowPlacement? placement;
    private IReadOnlyList<KnownMac> saved = [];
    private IReadOnlyList<MacRow> rows = [];
    private string status = LookingOnNetwork;
    private string? busyRow;
    private bool listedOnce;

    public ConnectForm(string dir, IReadOnlyList<string> serviceTypes)
    {
        this.dir = dir; this.serviceTypes = serviceTypes;
        Text = "Sill";
        BackColor = Palette.Panel;
        ClientSize = new Size(1280, 800);
        // Where the viewer's window was (window.json), so the two read as one window.
        placement = WindowPlacement.Load(Path.Combine(dir, "window.json"));
        StartPosition = FormStartPosition.Manual;
        Bounds = WindowPlacement.Fit(placement, Screen.AllScreens.Select(s => s.WorkingArea).ToList(), Size);
        Controls.Add(screen);
        screen.RowClicked += Clicked;
        screen.AddMacClicked += () =>
        {
            if (AddMacRequested is { } add) { add(); return; }
            Say("Adding a Mac by its code or a link comes next. For now, pair with Sill.Spike pair, then open Sill again.");
        };
        KeyPreview = true;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Palette.DarkTitleBar(Handle);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        if (placement?.Maximized == true) WindowState = FormWindowState.Maximized;
        saved = LoadSaved();
        Log($"Connect screen: looking for {string.Join(", ", serviceTypes)}; {(saved.Count == 0 ? "no Mac saved" : $"saved: {saved[0].Name} ({saved[0].MacId})")}.");
        foreach (var type in serviceTypes)
        {
            var b = new MacBrowser(type);
            b.Log += Log;
            b.Changed += _ => { try { BeginInvoke(Refresh); } catch (InvalidOperationException) { } };
            try { b.Start(); browsers.Add(b); }
            catch (Exception ex) when (ex is PlatformNotSupportedException or InvalidOperationException or DllNotFoundException)
            {
                Log($"Browse: {ex.Message}");
                status = $"This PC can’t look for Macs on the network ({ex.Message}).";
                b.Dispose();
            }
        }
        Refresh();
    }

    private new void Refresh()
    {
        if (IsDisposed) return;
        rows = ConnectRows.Build(browsers.SelectMany(b => b.Current), saved);
        if (rows.Count > 0 && !listedOnce)
        {
            listedOnce = true;
            Log($"Connect screen: first Mac listed {since.Elapsed.TotalSeconds:0.00} s after the browse began.");
        }
        Log($"Connect screen: {(rows.Count == 0 ? "no Macs" : string.Join("; ", rows.Select(r => $"{r.Name} ({r.Service.ServiceType}): {r.State}, {r.Word ?? "no word"}")))} "
            + $"at {since.Elapsed.TotalSeconds:0.00} s.");
        if (busyRow is not null && rows.All(r => r.Service.Id != busyRow)) busyRow = null;
        screen.Show(rows, status, busyRow);
    }

    private void Say(string line)
    {
        status = line;
        screen.Show(rows, status, busyRow);
    }

    private void Clicked(MacRow row)
    {
        Log($"Connect screen: clicked {row.Name}, {row.State}.");
        switch (row.State)
        {
            case MacRow.Kind.Paired:
                var targets = row.DialTargets();
                if (targets.Count == 0) { Say($"{row.Name} didn’t say where it is. Try again in a moment."); return; }
                busyRow = row.Service.Id;
                Say($"Connecting to {row.Name}…");
                Connect?.Invoke(targets, row.Name);
                break;
            case MacRow.Kind.NotPaired or MacRow.Kind.OpenDoor:
                if (PairRequested is { } pair) { pair(row); return; }
                Say($"{row.Name} isn’t paired with this PC yet. Pairing here comes next; for now, run "
                    + $"Sill.Spike pair --ask 1 --host {row.DialTargets().FirstOrDefault() ?? row.Name}, then open Sill again.");
                break;
            case MacRow.Kind.UpdateSill:
                Say(ConnectRows.UpdateSillStatus(row.Name));
                break;
        }
    }

    /// <summary>The Macs this PC paired with: today the one in mac.json (Sill.Spike pair's), its
    /// recognition key included. 10c makes this a list.</summary>
    private IReadOnlyList<KnownMac> LoadSaved()
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, "mac.json")));
            var root = doc.RootElement;
            string? Text(string name) => root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
            if (Text("MacId") is not { } id || Text("Name") is not { } name) return [];
            var key = Text("RecognitionKey") is { } rk ? Base64Url.Decode(rk) : null;
            return [new KnownMac(id, name, key is { Length: 32 } ? key : null, null)];
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return []; }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        foreach (var b in browsers) b.Dispose();
        // Where it was, for the viewer's next window (the viewer's own full screen and decoding kept).
        if (WindowState != FormWindowState.Minimized)
        {
            var normal = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
            new WindowPlacement(normal.X, normal.Y, normal.Width, normal.Height, WindowState == FormWindowState.Maximized,
                placement?.FullScreen ?? false, placement?.SoftwareDecoding ?? false).Save(Path.Combine(dir, "window.json"));
        }
        base.OnFormClosing(e);
    }

    private readonly Lock logGate = new();
    private void Log(string line)
    {
        try { lock (logGate) File.AppendAllText(Path.Combine(dir, "viewer.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {line}{Environment.NewLine}"); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}

/// <summary>
/// One window at a time: the connect screen, or the viewer it opened. The viewer's Disconnect (in
/// its Settings panel) brings the connect screen back; closing either window quits.
/// </summary>
sealed class SillApp : ApplicationContext
{
    private readonly string dir;
    private readonly ViewerOptions options;
    private readonly IReadOnlyList<string> serviceTypes;

    public SillApp(string dir, IReadOnlyList<string> hosts, ViewerOptions options, IReadOnlyList<string> serviceTypes)
    {
        this.dir = dir; this.options = options; this.serviceTypes = serviceTypes;
        if (hosts.Count > 0) ShowViewer(hosts);
        else ShowConnect();
    }

    private void ShowConnect()
    {
        var form = new ConnectForm(dir, serviceTypes);
        IReadOnlyList<string>? next = null;
        form.Connect += (targets, _) => { next = targets; form.Close(); };
        form.FormClosed += (_, _) =>
        {
            if (next is { } t) ShowViewer(t);
            else ExitThread();
        };
        form.Show();
    }

    private void ShowViewer(IReadOnlyList<string> hosts)
    {
        var form = new ViewerForm(dir, hosts, options);
        form.FormClosed += (_, _) =>
        {
            if (form.Disconnecting) ShowConnect();
            else ExitThread();
        };
        form.Show();
    }
}
