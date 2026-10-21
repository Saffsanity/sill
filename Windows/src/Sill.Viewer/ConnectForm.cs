using System.Diagnostics;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The window the viewer opens on when no <c>--host</c> is given: the <see cref="ConnectScreen"/>
/// over a <see cref="MacBrowser"/> per service type. A paired Mac's row connects at the addresses
/// and port the browser resolved (<see cref="Connect"/>, which <see cref="SillApp"/> turns into a
/// <see cref="ViewerForm"/>, pinned to the saved key). A "Not paired" row asks its Mac for its code
/// and Add a Mac… takes a link or an address and a code, both through a <see cref="PairingFlow"/>
/// shown as a <see cref="PairCard"/>; a pairing connects at once.
/// </summary>
sealed class ConnectForm : Form
{
    /// <summary>A Mac to connect to: the addresses to dial (<c>host:port</c>, in order), its name and its Mac ID.</summary>
    public event Action<IReadOnlyList<string>, string, string>? Connect;

    public const string LookingOnNetwork = "Looking for Macs on this network";

    private readonly string dir;
    private readonly ConnectScreen screen = new() { Dock = DockStyle.Fill };
    private readonly List<MacBrowser> browsers = [];
    private readonly IReadOnlyList<string> serviceTypes;
    private readonly Stopwatch since = Stopwatch.StartNew();
    private readonly WindowPlacement? placement;
    private readonly ISavedMacs store;
    private readonly PairCard card = new();
    private DeviceIdentity? identity;
    private PairingFlow? flow;
    private MacRow? flowRow;
    private IReadOnlyList<KnownMac> saved = [];
    private IReadOnlyList<MacRow> rows = [];
    private string status;
    private string? busyRow;
    private bool listedOnce;

    /// <param name="status">The status line to open with (a session's end: a Mac with a new key, a
    /// forgotten Mac); null for "Looking for Macs on this network".</param>
    public ConnectForm(string dir, IReadOnlyList<string> serviceTypes, string? status = null)
    {
        this.dir = dir; this.serviceTypes = serviceTypes;
        this.status = status ?? LookingOnNetwork;
        store = new SavedMacsFile(dir);
        Text = "Sill";
        BackColor = Palette.Panel;
        ClientSize = new Size(1280, 800);
        // Where the viewer's window was (window.json), so the two read as one window.
        placement = WindowPlacement.Load(Path.Combine(dir, "window.json"));
        StartPosition = FormStartPosition.Manual;
        Bounds = WindowPlacement.Fit(placement, Screen.AllScreens.Select(s => s.WorkingArea).ToList(), Size);
        Controls.Add(screen);
        screen.RowClicked += Clicked;
        screen.AddMacClicked += () => Start(null);
        card.Pair += (where, code) => _ = flow?.IsAddMac == true ? flow.SubmitAddAsync(where, code) : flow?.SubmitCodeAsync(code);
        card.Cancelled += () => flow?.Cancel();
        card.Rename += Rename;
        KeyPreview = true;
    }

