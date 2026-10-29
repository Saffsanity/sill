using System.Diagnostics;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The window the viewer opens on when no <c>--host</c> is given: the <see cref="ConnectScreen"/>
/// over a <see cref="MacBrowser"/> per service type. A paired Mac's row connects at the addresses
/// and port the browser resolved (<see cref="Connect"/>, which <see cref="SillApp"/> turns into a
/// <see cref="ViewerForm"/>, pinned to the saved key), and its saved addresses after them. Once the
/// network has had 3 s, each saved Mac it doesn't list is a Remote row (<see cref="RemoteRows"/>),
/// which connects at its saved addresses alone: away from home, through Tailscale. A "Not paired" row asks its Mac for its code
/// and Add a Mac… takes a link or an address and a code, both through a <see cref="PairingFlow"/>
/// shown as a <see cref="PairCard"/>; a pairing connects at once. Opened at the start of a run, it
/// clicks the Mac this PC connected to last by itself once its row is there (<see cref="LaunchDial"/>),
/// unless another click comes first.
/// </summary>
sealed class ConnectForm : Form
{
    /// <summary>A Mac to connect to: the addresses to dial (<c>host:port</c>, in order), its name, its
    /// Mac ID, and whether it is the start's own dial (one try: back here if it doesn't connect).</summary>
    public event Action<IReadOnlyList<string>, string, string, bool>? Connect;

    public const string LookingOnNetwork = "Looking for Macs on this network";

    private readonly string dir;
    private readonly ConnectScreen screen = new() { Dock = DockStyle.Fill };
    private readonly List<MacBrowser> browsers = [];
    private readonly IReadOnlyList<string> serviceTypes;
    private readonly Stopwatch since = Stopwatch.StartNew();
    private readonly WindowPlacement? placement;
    private readonly ISavedMacs store;
    private readonly PairCard card = new();
    private readonly UpdateChecker? updates;
    private DeviceIdentity? identity;
    private PairingFlow? flow;
    private MacRow? flowRow;
    private IReadOnlyList<SavedMac> saved = [];
    private readonly System.Windows.Forms.Timer grace = new() { Interval = (int)(RemoteRows.NetworkFirst * 1000) + 50 };
    private IReadOnlyList<MacRow> rows = [];
    private string status;
    private string? busyRow;
    private bool listedOnce;
    private SavedMac? launchMac;   // the start's own dial, until its row is clicked or another click comes
    private readonly bool atLaunch;
    private readonly System.Windows.Forms.Timer launchWait = new() { Interval = (int)((RemoteRows.NetworkFirst + 1) * 1000) + 50 };

