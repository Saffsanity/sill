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
/// The Mac's Desktop, live. A worker reads the session (the spike's <see cref="SessionClient"/>),
/// feeds every frame to the decoder (each one is needed: later frames refer to it), and converts
/// the newest picture to a bitmap only when the window has drawn the last one, so a slow paint
/// drops pictures rather than queueing them. Mouse and keys go to the Mac (kind 8): left Ctrl is
/// ⌘, right Ctrl ⌃, Alt ⌥; Alt+Tab is the Mac's ⌘Tab and the Windows key alone its Spotlight (a
/// low-level hook takes both from Windows while this window is in front). The bar on top is the
/// iPad's: Apps, the Desktop, the windows, and the Mac's gestures. F11 toggles full screen.
/// </summary>
sealed class ViewerForm : Form
{
    private sealed record SavedMac(string Fingerprint, string MacId, string Name, string RecognitionKey, string Host, int Port);

    private readonly string dir;
    private readonly IReadOnlyList<string> hostOverrides;
    private readonly CancellationTokenSource stop = new();
    private readonly Lock gate = new();
    private Bitmap? front, back;
    private volatile bool paintPending;
    private long shownAt;   // when Show last asked for a paint
    private volatile int clientWidth = 1280, clientHeight = 800;
    private string status = "Connecting…";
    private string macName = "Mac";

    // Once-a-second figures for the title.
    private int framesIn, picturesShown; private long bytesIn; private double decodeMs, worstDecodeMs; private double? rtt;
    private string size = "";