    private string PcName => ThisPc.Load(dir).NameOr(Environment.MachineName);

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
        Log($"Connect screen: looking for {string.Join(", ", serviceTypes)}; "
            + (saved.Count == 0 ? "no Mac saved" : "saved: " + string.Join(", ", saved.Select(m => $"{m.Name} ({m.MacId}{(m.NewKey ? ", new key" : "")})"))) + ".");
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
        Log($"Connect screen: clicked {row.Name}, {row.State}{(row.Replaces is { } r ? $" (pairs again in place of {r})" : "")}.");
        switch (row.State)
        {
            case MacRow.Kind.Paired:
                flow?.Cancel();
                var targets = row.DialTargets();
                if (targets.Count == 0) { Say($"{row.Name} didn’t say where it is. Try again in a moment."); return; }
                busyRow = row.Service.Id;
                Say($"Connecting to {row.Name}…");
                Connect?.Invoke(targets, row.Name, row.MacId!);
                break;
            case MacRow.Kind.NotPaired or MacRow.Kind.OpenDoor:
                Start(row);
                break;
            case MacRow.Kind.UpdateSill:
                Say(ConnectRows.UpdateSillStatus(row.Name));
                break;
        }
    }

    // ---- pairing ----

    /// <summary>A pairing: a row's ask (<paramref name="row"/>), or Add a Mac… (null). Any pairing
    /// already under way stops first (its code withdrawn).</summary>
    private void Start(MacRow? row)
    {
        flow?.Cancel();
        try { identity ??= DeviceIdentity.LoadOrCreate(dir); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException)
        {
            Say($"This PC couldn’t make its key ({e.Message}).");
            return;
        }
        var door = new TlsPairingDoor(identity, () => PcName);
        flowRow = row;
        if (row is null)
        {
            flow = PairingFlow.AddMac(door, store);
            Log("Pairing: Add a Mac.");
        }
        else
        {
            var targets = row.DialTargets().Select(DoorAddress.Parse).OfType<DoorAddress>().ToList();
            if (targets.Count == 0) { Say($"{row.Name} didn’t say where it is. Try again in a moment."); return; }
            flow = PairingFlow.Home(door, store, row.Name, targets, row.Replaces, row.Name);
            Log($"Pairing: asking {row.Name} at {string.Join(", ", targets)}.");
        }
        var mine = flow;
        mine.Changed += () => { if (flow == mine) FlowChanged(mine); };
        if (row is null) FlowChanged(mine);
        else _ = mine.AskAsync();
    }

    private void FlowChanged(PairingFlow f)
    {
        Log($"Pairing: {f.Step}{(f.Line is { } l ? $", “{l}”" : "")}{(f.Problem is { } p ? $", problem “{p}”" : "")}.");
        switch (f.Step)
        {
            case PairingFlow.Steps.Asking:
                busyRow = flowRow?.Service.Id;
                Say(f.Line ?? "");
                break;
            case PairingFlow.Steps.Code or PairingFlow.Steps.Proving:
                if (!screen.Controls.Contains(card))
                {
                    screen.ShowCard(card);
                    card.Open(f.IsAddMac ? null : f.Mac, PcName);   // on screen first, so its field takes the focus
                }
                card.Set(f);
                busyRow = null;
                status = f.IsAddMac ? "" : f.Step == PairingFlow.Steps.Code ? PairingCopy.Showing(f.Mac) : "";
                screen.Show(rows, status, busyRow);
                break;
            case PairingFlow.Steps.Paired:
                screen.ShowCard(null);
                flow = null;
                Say(f.Line ?? "");
                var mac = f.Saved!;
                saved = LoadSaved();
                // The address the pairing reached first, then the row's others.
                var targets = new List<string> { f.Reached!.Value.ToString() };
                foreach (var t in flowRow?.DialTargets() ?? []) if (!targets.Contains(t)) targets.Add(t);
                Log($"Pairing: paired with {mac.Name} ({mac.MacId}) at {f.Reached}; connecting.");
                Connect?.Invoke(targets, mac.Name, mac.MacId);
                break;
            case PairingFlow.Steps.Ended:
                screen.ShowCard(null);
                flow = null;
                busyRow = null;
                saved = LoadSaved();
                status = f.Line ?? LookingOnNetwork;
                Refresh();
                break;
        }
    }

    private void Rename()
    {
        string current = ThisPc.Load(dir).Name ?? Environment.MachineName;
        if (RenameDialog.Ask(this, current, DeviceDpi) is not { } next) return;
        new ThisPc(next).Save(dir);
        Log($"This PC's name: “{PcName}”.");
        card.SetPcName(PcName);
    }

    /// <summary>The Macs this PC paired with (macs.json, or the spike's mac.json taken in once).</summary>
    private IReadOnlyList<KnownMac> LoadSaved() => store.Load().Select(m => m.Known).ToList();

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        flow?.Cancel();
        foreach (var b in browsers) b.Dispose();
        identity?.Dispose();
        // Where it was, for the viewer's next window (the viewer's own full screen, decoding and clipboard kept).
        if (WindowState != FormWindowState.Minimized)
        {
            var normal = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
            new WindowPlacement(normal.X, normal.Y, normal.Width, normal.Height, WindowState == FormWindowState.Maximized,
                placement?.FullScreen ?? false, placement?.SoftwareDecoding ?? false, placement?.ShareClipboard ?? true)
                .Save(Path.Combine(dir, "window.json"));
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
/// its Settings panel), Forget, or a Mac with a new key brings the connect screen back, with the
/// viewer's last words as its status line; closing either window quits.
/// </summary>
sealed class SillApp : ApplicationContext
{
    private readonly string dir;
    private readonly ViewerOptions options;
    private readonly IReadOnlyList<string> serviceTypes;

    public SillApp(string dir, IReadOnlyList<string> hosts, ViewerOptions options, IReadOnlyList<string> serviceTypes)
    {
        this.dir = dir; this.options = options; this.serviceTypes = serviceTypes;
        if (hosts.Count > 0) ShowViewer(hosts, null);
        else ShowConnect(null);
    }

    private void ShowConnect(string? status)
    {
        var form = new ConnectForm(dir, serviceTypes, status);
        (IReadOnlyList<string> Targets, string MacId)? next = null;
        form.Connect += (targets, _, macId) => { next = (targets, macId); form.Close(); };
        form.FormClosed += (_, _) =>
        {
            if (next is { } t) ShowViewer(t.Targets, t.MacId);
            else ExitThread();
        };
        form.Show();
    }

    private void ShowViewer(IReadOnlyList<string> hosts, string? macId)
    {
        var form = new ViewerForm(dir, hosts, options, macId);
        form.FormClosed += (_, _) =>
        {
            if (form.Disconnecting) ShowConnect(form.EndedWith);
            else ExitThread();
        };
        form.Show();
    }
}
