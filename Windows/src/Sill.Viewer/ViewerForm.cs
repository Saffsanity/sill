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
/// ⌘, right Ctrl ⌃, Alt ⌥. F11 toggles full screen.
/// </summary>
sealed class ViewerForm : Form
{
    private sealed record SavedMac(string Fingerprint, string MacId, string Name, string RecognitionKey, string Host, int Port);

    private readonly string dir;
    private readonly string? hostOverride;
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

    public ViewerForm(string dir, string? hostOverride)
    {
        this.dir = dir; this.hostOverride = hostOverride;
        Text = "Sill Viewer";
        BackColor = Color.Black;
        ClientSize = new Size(1280, 800);
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
        KeyPreview = true;
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Resized();
        _ = Task.Run(() => RunAsync(stop.Token));
        var timer = new System.Windows.Forms.Timer { Interval = 1000 };
        timer.Tick += (_, _) => UpdateTitle();
        timer.Start();
    }

    protected override void OnResize(EventArgs e) { base.OnResize(e); Resized(); Invalidate(); }
    private void Resized() { clientWidth = Math.Max(1, ClientSize.Width); clientHeight = Math.Max(1, ClientSize.Height); }

    protected override void OnFormClosing(FormClosingEventArgs e) { stop.Cancel(); base.OnFormClosing(e); }

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
                float scale = Math.Min((float)ClientSize.Width / front.Width, (float)ClientSize.Height / front.Height);
                int w = (int)(front.Width * scale), h = (int)(front.Height * scale);
                g.InterpolationMode = scale >= 1 ? InterpolationMode.NearestNeighbor : InterpolationMode.Bilinear;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.CompositingMode = CompositingMode.SourceCopy;
                pictureRect = new Rectangle((ClientSize.Width - w) / 2, (ClientSize.Height - h) / 2, w, h);
                g.DrawImage(front, pictureRect);
            }
            else
            {
                TextRenderer.DrawText(g, status, Font, ClientRectangle, Color.Gainsboro,
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
        string host = mac.Host; int port = mac.Port;
        if (hostOverride is not null)
        {
            int colon = hostOverride.LastIndexOf(':');
            if (colon <= 0 || !int.TryParse(hostOverride[(colon + 1)..], out port)) { Status("--host takes <address>:<port>."); return false; }
            host = hostOverride[..colon].Trim('[', ']');
        }

        Status($"Connecting to {mac.Name} at {host}:{port}…");
        // This session's token: the watchdog cancels it when nothing has arrived for 10 s.
        using var sessionStop = CancellationTokenSource.CreateLinkedTokenSource(stopping);
        var ct = sessionStop.Token;
        SessionClient session;
        try
        {
            session = await SessionClient.ConnectAsync(host, port, DeviceIdentity.LoadOrCreate(dir), pin,
                new Hello("0.1", "viewer", Hello.CurrentProtocol, $"{Environment.MachineName} (Windows)"), ct);
        }
        catch (Exception e)
        {
            Status($"Couldn’t connect to {mac.Name} at {host}:{port}: {e.Message} Trying again…");
            return true;
        }

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
        bool asked = false, keyed = false;
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
                        if (SessionMessages.Decode<WindowList>(payload) is { } list && list.ActiveName == "none" && !asked)
                        {
                            asked = true;
                            await session.SendAsync(SessionMessages.SelectDesktop(), ct);
                            Log("Asked for the Desktop.");
                        }
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

    // A ping a second (its pong gives the round trip) and ClientStats, so the Mac's log names us.
    private async Task PingAsync(SessionClient session, Stopwatch clock, CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        try
        {
            do
            {
                await session.SendAsync(SessionMessages.Ping(clock.Elapsed.TotalSeconds), ct);
                var stats = JsonSerializer.SerializeToUtf8Bytes(new { fps = picturesShown, frameAgeMs = -1, rttMs = -1, device = $"{Environment.MachineName} (Windows)" });
                await session.SendAsync(StreamHeader.Serialize(SessionKinds.ClientStats, 0, false, stats), ct);
            }
            while (await timer.WaitForNextTickAsync(ct));
        }
        catch (Exception e) when (e is OperationCanceledException or IOException or ObjectDisposedException) { }
    }
}