    // Input: one writer keeps kind 8 in the order it was made; the picture's place in the window
    // turns a mouse position into the frame fraction the host expects.
    private readonly Channel<byte[]> outgoing = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions { SingleReader = true });
    private volatile bool connected;
    private Rectangle pictureRect;
    private readonly Dictionary<Keys, ushort> keysDown = [];
    private bool leftDown, rightDown;
    private long lastMoveTicks;
    private (double X, double Y) lastPointer = (-1, -1);

    // The iPad's bar and Apps drawer, and what they show.
    private readonly MacBar bar = new();
    private readonly AppsDrawer drawer = new();
    private KeyboardHook? hook;
    private volatile bool desktopActive, nothingStreams;
    private long askedAt;   // when the Desktop was last asked for
    private bool cmdTab, winDown, winUsed;

    public ViewerForm(string dir, IReadOnlyList<string> hostOverrides)
    {
        this.dir = dir; this.hostOverrides = hostOverrides;
        Text = "Sill Viewer";
        BackColor = Color.Black;
        ClientSize = new Size(1280, 800);
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
        KeyPreview = true;

        Controls.Add(drawer);
        Controls.Add(bar);
        bar.AppsClicked += () => drawer.Toggle();
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
        drawer.Closed += () => { ActiveControl = null; Focus(); };
    }

    /// <summary>Where the Mac's picture goes: the window under the bar.</summary>
    private Rectangle VideoArea => new(0, bar.Height, ClientSize.Width, Math.Max(1, ClientSize.Height - bar.Height));

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Resized();
        try { hook = new KeyboardHook(SystemKey); }
        catch (Exception ex) { Log($"No keyboard hook ({ex.Message}): Alt+Tab and the Windows key stay Windows'."); }
        _ = Task.Run(() => RunAsync(stop.Token));
        var timer = new System.Windows.Forms.Timer { Interval = 1000 };
        timer.Tick += (_, _) => UpdateTitle();
        timer.Start();
    }

    protected override void OnResize(EventArgs e) { base.OnResize(e); Resized(); Invalidate(); }
    private void Resized() { var v = VideoArea; clientWidth = Math.Max(1, v.Width); clientHeight = Math.Max(1, v.Height); }

    protected override void OnFormClosing(FormClosingEventArgs e) { hook?.Dispose(); stop.Cancel(); base.OnFormClosing(e); }

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

    private (double X, double Y) Fraction(Point p)
    {
        var r = pictureRect;
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
        Send(InputMessages.Scroll(f.X, f.Y, 0, e.Delta / 120.0 * NotchFraction));
    }

    protected override void WndProc(ref Message m)
    {
        const int WM_MOUSEHWHEEL = 0x020E, WM_SYSCOMMAND = 0x0112, SC_KEYMENU = 0xF100;
        if (m.Msg == WM_MOUSEHWHEEL)
        {
            int delta = (short)((long)m.WParam >> 16);
            var f = Fraction(PointToClient(new Point((short)(long)m.LParam, (short)((long)m.LParam >> 16))));
            Send(InputMessages.Scroll(f.X, f.Y, -delta / 120.0 * NotchFraction, 0));   // tilted right: content moves left
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
    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
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
        FormBorderStyle = on ? FormBorderStyle.None : FormBorderStyle.Sizable;
        WindowState = on ? FormWindowState.Maximized : FormWindowState.Normal;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Color.Black);
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
            else
            {
                TextRenderer.DrawText(g, status, Font, VideoArea, Color.Gainsboro,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
            }
        }
        paintPending = false;
    }

    private void UpdateTitle()
    {
        string figures;
        lock (gate)
        {
            figures = framesIn == 0 && picturesShown == 0 ? status
                : $"{size} · {picturesShown} shown, {framesIn} received ({bytesIn * 8 / 1_000_000.0:0.0} Mbps) · decode {decodeMs / Math.Max(framesIn, 1):0} ms (worst {worstDecodeMs:0})"
                  + (rtt is { } r ? $" · rtt {r * 1000:0} ms" : "");
            framesIn = picturesShown = 0; bytesIn = 0; decodeMs = worstDecodeMs = 0; rtt = null;
        }
        Text = $"{macName} — {figures}";
    }

    private void Status(string text)
    {
        Log(text);
        lock (gate) status = text;
        BeginInvoke(() => { Invalidate(); UpdateTitle(); });
    }

    // viewer.log beside the key: each step and every error, for when the window alone can't say.
    private readonly Lock logGate = new();
    private void Log(string line)
    {
        try { lock (logGate) File.AppendAllText(Path.Combine(dir, "viewer.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {line}{Environment.NewLine}"); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    // A session at a time; when one ends (the Mac gone, a restart, silence) the next starts 2 s later.
    private async Task RunAsync(CancellationToken ct)
    {
        Log($"Viewer started (identity {dir}).");
        while (!ct.IsCancellationRequested)
        {
            if (!await SessionAsync(ct)) return;
            try { await Task.Delay(TimeSpan.FromSeconds(2), ct); } catch (OperationCanceledException) { return; }
        }
    }

    /// <summary>One session; false when trying again is pointless (no paired Mac, a bad --host).</summary>
    private async Task<bool> SessionAsync(CancellationToken stopping)
    {
        SavedMac? mac;
        byte[]? pin;
        try
        {
            mac = JsonSerializer.Deserialize<SavedMac>(File.ReadAllText(Path.Combine(dir, "mac.json")));
            pin = mac is null ? null : Base64Url.Decode(mac.Fingerprint);
            if (mac is null || pin is not { Length: 32 }) throw new InvalidDataException("mac.json is not a saved Mac.");
        }
        catch (Exception e) when (e is IOException or JsonException or InvalidDataException or UnauthorizedAccessException)
        {
            Status($"No paired Mac in {dir}: pair first with Sill.Spike pair.\n({e.Message})");
            return false;
        }
        macName = mac.Name;
        // The addresses to dial, in order: each --host, else the one saved at pairing.
        var targets = new List<(string Host, int Port)>();
        foreach (var h in hostOverrides.Count > 0 ? hostOverrides : [$"{mac.Host}:{mac.Port}"])
        {
            int colon = h.LastIndexOf(':');
            if (colon <= 0 || !int.TryParse(h[(colon + 1)..], out int p)) { Status($"--host takes <address>:<port>, not {h}."); return false; }
            targets.Add((h[..colon].Trim('[', ']'), p));
        }

        // This session's token: the watchdog cancels it when nothing has arrived for 10 s.
        using var sessionStop = CancellationTokenSource.CreateLinkedTokenSource(stopping);
        var ct = sessionStop.Token;
        SessionClient? session = null;
        string host = "", tried = "";
        foreach (var (h, p) in targets)
        {
            Status($"Connecting to {mac.Name} at {h}:{p}…");
            using var dial = CancellationTokenSource.CreateLinkedTokenSource(ct);
            dial.CancelAfter(TimeSpan.FromSeconds(targets.Count > 1 ? 4 : 15));   // an address that isn't there now (away from home) gives way
            try
            {
                session = await SessionClient.ConnectAsync(h, p, DeviceIdentity.LoadOrCreate(dir), pin,
                    new Hello("0.1", "viewer", Hello.CurrentProtocol, $"{Environment.MachineName} (Windows)"), dial.Token);
                host = $"{h}:{p}";
                break;
            }
            catch (Exception e) when (!stopping.IsCancellationRequested)
            {
                tried += $"\n{h}:{p}: {(e is OperationCanceledException ? "no answer" : e.Message)}";
                Log($"Couldn’t connect at {h}:{p}: {e.Message}");
            }
        }
        if (session is null)
        {
            Status($"Couldn’t reach {mac.Name}. Trying again…{tried}");
            return true;
        }
        Log($"Connected at {host}.");

        await using var connection = session;
        Status($"Connected to {mac.Name}. Waiting for the picture…");
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
        HevcDecoder? decoder = null;
        ParameterSets? ps = null;
        bool keyed = false;
        nothingStreams = false;
        int pictures = 0;
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
                        if (list is not null)
                        {
                            desktopActive = list.ActiveName == "desktop";
                            nothingStreams = list.ActiveName == "none";
                            BeginInvoke(() => bar.SetWindows(list.Windows, list.ActiveWindowId, list.ActiveName == "desktop", list.Gestures >= 1));
                        }
                        // As the iPad does: whenever the Mac says nothing streams, ask for the Desktop.
                        // The Mac drops a pick that lands while it is still stopping another stream
                        // (a viewer closed a moment ago), so the ping loop asks again every 3 s.
                        if (list is not null && list.ActiveName == "none")
                            await AskForDesktopAsync(session, ct);
                        break;
                    case SessionKinds.ParameterSets:
                        var next = ParameterSets.Parse(payload);
                        var sps = next?.Sets.Select(s => HevcSps.Parse(s)).FirstOrDefault(s => s is not null);
                        if (next is null || sps is null) break;
                        ps = next;
                        // A new size (a pick, a resolution change) needs a decoder made for it.
                        if (decoder is null || decoder.Sps != sps)
                        {
                            decoder?.Dispose();
                            decoder = new HevcDecoder(sps);
                            Log($"Decoder {decoder.Name} for {sps.Width}×{sps.Height} (coded {sps.CodedWidth}×{sps.CodedHeight}).");
                            keyed = false;
                            lock (gate) size = $"{sps.Width}×{sps.Height}";
                        }
                        break;
                    case SessionKinds.Frame:
                        lock (gate) { framesIn++; bytesIn += payload.Length; }
                        if (decoder is null || ps is null) break;
                        if (!keyed && !h.IsKeyframe) break;   // nothing decodes before a keyframe
                        keyed = true;
                        var nals = AccessUnit.Nals(payload, ps.NalUnitHeaderLength);
                        if (nals is null) break;
                        var t0 = clock.Elapsed.TotalMilliseconds;
                        var picture = decoder.Push(AnnexB.Build(h.IsKeyframe ? ps : null, payload, nals));
                        double took = clock.Elapsed.TotalMilliseconds - t0;
                        lock (gate) { decodeMs += took; worstDecodeMs = Math.Max(worstDecodeMs, took); }
                        if (picture is not null && pictures++ == 0) Log($"First picture after {clock.Elapsed.TotalSeconds:0.00} s ({took:0} ms to decode).");
                        if (picture is not null && (!paintPending || Stopwatch.GetElapsedTime(Interlocked.Read(ref shownAt)).TotalMilliseconds > 500))
                            Show(picture, decoder.Sps);
                        break;
                    case SessionKinds.Thumbnail:
                        if (ImageBlobs.Thumbnail(payload) is { } thumb && LoadImage(thumb.Jpeg) is { } thumbImage)
                            BeginInvoke(() => bar.SetThumbnail(thumb.WindowId, thumbImage));
                        break;
                    case SessionKinds.AppIcon:
                        if (ImageBlobs.Icon(payload) is { } icon && LoadImage(icon.Png) is { } iconImage)
                            BeginInvoke(() => drawer.SetIcon(icon.BundleId, iconImage));
                        break;
                    case SessionKinds.AppList:
                        if (SessionMessages.Decode<List<AppInfo>>(payload) is { } apps)
                            BeginInvoke(() => drawer.SetApps(apps));
                        break;
                    case SessionKinds.Pong:
                        double sent = SessionMessages.PongTime(payload);
                        lock (gate) rtt = Math.Max(rtt ?? 0, clock.Elapsed.TotalSeconds - sent);
                        break;
                    case SessionKinds.Goodbye:
                        var bye = SessionMessages.Decode<Goodbye>(payload);
                        Status($"{mac.Name} ended the session: {bye?.Message ?? bye?.Reason ?? "goodbye"}");
                        break;
                }
            }
            Status($"{mac.Name} closed the session. Reconnecting…");
        }
        catch (OperationCanceledException) when (!stopping.IsCancellationRequested) { Status($"Lost {mac.Name} (nothing for 10 s). Reconnecting…"); }
        catch (OperationCanceledException) { }
        catch (Exception e) { Log(e.ToString()); Status($"The session ended: {e.Message} Reconnecting…"); }
        finally { connected = false; paintPending = false; decoder?.Dispose(); }
        return true;
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
                var stats = JsonSerializer.SerializeToUtf8Bytes(new { fps = picturesShown, frameAgeMs = -1, rttMs = -1, device = $"{Environment.MachineName} (Windows)" });
                await session.SendAsync(StreamHeader.Serialize(SessionKinds.ClientStats, 0, false, stats), ct);
            }
            while (await timer.WaitForNextTickAsync(ct));
        }
        catch (Exception e) when (e is OperationCanceledException or IOException or ObjectDisposedException) { }
    }
}
