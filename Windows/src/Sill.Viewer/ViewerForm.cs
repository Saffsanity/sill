using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Text.Json;
using Sill.Media;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The Mac's Desktop, live. A worker reads the session (the spike's <see cref="SessionClient"/>)
/// and hands every frame to a video thread of the session's (each one is needed: later frames
/// refer to it). That thread decodes on the GPU (Direct3D 11) and draws the texture into
/// <see cref="VideoPanel"/>'s swap chain; without a GPU path, or once it fails, it decodes in
/// software and converts the newest picture to a bitmap only when the window has drawn the last
/// one, so a slow paint drops pictures rather than queueing them. Mouse and keys go to the Mac (kind 8): left Ctrl is
/// ⌘, right Ctrl ⌃, Alt ⌥; Alt+Tab is the Mac's ⌘Tab and the Windows key alone its Spotlight (a
/// low-level hook takes both from Windows while this window is in front). The bar on top is the
/// iPad's: Apps, the Desktop, the windows, and the Mac's gestures. F11 toggles full screen.
/// </summary>
sealed class ViewerForm : Form
{
    private readonly string dir;
    private readonly IReadOnlyList<string> hostOverrides;   // --host: dialed first, as given
    // The Mac's row on this network as this window's browsers list it (the connect screen's at
    // first), and the reconnect's wake for a click or that row listed afresh.
    private readonly List<MacBrowser> browsers = [];
    private readonly Lock rowGate = new();
    private IReadOnlyList<string> rowTargets = [];
    private TaskCompletionSource wake = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly ISavedMacs store;
    private string? macId;   // the saved Mac this window streams; null: the newest (--host)
    private readonly bool fromRow;   // opened from the connect screen's row (or a pairing): a refused pin marks it
    private readonly ViewerOptions options;
    private readonly UpdateChecker? updates;   // the app's (SillApp's), for Settings' update rows
    private readonly CancellationTokenSource stop = new();
    private readonly Lock gate = new();
    private Bitmap? front, back;
    private volatile bool paintPending;
    private long shownAt;   // when Show last asked for a paint
    private volatile int clientWidth = 1280, clientHeight = 800;
    private string status = "Connecting…";
    private string macName = "Mac";

    // Once-a-second figures for the title.
    private int framesIn, framesDecoded, picturesShown; private long bytesIn; private double decodeMs, worstDecodeMs, drawMs; private double? rtt;
    // The last whole second's figures, for ClientStats (the counters above are mid-second when it is sent).
    private int lastSecondShown; private double? lastSecondRtt;
    private string size = "";
    private volatile bool pictured;   // this session has shown a picture: the title gives figures, not the status
    private TimeSpan cpuAtLastTitle;

    // The GPU path: one device for the viewer's life, a renderer on the panel made by the first
    // session's video thread. Once the GPU path fails it stays off until the viewer restarts.
    private readonly VideoPanel panel = new();
    private GpuDevice? gpu;
    private VideoRenderer? renderer;
    private volatile bool gpuFailed, gpuShowing;
    private volatile int pictureWidth, pictureHeight;   // the shown picture's size, for the mouse
    private volatile int panelWidth = 1, panelHeight = 1;
    private IntPtr panelHandle;
    private volatile string decodePath = "";
    private Channel<VideoJob>? jobs;   // this session's, for a redraw after a resize
    private volatile string? endReason;   // why the video thread ended the session, if it did