    /// <param name="status">The status line to open with (a session's end: a Mac with a new key, a
    /// forgotten Mac); null for "Looking for Macs on this network".</param>
    /// <param name="updates">The app's update check (null when this run doesn't check): a newer
    /// release shows as "Sill 0.6 Is Available…" above the footer.</param>
    /// <param name="atLaunch">The run's first window: dial the Mac connected to last by itself.</param>
    public ConnectForm(string dir, IReadOnlyList<string> serviceTypes, string? status = null, UpdateChecker? updates = null, bool atLaunch = false)
    {
        this.dir = dir; this.serviceTypes = serviceTypes; this.updates = updates; this.atLaunch = atLaunch;
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
        screen.UpdateClicked += offer => { Log($"Update: opening the release page of Sill {offer.Version}."); AppUpdates.OpenPage(offer.Url); };
        if (updates is not null) updates.Changed += UpdatesChanged;
        card.Pair += (where, code) => _ = flow?.IsAddMac == true ? flow.SubmitAddAsync(where, code) : flow?.SubmitCodeAsync(code);
        card.Cancelled += () => flow?.Cancel();
        card.Rename += Rename;
        grace.Tick += (_, _) => { grace.Stop(); Refresh(); };   // the Remote rows, once the network has had its seconds
        launchWait.Tick += (_, _) => { launchWait.Stop(); Refresh(); };   // the start's dial gives up waiting for a row
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
            + (saved.Count == 0 ? "no Mac saved" : "saved: " + string.Join(", ", saved.Select(m => $"{m.Name} ({m.MacId}{(m.NewKey == true ? ", new key" : "")}, "
                + $"{m.Addresses?.Count ?? 0} addresses from kind 18)"))) + ".");
        if (atLaunch && LaunchDial.Mac(saved) is { } last)
        {
            launchMac = last;
            status = $"Connecting to {last.Name}…";
            launchWait.Start();
            Log($"Connect at launch: {last.Name} ({last.MacId}), last connected {last.LastConnectedAt!.Value.ToLocalTime():yyyy-MM-dd HH:mm}; waiting for its row.");
        }
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
        grace.Start();
        UpdatesChanged();
        Refresh();
    }

    /// <summary>The offer, as Sill.app's menu item: shown for as long as a newer release is out.</summary>
    private void UpdatesChanged()
    {
        if (IsDisposed || updates is null) return;
        var offer = updates.Offer;
        screen.ShowUpdate(offer, updates.Running);
        if (offer is not null && updates.UnshownOffer is not null)
        {
            updates.NoteShown(offer);
            Log($"Update: Sill {offer.Version} is available; offered on the connect screen.");
        }
    }

    private new void Refresh()
    {
        if (IsDisposed) return;
        var listed = ConnectRows.Build(browsers.SelectMany(b => b.Current), saved.Select(m => m.Known).ToList());
        rows = [.. listed, .. RemoteRows.Build(saved, listed, since.Elapsed.TotalSeconds)];
        if (rows.Count > 0 && !listedOnce)
        {
            listedOnce = true;
            Log($"Connect screen: first Mac listed {since.Elapsed.TotalSeconds:0.00} s after the browse began.");
        }
        Log($"Connect screen: {(rows.Count == 0 ? "no Macs" : string.Join("; ", rows.Select(r => $"{r.Name} ({r.Service.ServiceType}): {r.State}, {r.Word ?? "no word"}")))} "
            + $"at {since.Elapsed.TotalSeconds:0.00} s.");
        if (busyRow is not null && rows.All(r => r.Key != busyRow)) busyRow = null;
        screen.Show(rows, status, busyRow);
        if (launchMac is { } mac)
        {
            if (LaunchDial.Row(mac.MacId, rows) is { } row)
            {
                Log($"Connect at launch: dialing {row.Name} ({row.State}) at {since.Elapsed.TotalSeconds:0.00} s.");
                Dial(row, once: true);
            }
            else if (LaunchDial.GivesUp(mac.MacId, rows, since.Elapsed.TotalSeconds))
            {
                launchMac = null;
                Log($"Connect at launch: no row to dial for {mac.Name}; waiting for a click.");
                Say(LookingOnNetwork);
            }
        }
    }

    private void Say(string line)
    {
        status = line;
        screen.Show(rows, status, busyRow);
    }

    private void Clicked(MacRow row)
    {
        Log($"Connect screen: clicked {row.Name}, {row.State}{(row.Replaces is { } r ? $" (pairs again in place of {r})" : "")}.");
        Dial(row, once: false);
    }

    /// <summary>A row clicked, by the person or by the start's own dial (<paramref name="once"/>).
    /// Either way the start's dial is over.</summary>
    private void Dial(MacRow row, bool once)
    {
        launchMac = null;
        launchWait.Stop();
        switch (row.State)
        {
            case MacRow.Kind.Paired:
                flow?.Cancel();
                var targets = row.DialTargets();
                if (targets.Count == 0) { Say($"{row.Name} didn’t say where it is. Try again in a moment."); return; }
                busyRow = row.Key;
                Say($"Connecting to {row.Name}…");
                Connect?.Invoke(targets, row.Name, row.MacId!, once);
                break;
            case MacRow.Kind.NotPaired or MacRow.Kind.OpenDoor:
                Start(row);
                break;
            case MacRow.Kind.UpdateSill:
                Say(ConnectRows.UpdateSillStatus(row.Name));
                break;
            case MacRow.Kind.Remote:
                flow?.Cancel();
                busyRow = row.Key;
                Say($"Connecting to {row.Name} remotely…");
                Connect?.Invoke([], row.Name, row.MacId!, once);   // the viewer dials its saved addresses
                break;
        }
    }

    // ---- pairing ----

    /// <summary>A pairing: a row's ask (<paramref name="row"/>), or Add a Mac… (null). Any pairing
    /// already under way stops first (its code withdrawn).</summary>
    private void Start(MacRow? row)
    {
        flow?.Cancel();
        if (launchMac is not null) { launchMac = null; launchWait.Stop(); Log("Connect at launch: called off by a click."); }
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
                busyRow = flowRow?.Key;
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
                Connect?.Invoke(targets, mac.Name, mac.MacId, false);
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
    private IReadOnlyList<SavedMac> LoadSaved() => store.Load();

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        flow?.Cancel();
        if (updates is not null) updates.Changed -= UpdatesChanged;
        grace.Dispose();
        launchWait.Dispose();
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
/// viewer's last words as its status line; closing either window quits. The app's one update check
/// (<see cref="AppUpdates"/>) lives here for the whole run, whichever window shows, and goes with
/// the app.
/// </summary>
sealed class SillApp : ApplicationContext
{
    private readonly string dir;
    private readonly ViewerOptions options;
    private readonly UpdateChecker? updates;

    public SillApp(string dir, IReadOnlyList<string> hosts, ViewerOptions options)
    {
        this.dir = dir; this.options = options;
        // The UI thread's context, so the checker's Changed comes on it (WinForms would install it
        // with the first control; the checker starts before any).
        if (SynchronizationContext.Current is not WindowsFormsSynchronizationContext)
            SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
        updates = AppUpdates.Create(SynchronizationContext.Current);
        if (updates is not null) Microsoft.Win32.SystemEvents.PowerModeChanged += Woke;
        if (hosts.Count > 0) ShowViewer(hosts, null);
        else ShowConnect(null, atLaunch: true);
    }

    // Timers may not have counted the sleep: the next check is worked out again.
    private void Woke(object? sender, Microsoft.Win32.PowerModeChangedEventArgs e)
    {
        if (e.Mode == Microsoft.Win32.PowerModes.Resume) updates?.SystemDidWake();
    }

    protected override void ExitThreadCore()
    {
        if (updates is not null)
        {
            Microsoft.Win32.SystemEvents.PowerModeChanged -= Woke;
            updates.Dispose();
        }
        base.ExitThreadCore();
    }

    private void ShowConnect(string? status, bool atLaunch = false)
    {
        var form = new ConnectForm(dir, options.ServiceTypes, status, updates, atLaunch);
        (IReadOnlyList<string> Targets, string MacId, bool Once)? next = null;
        form.Connect += (targets, _, macId, once) => { next = (targets, macId, once); form.Close(); };
        form.FormClosed += (_, _) =>
        {
            if (next is { } t) ShowViewer(t.Targets, t.MacId, t.Once);
            else ExitThread();
        };
        form.Show();
    }

    private void ShowViewer(IReadOnlyList<string> hosts, string? macId, bool once = false)
    {
        var form = new ViewerForm(dir, hosts, options, macId, updates, once);
        form.FormClosed += (_, _) =>
        {
            if (form.Disconnecting) ShowConnect(form.EndedWith);
            else ExitThread();
        };
        form.Show();
    }
}