    // Input: one writer keeps kind 8 in the order it was made; the picture's place in the window
    // turns a mouse position into the frame fraction the host expects.
    private readonly Channel<byte[]> outgoing = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions { SingleReader = true });
    private volatile bool connected;
    private Rectangle pictureRect;
    private readonly Dictionary<Keys, ushort> keysDown = [];
    private bool leftDown, rightDown;
    private long lastMoveTicks;
    private (double X, double Y) lastPointer = (-1, -1);

    // The Mac's cursor (kind 14), on the UI thread.
    private MacCursor? macCursor;

    private void SetMacCursor(MacCursor? next)
    {
        var old = macCursor;
        macCursor = next;
        if (PictureRect().Contains(PointToClient(MousePosition)))
            System.Windows.Forms.Cursor.Current = next?.Cursor ?? Cursors.Default;   // now, not at the next move
        old?.Dispose();
    }

    // The iPad's bar and Apps drawer, and what they show.
    private readonly MacBar bar = new();
    private readonly AppsDrawer drawer = new();
    private readonly StatusCard card = new();

    // The Settings panel (kinds 16 and 17): the Mac's settings with this PC's picks over them, on
    // the UI thread; a note for a pick the Mac refused or never answered.
    private readonly SettingsPanel settings = new();
    private readonly SettingsLedger ledger = new();
    private ClipboardBridge? clipboard;   // kind 32, made once the window is shown
    private readonly Stopwatch settingsClock = Stopwatch.StartNew();
    private int settingsToken;
    private string settingsNote = "";
    private double noteUntil;
    private volatile bool preferSoftware;
    private readonly WindowPlacement? placement;
    private Rectangle normalBounds;   // the last bounds of a normal window (not maximized, not full screen)

    // RestoreBounds of a borderless window leaves the frame out, so a size kept through full screen
    // would shrink by a frame each time: the normal bounds are kept as they happen instead.
    private void NoteNormalBounds()
    {
        if (WindowState == FormWindowState.Normal && FormBorderStyle != FormBorderStyle.None) normalBounds = Bounds;
    }

    protected override void OnMove(EventArgs e) { base.OnMove(e); NoteNormalBounds(); }
    private double lastRtt;
    private CancellationTokenSource? currentSession;
    private KeyboardHook? hook;
    private volatile bool desktopActive, nothingStreams;
    private long askedAt;   // when the Desktop was last asked for
    private bool cmdTab, winDown, winUsed;

    /// <summary>Closed by the Settings panel's Disconnect, not by the window's close button.</summary>
    public bool Disconnecting { get; private set; }

    // This PC's name as the Mac sees it (pc.json), read once and again after a rename.
    private string? pcName;
    private string PcName => pcName ??= ThisPc.Load(dir).NameOr(Environment.MachineName);
    /// <summary>The words the connect screen opens with after this window: a Mac with a new key, a forgotten Mac.</summary>
    public string? EndedWith { get; private set; }

    /// <param name="targets">With <paramref name="macId"/>, the addresses of the Mac's row the
    /// connect screen clicked (none for a Remote row); else each <c>--host</c>.</param>
    /// <param name="macId">The saved Mac the connect screen's row (or a pairing) chose; null for
    /// <c>--host</c>, which dials the newest saved Mac.</param>
    /// <param name="updates">The app's update check, for Settings › This PC (null when this run doesn't check).</param>
    public ViewerForm(string dir, IReadOnlyList<string> targets, ViewerOptions options, string? macId = null, UpdateChecker? updates = null)
    {
        this.dir = dir; this.options = options; this.updates = updates;
        this.macId = macId; fromRow = macId is not null;
        if (fromRow) { hostOverrides = []; rowTargets = targets; }
        else hostOverrides = targets;
        store = new SavedMacsFile(dir);
        Text = "Sill";
        BackColor = Palette.Panel;
        ClientSize = new Size(1280, 800);
        // Where it was left (window.json beside the key), if that is still on a screen.
        placement = WindowPlacement.Load(Path.Combine(dir, "window.json"));
        StartPosition = FormStartPosition.Manual;
        Bounds = WindowPlacement.Fit(placement, Screen.AllScreens.Select(s => s.WorkingArea).ToList(), Size);
        preferSoftware = options.Decoder == "software" || (options.Decoder == "auto" && placement?.SoftwareDecoding == true);
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
        KeyPreview = true;

        Controls.Add(drawer);
        Controls.Add(card);
        Controls.Add(settings);
        Controls.Add(bar);
        Controls.Add(panel);
        panel.SendToBack();   // under the bar and the drawer
        panel.Visible = false;
        bar.AppsClicked += () => { CloseSettings(); drawer.Toggle(); bar.AppsOpen = drawer.Visible; };
        bar.SettingsClicked += () =>
        {
            if (settings.Visible) { CloseSettings(); return; }
            drawer.Close();
            RefreshSettings();
            settings.Visible = true;
            settings.BringToFront();
            bar.SettingsOpen = true;
        };
        settings.Done += CloseSettings;
        settings.Disconnect += () => { Disconnecting = true; Close(); };   // back to the connect screen (SillApp)
        settings.Forget += () =>
        {
            // This PC forgets the Mac's key; the Mac lists this PC until it is removed there.
            if (macId is { } id) store.Forget(id);
            Log($"Forgot {macName} ({macId}).");
            EndedWith = $"This PC forgot {macName}. To connect again, click it and pair. {macName} lists this PC in Sill’s Settings › Devices until you remove it there.";
            Disconnecting = true;
            Close();
        };
        settings.RenamePc += () =>
        {
            CloseSettings();
            if (RenameDialog.Ask(this, ThisPc.Load(dir).Name ?? Environment.MachineName, DeviceDpi) is { } next)
            {
                new ThisPc(next).Save(dir);
                pcName = null;
                Log($"This PC's name: “{PcName}”.");
            }
            RefreshSettings();
        };
        settings.Pick += change =>
        {
            if (ledger.Pick(change, ++settingsToken, settingsClock.Elapsed.TotalSeconds) is { } send) Send(send.Encode());
            RefreshSettings();
        };
        settings.SoftwareDecoding += software =>
        {
            if (software == preferSoftware) return;
            preferSoftware = software;
            Log($"Decoding: {(software ? "software" : "GPU")}, chosen in Settings; reconnecting.");
            endReason = software ? "Switching to software decoding…" : "Switching to GPU decoding…";
            try { currentSession?.Cancel(); }   // the next session decodes the chosen way (a fresh keyframe at connect)
            catch (ObjectDisposedException) { }  // between sessions: the next one does anyway
            RefreshSettings();
        };
        settings.ShareClipboard += on => { if (clipboard is not null) clipboard.ShareOn = on; RefreshSettings(); };
        settings.UpdateAutomatic += on => { updates?.SetAutomatic(on); Log($"Update: automatic checks {(on ? "on" : "off")}."); };
        settings.CheckNow += () => updates?.CheckNow();
        settings.OpenRelease += url => { Log($"Update: opening {url.AbsoluteUri}."); AppUpdates.OpenPage(url); };
        settings.StartMenu += on =>
        {
            try
            {
                if (on) SelfInstall.AddShortcut();
                else SelfInstall.RemoveShortcut();
                Log($"Start menu shortcut {(on ? "added" : "removed")}: {SelfInstall.ShortcutPath}.");
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or COMException)
            {
                Log($"Start menu shortcut: {e.Message}");
            }
            RefreshSettings();
        };
        if (updates is not null) updates.Changed += UpdatesChanged;
        bar.DesktopClicked += () => Send(SessionMessages.SelectDesktop());
        bar.WindowClicked += id => Send(SessionMessages.SelectWindow(id));
        bar.WindowCommand += (id, action) => Send(SessionMessages.WindowCommand(id, action));
        bar.GestureClicked += gesture =>
        {
            // As the iPad does: a gesture acts on the Mac's whole screen, so the Desktop streams first.
            if (!desktopActive) Send(SessionMessages.SelectDesktop());
            Send(SessionMessages.Gesture(gesture));
        };
        drawer.Launch += bundleId => Send(SessionMessages.LaunchApp(bundleId));
        drawer.ShowWindow += id => Send(SessionMessages.SelectWindow(id));
        drawer.Closed += () => { bar.AppsOpen = false; ActiveControl = null; Focus(); };
    }

    /// <summary>Where the Mac's picture goes: the window under the bar.</summary>
    private Rectangle VideoArea => new(0, bar.Height, ClientSize.Width, Math.Max(1, ClientSize.Height - bar.Height));

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Palette.DarkTitleBar(Handle);   // the title bar in the bar's colour, as one with it
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        if (placement?.FullScreen == true) FullScreen(true);
        else if (placement?.Maximized == true) WindowState = FormWindowState.Maximized;
        Resized();
        panelHandle = panel.Handle;
        if (options.Decoder != "software")
        {
            try
            {
                gpu = new GpuDevice(options.Adapter);
                Log($"GPU: {gpu.AdapterName}.");
            }
            catch (Exception ex)
            {
                gpuFailed = true;
                Log($"No GPU path ({ex.Message}): decoding in software.");
            }
        }
        else gpuFailed = true;
        try { hook = new KeyboardHook(SystemKey); }
        catch (Exception ex) { Log($"No keyboard hook ({ex.Message}): Alt+Tab and the Windows key stay Windows'."); }
        clipboard = new ClipboardBridge(placement?.ShareClipboard ?? true, () => GetForegroundWindow() == Handle, Send, Log);
        _ = Task.Run(() => RunAsync(stop.Token));
        var timer = new System.Windows.Forms.Timer { Interval = 1000 };
        timer.Tick += (_, _) => { UpdateTitle(); PlaceCard(); SettingsTick(); };
        timer.Start();
    }

    protected override void OnResize(EventArgs e) { base.OnResize(e); NoteNormalBounds(); Resized(); Invalidate(); }
    private void Resized()
    {
        var v = VideoArea;
        clientWidth = Math.Max(1, v.Width); clientHeight = Math.Max(1, v.Height);
        panel.Bounds = v;
        if (card.Width > 0) PlaceCard();
        // The drawer floats under the bar on the left, as the iPad's: 22 pt in, 8 under, 14 above the foot.
        float s = DeviceDpi / 96f;
        drawer.Bounds = new Rectangle((int)(22 * s), v.Y + (int)(8 * s), Math.Min(drawer.CardPixels, Math.Max(1, v.Width - (int)(44 * s))),
            Math.Max(1, v.Height - (int)(22 * s)));
        PlaceSettings();
        panelWidth = Math.Max(1, panel.ClientSize.Width); panelHeight = Math.Max(1, panel.ClientSize.Height);
        jobs?.Writer.TryWrite(VideoJob.Redraw);   // a still screen sends nothing: draw the last picture at the new size
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // As it is left: the normal bounds (a maximized or full-screen window's are its RestoreBounds),
        // maximized, full screen, and how it decodes.
        bool full = FormBorderStyle == FormBorderStyle.None;
        var normal = normalBounds.IsEmpty ? Bounds : normalBounds;
        new WindowPlacement(normal.X, normal.Y, normal.Width, normal.Height, WindowState == FormWindowState.Maximized && !full, full, preferSoftware,
            clipboard?.ShareOn ?? placement?.ShareClipboard ?? true).Save(Path.Combine(dir, "window.json"));
        if (updates is not null) updates.Changed -= UpdatesChanged;
        hook?.Dispose(); clipboard?.Dispose(); stop.Cancel();
        lock (rowGate) { foreach (var b in browsers) b.Dispose(); browsers.Clear(); }
        base.OnFormClosing(e);
    }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();

    // The keys Windows keeps (the hook's callback, on the UI thread). Only while this window is in
    // front and the Apps search isn't taking keys; true keeps the key from Windows.
    private bool SystemKey(int vk, bool down, bool altDown)
    {
        const int VK_TAB = 0x09, VK_SHIFT = 0x10, VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_SPACE_HID = 0x2C, TAB_HID = 0x2B;
        if (GetForegroundWindow() != Handle || drawer.Typing || !connected)
        {
            winDown = false;
            return false;
        }
        // Alt+Tab → ⌘Tab: ⌘ held until Alt comes up, Tab (with Shift, backwards) through the apps.
        if (vk == VK_TAB && altDown)
        {
            if (down && !cmdTab)
            {
                if (keysDown.Remove(Keys.Menu, out ushort opt)) Send(InputMessages.Key(opt, false, Modifiers()));
                cmdTab = true;
                Send(InputMessages.Key(HidKeys.LeftCommand, true, InputMessages.Command));
            }
            ulong mods = InputMessages.Command | ((GetKeyState(VK_SHIFT) & 0x8000) != 0 ? InputMessages.Shift : 0);
            Send(InputMessages.Key(TAB_HID, down, mods));
            return true;
        }
        if (cmdTab && !down && vk is 0x12 or 0xA4 or 0xA5)
        {
            cmdTab = false;
            Send(InputMessages.Key(HidKeys.LeftCommand, false, 0));
            return false;   // Windows must see Alt come up, or it would think it still held
        }
        // The Windows key: alone, Spotlight (⌘Space); held with another key, ⌃ (for a terminal's ⌃C).
        if (vk is VK_LWIN or VK_RWIN)
        {
            if (down) { if (!winDown) { winDown = true; winUsed = false; } }
            else
            {
                winDown = false;
                if (winUsed)
                {
                    if (keysDown.Remove(Keys.LWin, out ushort ctl)) Send(InputMessages.Key(ctl, false, Modifiers()));
                }
                else
                {
                    Send(InputMessages.Key(HidKeys.LeftCommand, true, InputMessages.Command));
                    Send(InputMessages.Key(VK_SPACE_HID, true, InputMessages.Command));
                    Send(InputMessages.Key(VK_SPACE_HID, false, InputMessages.Command));
                    Send(InputMessages.Key(HidKeys.LeftCommand, false, 0));
                }
            }
            return true;   // both the down and the up: Windows never sees the key, so no Start menu
        }
        if (winDown && down && !winUsed)
        {
            winUsed = true;
            keysDown[Keys.LWin] = HidKeys.LeftControl;
            Send(InputMessages.Key(HidKeys.LeftControl, true, Modifiers()));
        }
        return false;
    }

    // ---- input ----

    private void Send(byte[] message) { if (connected) outgoing.Writer.TryWrite(message); }

    /// <summary>Where the Mac's picture is in the window, on either path.</summary>
    private Rectangle PictureRect()
    {
        if (!gpuShowing || pictureWidth <= 0) return pictureRect;
        var v = VideoArea;
        var (x, y, w, h) = Letterbox.Fit(pictureWidth, pictureHeight, v.Width, v.Height);
        return new Rectangle(v.X + x, v.Y + y, w, h);
    }

    private (double X, double Y) Fraction(Point p)
    {
        var r = PictureRect();
        if (r.Width <= 0 || r.Height <= 0) return (0.5, 0.5);
        return (Math.Clamp((p.X - r.X + 0.5) / r.Width, 0, 1), Math.Clamp((p.Y - r.Y + 0.5) / r.Height, 0, 1));
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var f = Fraction(e.Location);
        // At most 250 a second: a 1000 Hz mouse would send four times what the Mac can show.
        long now = Stopwatch.GetTimestamp();
        if (f == lastPointer || Stopwatch.GetElapsedTime(lastMoveTicks, now).TotalMilliseconds < 4) return;
        lastMoveTicks = now; lastPointer = f;
        Send(InputMessages.PointerEvent(InputMessages.Pointer.Move, f.X, f.Y));
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        // A click beside the open drawer closes it and clicks nothing on the Mac, as a tap does on the iPad.
        if (drawer.Visible) { drawer.Close(); return; }
        if (settings.Visible) { CloseSettings(); return; }
        // No session: a click is "try now" ("…or click it to try now"), as a tap on the iPad's row.
        if (!connected) { Wake("clicked"); return; }
        var f = Fraction(e.Location);
        Send(InputMessages.PointerEvent(InputMessages.Pointer.Move, f.X, f.Y));
        if (e.Button == MouseButtons.Left) { leftDown = true; Send(InputMessages.PointerEvent(InputMessages.Pointer.LeftDown, f.X, f.Y)); }
        if (e.Button == MouseButtons.Right) { rightDown = true; Send(InputMessages.PointerEvent(InputMessages.Pointer.RightDown, f.X, f.Y)); }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        var f = Fraction(e.Location);
        if (e.Button == MouseButtons.Left && leftDown) { leftDown = false; Send(InputMessages.PointerEvent(InputMessages.Pointer.LeftUp, f.X, f.Y)); }
        if (e.Button == MouseButtons.Right && rightDown) { rightDown = false; Send(InputMessages.PointerEvent(InputMessages.Pointer.RightUp, f.X, f.Y)); }
    }

    // A wheel notch (120) moves the content a twenty-fifth of the frame; a precision touchpad's
    // smaller deltas move it in proportion. Natural sign: a wheel turned up moves the content down.
    private const double NotchFraction = 0.04;

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        var f = Fraction(e.Location);
        Glide(0, e.Delta / 120.0 * NotchFraction, f);
    }

    // The wheel as a trackpad scroll (WheelGlide): each notch eased over ~0.1 s, a step every 16 ms,
    // so the Mac's content moves smoothly and repaints every frame instead of once a notch.
    private readonly WheelGlide glide = new();
    private readonly Lock glideGate = new();
    private readonly Stopwatch glideClock = Stopwatch.StartNew();
    private bool gliding;

    private void Glide(double dx, double dy, (double X, double Y) at)
    {
        lock (glideGate)
        {
            SendGlide(glide.Wheel(dx, dy, at.X, at.Y, glideClock.Elapsed.TotalSeconds));
            if (gliding) return;
            gliding = true;
        }
        _ = Task.Run(async () =>
        {
            using var tick = new PeriodicTimer(TimeSpan.FromMilliseconds(16));
            while (await tick.WaitForNextTickAsync())
                lock (glideGate)
                {
                    SendGlide(glide.Tick(glideClock.Elapsed.TotalSeconds));
                    if (!glide.Active) { gliding = false; return; }
                }
        });
    }

    private void FinishGlide()
    {
        lock (glideGate) SendGlide(glide.Finish());
    }

    private void SendGlide(IReadOnlyList<WheelGlide.Output> outputs)
    {
        foreach (var o in outputs)
            Send(o switch
            {
                WheelGlide.Began => InputMessages.ScrollGesture(InputMessages.ScrollPhase.Began, o.X, o.Y),
                WheelGlide.Delta d => InputMessages.Scroll(d.X, d.Y, d.Dx, d.Dy),
                _ => InputMessages.ScrollGesture(InputMessages.ScrollPhase.Ended, o.X, o.Y),
            });
    }

    protected override void WndProc(ref Message m)
    {
        const int WM_MOUSEHWHEEL = 0x020E, WM_SYSCOMMAND = 0x0112, SC_KEYMENU = 0xF100;
        if (m.Msg == WM_MOUSEHWHEEL)
        {
            int delta = (short)((long)m.WParam >> 16);
            var f = Fraction(PointToClient(new Point((short)(long)m.LParam, (short)((long)m.LParam >> 16))));
            Glide(-delta / 120.0 * NotchFraction, 0, f);   // tilted right: content moves left
            m.Result = 1;
            return;
        }
        // The cursor over the picture: Windows asks this window with the video panel named (the
        // panel lets the mouse through to here), which WinForms leaves to Windows' arrow.
        const int WM_SETCURSOR = 0x0020, HTCLIENT = 1;
        if (m.Msg == WM_SETCURSOR && ((int)m.LParam & 0xFFFF) == HTCLIENT && (m.WParam == Handle || m.WParam == panelHandle))
        {
            System.Windows.Forms.Cursor.Current = macCursor is not null && PictureRect().Contains(PointToClient(MousePosition)) ? macCursor.Cursor : Cursors.Default;
            m.Result = 1;
            return;
        }
        // Alt alone would open the window menu and take the keys from the Mac.
        if (m.Msg == WM_SYSCOMMAND && ((int)m.WParam & 0xFFF0) == SC_KEYMENU) return;
        base.WndProc(ref m);
    }

    // Every key is the Mac's, arrows and Tab included (WinForms would move focus with them).
    protected override bool IsInputKey(Keys keyData) => true;
    protected override bool ProcessDialogKey(Keys keyData) => false;

    [DllImport("user32.dll")] private static extern short GetKeyState(int virtualKey);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (drawer.Typing && e.KeyCode != Keys.F11) return;
        e.Handled = e.SuppressKeyPress = true;
        if (e.KeyCode == Keys.F11) { FullScreen(FormBorderStyle != FormBorderStyle.None); return; }
        ushort hid = e.KeyCode switch
        {
            // Left Ctrl is ⌘, so Ctrl+C copies on the Mac as it does on Windows; right Ctrl is ⌃.
            Keys.ControlKey => (GetKeyState(0xA3) & 0x8000) != 0 ? HidKeys.LeftControl : HidKeys.LeftCommand,
            Keys.ShiftKey => HidKeys.LeftShift,
            Keys.Menu => HidKeys.LeftOption,
            Keys.LWin or Keys.RWin => 0,   // Windows keeps it (the Start menu)
            _ => HidKeys.FromVirtualKey((int)e.KeyCode),
        };
        if (hid == 0) return;
        keysDown[e.KeyCode] = hid;
        Send(InputMessages.Key(hid, true, Modifiers()));
    }

    protected override void OnKeyUp(KeyEventArgs e)
    {
        base.OnKeyUp(e);
        if (drawer.Typing && !keysDown.ContainsKey(e.KeyCode)) return;
        e.Handled = e.SuppressKeyPress = true;
        if (!keysDown.Remove(e.KeyCode, out ushort hid)) return;
        Send(InputMessages.Key(hid, false, Modifiers()));
    }

    private ulong Modifiers()
    {
        ulong m = 0;
        foreach (ushort hid in keysDown.Values)
            m |= hid switch
            {
                HidKeys.LeftShift => InputMessages.Shift, HidKeys.LeftControl => InputMessages.Control,
                HidKeys.LeftOption => InputMessages.Option, HidKeys.LeftCommand => InputMessages.Command, _ => 0,
            };
        return m;
    }

    // Leaving the window (Alt+Tab, a click elsewhere) lets go of everything held, so no key or
    // button stays down on the Mac.
    protected override void OnActivated(EventArgs e) { base.OnActivated(e); clipboard?.CameToFront(); }

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        FinishGlide();
        foreach (var key in keysDown.Keys.ToList()) { ushort hid = keysDown[key]; keysDown.Remove(key); Send(InputMessages.Key(hid, false, Modifiers())); }
        var f = lastPointer.X < 0 ? (0.5, 0.5) : lastPointer;
        if (leftDown) { leftDown = false; Send(InputMessages.PointerEvent(InputMessages.Pointer.LeftUp, f.Item1, f.Item2)); }
        if (rightDown) { rightDown = false; Send(InputMessages.PointerEvent(InputMessages.Pointer.RightUp, f.Item1, f.Item2)); }
    }

    private async Task WriteInputAsync(SessionClient session, CancellationToken ct)
    {
        try
        {
            await foreach (var message in outgoing.Reader.ReadAllAsync(ct))
                await session.SendAsync(message, ct);
        }
        catch (Exception e) when (e is OperationCanceledException or IOException or ObjectDisposedException) { }
    }

    private void FullScreen(bool on)
    {
        var normal = normalBounds;
        FormBorderStyle = on ? FormBorderStyle.None : FormBorderStyle.Sizable;
        WindowState = on ? FormWindowState.Maximized : FormWindowState.Normal;
        // Windows' own restore size was taken without the frame: the remembered one, frame and all.
        if (!on && !normal.IsEmpty) Bounds = normal;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Palette.Panel);
        lock (gate)
        {
            if (front is not null)
            {
                // Letterboxed to the window, the Mac's shape kept.
                var area = VideoArea;
                float scale = Math.Min((float)area.Width / front.Width, (float)area.Height / front.Height);
                int w = (int)(front.Width * scale), h = (int)(front.Height * scale);
                g.InterpolationMode = scale >= 1 ? InterpolationMode.NearestNeighbor : InterpolationMode.Bilinear;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.CompositingMode = CompositingMode.SourceCopy;
                pictureRect = new Rectangle(area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h);
                g.DrawImage(front, pictureRect);
            }

        }
        paintPending = false;
    }

    private void UpdateTitle()
    {
        string figures;
        lock (gate)
        {
            var cpuNow = Process.GetCurrentProcess().TotalProcessorTime;
            double cpu = (cpuNow - cpuAtLastTitle).TotalSeconds * 100;   // the timer ticks once a second
            cpuAtLastTitle = cpuNow;
            figures = !pictured ? status
                : $"{size} · {decodePath} · {picturesShown} shown, {framesIn} received ({bytesIn * 8 / 1_000_000.0:0.0} Mbps) · decode {decodeMs / Math.Max(framesDecoded, 1):0.0} ms (worst {worstDecodeMs:0})"
                  + (drawMs > 0 ? $" · draw {drawMs / Math.Max(picturesShown, 1):0.0} ms" : "")
                  + $" · CPU {cpu:0}%"
                  + (rtt is { } r ? $" · rtt {r * 1000:0} ms" : "");
            if (framesIn > 0 || picturesShown > 0)
                Log($"second: {size} {decodePath}, {picturesShown} shown, {framesIn} received, decode {decodeMs / Math.Max(framesDecoded, 1):0.0} ms (worst {worstDecodeMs:0}), "
                    + $"draw {drawMs / Math.Max(picturesShown, 1):0.0} ms, CPU {cpu:0}%");
            lastSecondShown = picturesShown; lastSecondRtt = rtt;
            framesIn = framesDecoded = picturesShown = 0; bytesIn = 0; decodeMs = worstDecodeMs = drawMs = 0; rtt = null;
        }
        Text = $"{macName} — {figures}";
    }

    /// <summary>What the viewer is doing, for the title, the log and the status card (the Mac's
    /// name over it); <paramref name="busy"/> spins the card's spinner (false: nothing will change
    /// by itself).</summary>
    private void Status(string text, bool busy = true)
    {
        Log(text);
        lock (gate) status = text;
        BeginInvoke(() => { card.Set(macName, text, busy); PlaceCard(); Invalidate(); UpdateTitle(); });
    }

    // ---- the Settings panel ----

    private void RefreshSettings()
    {
        bool gpuUsable = gpu is not null && !gpuFailed;
        settings.Show(ledger, macName, settingsNote, gpuUsable, gpu?.AdapterName ?? "", preferSoftware || !gpuUsable,
            clipboard?.ShareOn ?? true, clipboard?.MacShares, PcName, macId is not null,
            new SettingsPanel.AppRows(updates?.Pane, updates?.Automatic ?? true, AppUpdates.RunsInstalled ? SelfInstall.ShortcutExists : null));
        PlaceSettings();
    }

    // A check ended or the switch changed: Settings' update rows follow while they show; a newer
    // release shown there counts as told (the connect screen offers it too).
    private void UpdatesChanged()
    {
        if (IsDisposed || updates is null || !settings.Visible) return;
        RefreshSettings();
        if (updates.UnshownOffer is { } offer) updates.NoteShown(offer);
    }

    // Hanging under the bar on the right, as the iPad's: 22 pt in, 8 under, as tall as it needs.
    private void PlaceSettings()
    {
        var v = VideoArea;
        float s = DeviceDpi / 96f;
        int width = Math.Min(settings.CardPixels, Math.Max(1, v.Width - (int)(44 * s)));
        int height = Math.Max(1, Math.Min(settings.ContentHeight, v.Height - (int)(22 * s)));
        settings.Bounds = new Rectangle(v.Right - (int)(22 * s) - width, v.Y + (int)(8 * s), width, height);
    }

    private void CloseSettings()
    {
        if (!settings.Visible) return;
        settings.Visible = false;
        bar.SettingsOpen = false;
        Focus();
    }

    private void Note(string text)
    {
        settingsNote = text;
        noteUntil = settingsClock.Elapsed.TotalSeconds + 4;
    }

    // Once a second: a pick the Mac hasn't answered in max(4 s, 4 round trips) goes back, as on the
    // iPad, and an old note goes.
    private void SettingsTick()
    {
        double now = settingsClock.Elapsed.TotalSeconds;
        bool changed = false;
        if (ledger.Expire(now, Math.Max(4, 4 * lastRtt))) { Note($"{macName} didn’t answer. Try again."); changed = true; }
        if (settingsNote.Length > 0 && now > noteUntil) { settingsNote = ""; changed = true; }
        if (changed || settings.Visible) RefreshSettings();
    }

    /// <summary>Why a dial failed, in a few words for the card (the log keeps the whole error).</summary>
    private static string Reason(Exception e)
    {
        for (var x = e; x is not null; x = x.InnerException)
            switch (x)
            {
                case OperationCanceledException: return "no answer";
                case SillTls.PinMismatchException: return "not the Mac this PC paired with";
                case System.Net.Sockets.SocketException { SocketErrorCode: System.Net.Sockets.SocketError.ConnectionRefused }: return "refused (is Sill open on it?)";
                case System.Net.Sockets.SocketException { SocketErrorCode: System.Net.Sockets.SocketError.HostNotFound or System.Net.Sockets.SocketError.NoData }: return "name not found";
                case System.Net.Sockets.SocketException { SocketErrorCode: System.Net.Sockets.SocketError.ConnectionReset }: return "closed the connection";
                case System.Security.Authentication.AuthenticationException: return "the secure connection failed";
            }
        return e is IOException ? "closed the connection" : "couldn’t connect";
    }

    // The card shows while there is no live picture: before a session's first, and after it ends.
    private void PlaceCard()
    {
        var v = VideoArea;
        card.Location = new Point(v.X + (v.Width - card.Width) / 2, v.Y + (v.Height - card.Height) / 2);
        bool show = !pictured;
        if (card.Visible != show) card.Visible = show;
        if (show) card.BringToFront();
        drawer.BringToFront();
    }

    // viewer.log beside the key: each step and every error, for when the window alone can't say.
    private readonly Lock logGate = new();
    private void Log(string line)
    {
        try { lock (logGate) File.AppendAllText(Path.Combine(dir, "viewer.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {line}{Environment.NewLine}"); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    // ---- dialing and the reconnect ----

    /// <summary>How a session ended, for <see cref="RunAsync"/>: whether it ran (its first window
    /// list came, or this viewer ended it itself), what follows, and the words for the card.</summary>
    private enum Next { Reconnect, ForGood, Stop }
    private sealed record Ending(bool Ran, Next Next, string Words);

    /// <summary>TEST ONLY: keep loopback addresses from kind 18 (a test host reached through an SSH forward).</summary>
    private static readonly bool KeepLoopback = Environment.GetEnvironmentVariable("SILL_TEST_KEEP_LOOPBACK") == "1";

    /// <summary>
    /// A dial, then the session it brings, again and again (ReconnectPolicy, the iPad's back-off):
    /// the first at once, then 5, 10, 20 and every 30 s after the last started while they don't
    /// connect, 12 at most; the card says "Reconnecting to ‹Mac›…", after 3 that it may be asleep,
    /// after 12 that this stopped. A session that ran and ended starts the count again, at once. A
    /// click on the window, or the Mac's row listed afresh on this network (Sill.app relaunched on
    /// a new port, the Mac back), dials now and starts the count again. An end that forbids it
    /// (removed, another key at Tailscale's address, a goodbye that says no reconnect) waits for a
    /// click.
    /// </summary>
    private async Task RunAsync(CancellationToken ct)
    {
        Log($"Viewer started (identity {dir}).");
        StartBrowsing();
        if ((macId is { } chosen ? store.Find(chosen) : SavedMacs.Newest(store.Load())) is { } named) macName = named.Name;   // for the first line
        var clock = Stopwatch.StartNew();
        int failed = 0;
        double? lastDialAt = null;
        string? endWords = null;   // the last session's end, shown while the first redial runs
        bool dialed = false;
        while (!ct.IsCancellationRequested)
        {
            var (dial, recheck) = ReconnectPolicy.Redial(failed, lastDialAt, clock.Elapsed.TotalSeconds);
            if (!dial)
            {
                var wait = recheck is { } at ? TimeSpan.FromSeconds(Math.Max(0, at - clock.Elapsed.TotalSeconds)) : (TimeSpan?)null;
                if (await WaitAsync(wait, ct)) { failed = 0; lastDialAt = null; }
                continue;
            }
            lock (rowGate) wake = new(TaskCreationOptions.RunContinuationsAsynchronously);
            lastDialAt = clock.Elapsed.TotalSeconds;
            string dialing = endWords ?? (dialed ? ReconnectPolicy.Line(macName, failed) : $"Connecting to {macName}…");
            dialed = true;
            var end = await SessionAsync(ct, dialing);
            if (end is null || end.Next == Next.Stop) return;
            endWords = null;
            if (end.Ran) { failed = 0; lastDialAt = null; } else failed++;
            if (end.Next == Next.ForGood)
            {
                Status(end.Words, busy: false);
                Log("Reconnect: not by itself; waiting for a click.");
                if (!await WaitAsync(null, ct)) return;
                failed = 0; lastDialAt = null;
                continue;
            }
            if (end.Ran) { endWords = end.Words; Status(end.Words); continue; }
            string line = ReconnectPolicy.Line(macName, failed);
            Status(failed >= ReconnectPolicy.QuietAfter ? line : $"{line}\n{end.Words}", busy: failed < ReconnectPolicy.Dials);
            Log($"Reconnect: {failed} dial{(failed == 1 ? "" : "s")} did not connect.");
        }
    }

    /// <summary>Waits <paramref name="delay"/> (null: until woken); true when a click or the Mac's
    /// row listed afresh woke it, false when it ran out or the window closed.</summary>
    private async Task<bool> WaitAsync(TimeSpan? delay, CancellationToken ct)
    {
        Task woken;
        lock (rowGate) woken = wake.Task;
        var done = await Task.WhenAny(woken, Task.Delay(delay ?? Timeout.InfiniteTimeSpan, ct));
        return done == woken && !ct.IsCancellationRequested;
    }

    /// <summary>A click, or the row listed afresh: the reconnect dials now.</summary>
    private void Wake(string why)
    {
        lock (rowGate) if (!wake.Task.IsCompleted) { wake.TrySetResult(); Log($"Reconnect: {why}; dialing now."); }
    }

    /// <summary>This window's own browsers (the connect screen's types), so that the reconnect
    /// dials the Mac where its row is listed now, not where it was when the window opened.</summary>
    private void StartBrowsing()
    {
        foreach (var type in options.ServiceTypes)
        {
            var b = new MacBrowser(type);
            b.Log += Log;
            b.Changed += _ => RowChanged();
            try { b.Start(); lock (rowGate) browsers.Add(b); }
            catch (Exception ex) when (ex is PlatformNotSupportedException or InvalidOperationException or DllNotFoundException)
            {
                Log($"Browse: {ex.Message}");
                b.Dispose();
            }
        }
    }

    private void RowChanged()
    {
        if (macId is not { } id || stop.IsCancellationRequested) return;
        List<FoundService> services;
        lock (rowGate) services = browsers.SelectMany(b => b.Current).ToList();
        var row = ConnectRows.Build(services, store.Load().Select(m => m.Known).ToList())
            .FirstOrDefault(r => r.State == MacRow.Kind.Paired && r.MacId == id);
        IReadOnlyList<string> next = row?.DialTargets() ?? [];
        bool fresh;
        lock (rowGate) { fresh = next.Count > 0 && !next.SequenceEqual(rowTargets); rowTargets = next; }
        if (fresh) Log($"Browse: {macName} listed on this network at {string.Join(", ", next)}.");
        if (fresh && !connected) Wake($"{macName} listed afresh");
    }

    /// <summary>One dial and the session it brings; null when trying again is pointless (no
    /// paired Mac, a bad --host).</summary>
    private async Task<Ending?> SessionAsync(CancellationToken stopping, string dialing)
    {
        var all = store.Load();
        var mac = macId is { } id ? all.FirstOrDefault(m => m.MacId == id) : SavedMacs.Newest(all);
        if (mac?.Pin is not { } pin)
        {
            macName = "Sill";
            Status(macId is null ? "This PC isn’t paired with a Mac yet. Open Sill with no arguments, and click your Mac to pair."
                                 : "This PC no longer knows this Mac. Disconnect, then click it to pair again.", busy: false);
            return null;
        }
        macId = mac.MacId;
        macName = mac.Name;
        BeginInvoke(() => drawer.SetMacName(mac.Name));
        // What to dial: each --host as given, else the Mac's row on this network as listed now; then
        // its saved addresses (kind 18's, the one the pairing reached), happy eyeballs.
        var row = new List<DoorAddress>();
        if (hostOverrides.Count > 0)
            foreach (var h in hostOverrides)
            {
                if (DoorAddress.Parse(h) is not { } d) { Status($"--host takes <address>:<port>, not {h}.", busy: false); return null; }
                row.Add(d);
            }
        else lock (rowGate) row.AddRange(rowTargets.Select(DoorAddress.Parse).OfType<DoorAddress>());
        var candidates = RemoteDialPolicy.Plan(row, mac, RemoteDialPolicy.LocalIPv4());
        Status(dialing);
        Log($"Dialing {mac.Name}: {string.Join(", ", candidates.Select(c => c.Display + (c.Row ? " (row)" : "")))}.");

        // This session's token: the watchdog cancels it when nothing has arrived for 10 s.
        using var sessionStop = CancellationTokenSource.CreateLinkedTokenSource(stopping);
        var ct = sessionStop.Token;
        using var identity = DeviceIdentity.LoadOrCreate(dir);
        var hello = new Hello(AppVersion.Current, AppVersion.Build, Hello.CurrentProtocol, $"{PcName} (Windows)");
        HappyEyeballs.Result<SessionClient> race;
        try
        {
            race = await HappyEyeballs.RaceAsync(candidates,
                (c, t) => SessionClient.ConnectAsync(c.Host, c.Port, identity, pin, hello, t),
                s => s.DisposeAsync().AsTask(), RemoteDialPolicy.Stagger, RemoteDialPolicy.AttemptTimeout, RemoteDialPolicy.WholeDial, ct);
        }
        catch (OperationCanceledException) { return new Ending(false, Next.Stop, ""); }
        foreach (var (c, e) in race.Failures) Log($"Couldn’t connect at {c.Display}: {RemoteDialPolicy.EndOf(e)} ({e.Message})");
        if (race.Winner is not { } session)
        {
            var rowFailures = race.Failures.Where(f => f.Candidate.Row).ToList();
            if (fromRow && rowFailures.Count > 0 && rowFailures.Count == candidates.Count(c => c.Row)
                && rowFailures.All(f => RemoteDialPolicy.EndOf(f.Error) == RemoteDialPolicy.End.WrongKey))
            {
                // Another key answered as this Mac at every address of its row: set up again (or a
                // look-alike holds the row). Paired again as a Mac never seen: a click on its row asks,
                // with any key, and the code the Mac shows proves it (the iPad's afterPinRefused).
                store.MarkNewKey(mac.MacId);
                string words = PairingCopy.NewKey(mac.Name);
                Log($"Pin refused at every address of {mac.Name}'s row ({mac.MacId}): marked new key.");
                Status(words, busy: false);
                EndedWith = words;
                Disconnecting = true;
                BeginInvoke(Close);
                return new Ending(false, Next.Stop, words);
            }
            var counted = race.Failures.Select(f => (f.Candidate, Failure: RemoteDialPolicy.Classify(RemoteDialPolicy.EndOf(f.Error), f.Candidate)))
                .Where(f => f.Failure is not null).ToList();
            var worst = RemoteDialPolicy.Worst(counted.Select(f => f.Failure!.Value)) ?? RemoteDialPolicy.Failure.NoAnswer;
            var at = counted.FirstOrDefault(f => f.Failure == worst).Candidate ?? candidates.FirstOrDefault();
            return new Ending(false, worst is RemoteDialPolicy.Failure.WrongMac or RemoteDialPolicy.Failure.Revoked ? Next.ForGood : Next.Reconnect,
                RemoteCopy.DialFailure(worst, mac.Name, at, RemoteCopy.VpnName(mac)));
        }
        var won = race.Won!;
        Log($"Connected at {won.Display}{(won.Row ? " (its row)" : "")}.");
        bool listed = false;   // the first window list came: the Mac admitted this PC
        Goodbye? bye = null;

        await using var connection = session;
        Status("Connected. Waiting for the picture…");
        var clock = Stopwatch.StartNew();
        long lastHeard = Stopwatch.GetTimestamp();
        _ = Task.Run(async () =>
        {
            using var watch = new PeriodicTimer(TimeSpan.FromSeconds(1));
            try
            {
                while (await watch.WaitForNextTickAsync(ct))
                    if (Stopwatch.GetElapsedTime(Interlocked.Read(ref lastHeard)).TotalSeconds > 10)
                    {
                        Log("Nothing from the Mac for 10 s: ending the session.");
                        sessionStop.Cancel();
                    }
            }
            catch (OperationCanceledException) { }
        });
        _ = PingAsync(session, clock, ct);
        _ = WriteInputAsync(session, ct);
        connected = true;
        endReason = null;
        currentSession = sessionStop;
        BeginInvoke(() => { ledger.Reset(); clipboard?.SessionChanged(); RefreshSettings(); });   // a new connection's settings come with it
        pictured = false;
        ParameterSets? ps = null;
        HevcSps? sps = null;
        bool keyed = false;
        nothingStreams = false;
        // Decoding and drawing run on a thread of their own, so the reader keeps draining the
        // socket; a few frames of slack, then the reader waits (as it did when it decoded itself),
        // which backs the Mac off rather than queueing late pictures here.
        var video = Channel.CreateBounded<VideoJob>(new BoundedChannelOptions(8) { SingleReader = true, FullMode = BoundedChannelFullMode.Wait });
        jobs = video;
        var videoThread = Task.Factory.StartNew(() => VideoLoop(video.Reader, clock, sessionStop), CancellationToken.None,
            TaskCreationOptions.LongRunning, TaskScheduler.Default);
        try
        {
            int logged = 0;
            while (await session.ReadAsync(ct) is { } m)
            {
                var (h, payload) = m;
                Interlocked.Exchange(ref lastHeard, Stopwatch.GetTimestamp());
                if (h.Kind is not (SessionKinds.Frame or SessionKinds.Pong or SessionKinds.Tick or 3 or 4 or 26) && logged++ < 40)
                    Log($"kind {h.Kind}, {payload.Length} B");
                switch (h.Kind)
                {
                    case SessionKinds.WindowList:
                        var list = SessionMessages.Decode<WindowList>(payload);
                        if (list is not null && !listed)
                        {
                            listed = true;
                            store.Connected(mac.MacId, won.Row ? null : won.Key);   // a row's port is the home door's of the moment
                        }
                        if (list is not null)
                        {
                            desktopActive = list.ActiveName == "desktop";
                            nothingStreams = list.ActiveName == "none";
                            BeginInvoke(() =>
                            {
                                bar.SetWindows(list.Windows, list.ActiveWindowId, list.ActiveName == "desktop", list.Gestures >= 1);
                                drawer.SetWindows(list.Windows, list.ActiveWindowId);
                                if (clipboard?.HostSays(list.Clipboard) == true) RefreshSettings();
                            });
                        }
                        // As the iPad does: whenever the Mac says nothing streams, ask for the Desktop.
                        // The Mac drops a pick that lands while it is still stopping another stream
                        // (a viewer closed a moment ago), so the ping loop asks again every 3 s.
                        if (list is not null && list.ActiveName == "none")
                            await AskForDesktopAsync(session, ct);
                        break;
                    case SessionKinds.ParameterSets:
                        var next = ParameterSets.Parse(payload);
                        var nextSps = next?.Sets.Select(s => HevcSps.Parse(s)).FirstOrDefault(s => s is not null);
                        if (next is null || nextSps is null) break;
                        ps = next;
                        // A new size (a pick, a resolution change): the video thread makes a decoder
                        // for it, and nothing decodes before its first keyframe.
                        if (sps != nextSps)
                        {
                            keyed = false;
                            lock (gate) size = $"{nextSps!.Width}×{nextSps.Height}";
                        }
                        sps = nextSps;
                        break;
                    case SessionKinds.Frame:
                        lock (gate) { framesIn++; bytesIn += payload.Length; }
                        if (sps is null || ps is null) break;
                        if (!keyed && !h.IsKeyframe) break;   // nothing decodes before a keyframe
                        keyed = true;
                        var nals = AccessUnit.Nals(payload, ps.NalUnitHeaderLength);
                        if (nals is null) break;
                        if (videoThread.IsCompleted) { await videoThread; throw new InvalidOperationException("The video thread stopped."); }
                        await video.Writer.WriteAsync(new VideoJob(AnnexB.Build(h.IsKeyframe ? ps : null, payload, nals), sps), ct);
                        break;
                    case SessionKinds.Thumbnail:
                        if (ImageBlobs.Thumbnail(payload) is { } thumb && LoadImage(thumb.Jpeg) is { } thumbImage)
                            BeginInvoke(() => bar.SetThumbnail(thumb.WindowId, thumbImage));
                        break;
                    case SessionKinds.AppIcon:
                        if (ImageBlobs.Icon(payload) is { } icon && LoadImage(icon.Png) is { } iconImage)
                            BeginInvoke(() => { bar.SetIcon(icon.BundleId, new Bitmap(iconImage)); drawer.SetIcon(icon.BundleId, iconImage); });
                        break;
                    case HostSettingsKinds.HostSettings:
                        if (SessionMessages.Decode<HostSettingsState>(payload) is { } hostSettings)
                            BeginInvoke(() =>
                            {
                                if (ledger.Receive(hostSettings).Count > 0) Note($"{macName} kept its setting.");
                                RefreshSettings();
                            });
                        break;
                    case SessionKinds.Clipboard:
                        BeginInvoke(() => clipboard?.Received(payload));
                        break;
                    case SessionKinds.CursorShape:
                        if (ImageBlobs.Cursor(payload) is { } shape)
                            BeginInvoke(() =>
                            {
                                var made = MacCursor.Create(shape.Png, shape.HotX, shape.HotY, shape.Width, shape.Height, DeviceDpi);
                                Log($"Mac cursor: {shape.Width}×{shape.Height} pt, hotspot {shape.HotX},{shape.HotY}" + (made is null ? ": the image didn't load" : ""));
                                SetMacCursor(made);
                            });
                        break;
                    case SessionKinds.AppList:
                        if (SessionMessages.Decode<List<AppInfo>>(payload) is { } apps)
                            BeginInvoke(() => drawer.SetApps(apps));
                        break;
                    case SessionKinds.Pong:
                        double sent = SessionMessages.PongTime(payload);
                        lock (gate) rtt = Math.Max(rtt ?? 0, clock.Elapsed.TotalSeconds - sent);
                        lastRtt = clock.Elapsed.TotalSeconds - sent;
                        break;
                    case SessionKinds.MacInfo:
                        // Who the Mac is and how to reach it from afar: kept when its signature is the
                        // key this connection is pinned to, and it is newer than the last.
                        if (SignedMacInfo.Decode(payload) is { } signed && store.TakeMacInfo(signed, mac.MacId, pin, KeepLoopback))
                            Log($"Kind 18: {mac.Name}'s addresses saved: "
                                + string.Join(", ", store.Find(mac.MacId)?.Addresses?.Select(a => $"{a.Host} ({a.Via})") ?? []) + ".");
                        break;
                    case SessionKinds.Goodbye:
                        bye = SessionMessages.Decode<Goodbye>(payload) ?? new Goodbye("");
                        Log($"The Mac said goodbye: {bye.Reason}{(bye.Message is { } said ? $", “{said}”" : "")}.");
                        break;
                }
            }
            Log("The Mac closed the session.");
        }
        catch (OperationCanceledException) when (!stopping.IsCancellationRequested)
        {
            Log(endReason ?? "Nothing heard from the Mac for 10 s.");
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { Log(e.ToString()); }
        finally
        {
            connected = false;
            jobs = null;
            video.Writer.TryComplete();
            try { await videoThread; } catch (Exception e) { Log($"Video thread: {e.Message}"); }
            // The session is over: its watchdog, pings and input writer stop with it (the watchdog
            // otherwise went on and said "Nothing from the Mac for 10 s" 10 s after any end).
            sessionStop.Cancel();
            // Only once the video thread has stopped: its last draw would set it again.
            pictured = false;
            BeginInvoke(() => { PlaceCard(); UpdateTitle(); });
            paintPending = false;
        }
        if (stopping.IsCancellationRequested) return new Ending(listed, Next.Stop, "");
        if (endReason is { } why) return new Ending(true, Next.Reconnect, why);   // this viewer's own end (decoding)
        // The Mac's words first (GoodbyePolicy); a goodbye before the first window list is a dial
        // that failed, worded as one (its notices aside).
        if (bye is not null && (listed || GoodbyePolicy.IsNotice(bye)))
        {
            var o = GoodbyePolicy.For(bye, macName);
            return new Ending(listed, o.Reconnect ? Next.Reconnect : Next.ForGood, o.Text);
        }
        if (bye is not null)
        {
            var f = RemoteDialPolicy.Classify(bye.Reason);
            return new Ending(false, GoodbyePolicy.For(bye, macName).Reconnect && f != RemoteDialPolicy.Failure.Revoked ? Next.Reconnect : Next.ForGood,
                RemoteCopy.DialFailure(f, macName, won, RemoteCopy.VpnName(mac)));
        }
        if (!listed) return new Ending(false, Next.Reconnect, RemoteCopy.DialFailure(RemoteDialPolicy.Failure.NoAnswer, macName, won, RemoteCopy.VpnName(mac)));
        return new Ending(true, Next.Reconnect, GoodbyePolicy.For(null, macName).Text);
    }

    /// <summary>A frame for the video thread (Annex B, the SPS it belongs to), or a redraw.</summary>
    private sealed record VideoJob(byte[]? AnnexB, HevcSps? Sps)
    {
        public static readonly VideoJob Redraw = new(null, null);
    }

    // The session's video thread: decodes every frame in order (each is needed, later frames refer
    // to it) and draws the newest picture. On the GPU: decode to a texture, the video processor
    // into the panel's swap chain, present. In software: as before, a bitmap the form paints. A GPU
    // failure ends the session; the next one decodes in software (a fresh keyframe at connect).
    private void VideoLoop(ChannelReader<VideoJob> reader, Stopwatch clock, CancellationTokenSource sessionStop)
    {
        HevcDecoder? decoder = null;
        GpuPicture? last = null;
        int pictures = 0, gpuPictures = 0;
        int failAfter = int.TryParse(Environment.GetEnvironmentVariable("SILL_TEST_GPU_FAIL_AFTER"), out int n) ? n : -1;
        try
        {
            while (reader.WaitToReadAsync().AsTask().GetAwaiter().GetResult())
            {
                if (!reader.TryRead(out var job)) continue;
                try
                {
                    if (job.AnnexB is null)
                    {
                        if (last is not null && decoder is not null) Draw(last, decoder.Sps);
                        continue;
                    }
                    var sps = job.Sps!;
                    if (decoder is null || decoder.Sps != sps)
                    {
                        last?.Dispose(); last = null;
                        renderer?.ClearInputViews();
                        decoder?.Dispose(); decoder = null;
                        decoder = MakeDecoder(sps);
                    }
                    var t0 = clock.Elapsed.TotalMilliseconds;
                    if (decoder.OnGpu)
                    {
                        var picture = decoder.PushGpu(job.AnnexB);
                        Decoded(clock.Elapsed.TotalMilliseconds - t0);
                        if (picture is null) continue;
                        if (failAfter >= 0 && ++gpuPictures > failAfter)
                        {
                            picture.Dispose();
                            throw new COMException("SILL_TEST_GPU_FAIL_AFTER: a device lost, as a test", unchecked((int)0x887A0005));
                        }
                        last?.Dispose();
                        last = picture;
                        if (pictures++ == 0) Log($"First picture after {clock.Elapsed.TotalSeconds:0.00} s (GPU).");
                        Draw(picture, sps);
                    }
                    else
                    {
                        var picture = decoder.Push(job.AnnexB);
                        double took = clock.Elapsed.TotalMilliseconds - t0;
                        Decoded(took);
                        if (picture is not null && pictures++ == 0) Log($"First picture after {clock.Elapsed.TotalSeconds:0.00} s ({took:0} ms to decode, software).");
                        if (picture is not null && (!paintPending || Stopwatch.GetElapsedTime(Interlocked.Read(ref shownAt)).TotalMilliseconds > 500))
                            Show(picture, sps);
                    }
                }
                catch (Exception e) when (decoder?.OnGpu == true)
                {
                    gpuFailed = true;
                    Log($"GPU path failed: {e}");
                    endReason = $"The GPU path failed ({e.Message}); reconnecting with software decoding…";
                    BeginInvoke(() => { panel.Visible = false; gpuShowing = false; Invalidate(); });
                    sessionStop.Cancel();
                    return;
                }
            }
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            Log($"Video thread ended: {e}");
            endReason = $"Decoding failed ({e.Message}). Reconnecting…";
            sessionStop.Cancel();
        }
        finally
        {
            last?.Dispose();
            decoder?.Dispose();
        }
    }

    private HevcDecoder MakeDecoder(HevcSps sps)
    {
        if (gpu is not null && !gpuFailed && !preferSoftware)
        {
            try
            {
                var onGpu = new HevcDecoder(sps, null, gpu);
                decodePath = $"GPU ({gpu.AdapterName})";
                Log($"Decoder {onGpu.Name} on the GPU ({gpu.AdapterName}) for {sps.Width}×{sps.Height} (coded {sps.CodedWidth}×{sps.CodedHeight}).");
                return onGpu;
            }
            catch (Exception e)
            {
                gpuFailed = true;
                Log($"The GPU decoder refused ({e.Message}): decoding in software.");
            }
        }
        var decoder = new HevcDecoder(sps);
        decodePath = "software";
        // The form paints software pictures: the GPU's panel, if it showed, would cover them.
        if (gpuShowing) { gpuShowing = false; BeginInvoke(() => { panel.Visible = false; Invalidate(); }); }
        Log($"Decoder {decoder.Name} in software for {sps.Width}×{sps.Height} (coded {sps.CodedWidth}×{sps.CodedHeight}).");
        return decoder;
    }

    private void Decoded(double ms)
    {
        lock (gate) { framesDecoded++; decodeMs += ms; worstDecodeMs = Math.Max(worstDecodeMs, ms); }
    }

    // On the video thread: the picture into the panel's swap chain, letterboxed.
    private void Draw(GpuPicture picture, HevcSps sps)
    {
        var t0 = Stopwatch.GetTimestamp();
        renderer ??= new VideoRenderer(gpu!, panelHandle, panelWidth, panelHeight) { Background = Palette.Panel };
        renderer.Resize(panelWidth, panelHeight);
        int width = Math.Min(sps.Width, picture.Width - sps.Left), height = Math.Min(sps.Height, picture.Height - sps.Top);
        renderer.Draw(picture, (sps.Left, sps.Top, width, height));
        pictureWidth = width; pictureHeight = height;
        lock (gate) { picturesShown++; drawMs += Stopwatch.GetElapsedTime(t0).TotalMilliseconds; }
        if (!pictured) { pictured = true; BeginInvoke(PlaceCard); }
        if (!gpuShowing)
        {
            gpuShowing = true;
            BeginInvoke(() => { panel.Visible = true; });
        }
    }

    // A JPEG or PNG from the Mac as a bitmap of its own (Image.FromStream keeps its stream).
    private static Bitmap? LoadImage(byte[] bytes)
    {
        try
        {
            using var ms = new MemoryStream(bytes);
            using var img = Image.FromStream(ms);
            return new Bitmap(img);
        }
        catch (ArgumentException) { return null; }
        catch (ExternalException) { return null; }
    }

    // The newest picture to the back bitmap, sampled down to about the window's size, then swapped
    // in front. Only while no paint is pending, so the worker never writes a bitmap being drawn.
    private unsafe void Show(HevcDecoder.Picture p, HevcSps sps)
    {
        int width = Math.Min(sps.Width, p.Width - sps.Left), height = Math.Min(sps.Height, p.Height - sps.Top);
        int step = Math.Max(1, Math.Min(width / clientWidth, height / clientHeight));
        int outW = width / step, outH = height / step;
        if (back is null || back.Width != outW || back.Height != outH) { back?.Dispose(); back = new Bitmap(outW, outH, PixelFormat.Format32bppRgb); }
        var data = back.LockBits(new Rectangle(0, 0, outW, outH), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
        try
        {
            Bgra.FromNv12(p.Nv12, p.Stride, p.PlaneHeight, sps.Left, sps.Top, width, height, step, p.FullRange, p.Bt601,
                (byte*)data.Scan0, data.Stride);
        }
        finally { back.UnlockBits(data); }
        lock (gate)
        {
            (front, back) = (back, front);
            picturesShown++;
        }
        if (!pictured) { pictured = true; BeginInvoke(PlaceCard); }
        paintPending = true;
        Interlocked.Exchange(ref shownAt, Stopwatch.GetTimestamp());
        BeginInvoke(Invalidate);
    }

    private async Task AskForDesktopAsync(SessionClient session, CancellationToken ct)
    {
        Interlocked.Exchange(ref askedAt, Stopwatch.GetTimestamp());
        await session.SendAsync(SessionMessages.SelectDesktop(), ct);
        Log("Asked for the Desktop.");
    }

    // A ping a second (its pong gives the round trip) and ClientStats, so the Mac's log names us.
    private async Task PingAsync(SessionClient session, Stopwatch clock, CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        try
        {
            do
            {
                await session.SendAsync(SessionMessages.Ping(clock.Elapsed.TotalSeconds), ct);
                if (nothingStreams && Stopwatch.GetElapsedTime(Interlocked.Read(ref askedAt)).TotalSeconds >= 3)
                    await AskForDesktopAsync(session, ct);
                int shown; double? lastRtt;
                lock (gate) { shown = lastSecondShown; lastRtt = lastSecondRtt; }
                int rttMs = lastRtt is { } r ? (int)Math.Round(r * 1000) : -1;
                var stats = JsonSerializer.SerializeToUtf8Bytes(new { fps = shown, frameAgeMs = -1, rttMs, device = $"{PcName} (Windows)", rttMaxMs = rttMs });
                await session.SendAsync(StreamHeader.Serialize(SessionKinds.ClientStats, 0, false, stats), ct);
            }
            while (await timer.WaitForNextTickAsync(ct));
        }
        catch (Exception e) when (e is OperationCanceledException or IOException or ObjectDisposedException) { }
    }
}
