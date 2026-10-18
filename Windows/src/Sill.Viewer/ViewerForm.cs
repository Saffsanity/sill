using System.Diagnostics;
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
/// drops pictures rather than queueing them. Double-click for full screen; Esc leaves it.
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
    private volatile int clientWidth = 1280, clientHeight = 800;
    private string status = "Connecting…";
    private string macName = "Mac";

    // Once-a-second figures for the title.
    private int framesIn, picturesShown; private long bytesIn; private double decodeMs, worstDecodeMs; private double? rtt;
    private string size = "";

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

    protected override void OnDoubleClick(EventArgs e) { base.OnDoubleClick(e); FullScreen(FormBorderStyle != FormBorderStyle.None); }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.KeyCode == Keys.Escape && FormBorderStyle == FormBorderStyle.None) FullScreen(false);
        if (e.KeyCode == Keys.F11) FullScreen(FormBorderStyle != FormBorderStyle.None);
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
                g.DrawImage(front, new Rectangle((ClientSize.Width - w) / 2, (ClientSize.Height - h) / 2, w, h));
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
        lock (gate) status = text;
        BeginInvoke(() => { Invalidate(); UpdateTitle(); });
    }

    private async Task RunAsync(CancellationToken ct)
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
            return;
        }
        macName = mac.Name;
        string host = mac.Host; int port = mac.Port;
        if (hostOverride is not null)
        {
            int colon = hostOverride.LastIndexOf(':');
            if (colon <= 0 || !int.TryParse(hostOverride[(colon + 1)..], out port)) { Status("--host takes <address>:<port>."); return; }
            host = hostOverride[..colon].Trim('[', ']');
        }

        Status($"Connecting to {mac.Name} at {host}:{port}…");
        SessionClient session;
        try
        {
            session = await SessionClient.ConnectAsync(host, port, DeviceIdentity.LoadOrCreate(dir), pin,
                new Hello("0.1", "viewer", Hello.CurrentProtocol, $"{Environment.MachineName} (Windows)"), ct);
        }
        catch (Exception e)
        {
            Status($"Couldn’t connect to {mac.Name} at {host}:{port}: {e.Message}");
            return;
        }

        await using var connection = session;
        Status($"Connected to {mac.Name}. Waiting for the picture…");
        var clock = Stopwatch.StartNew();
        _ = PingAsync(session, clock, ct);
        HevcDecoder? decoder = null;
        ParameterSets? ps = null;
        bool asked = false, keyed = false;
        try
        {
            while (await session.ReadAsync(ct) is { } m)
            {
                var (h, payload) = m;
                switch (h.Kind)
                {
                    case SessionKinds.WindowList:
                        if (SessionMessages.Decode<WindowList>(payload) is { } list && list.ActiveName == "none" && !asked)
                        {
                            asked = true;
                            await session.SendAsync(SessionMessages.SelectDesktop(), ct);
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
                        if (picture is not null && !paintPending) Show(picture, decoder.Sps);
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
            Status($"{mac.Name} closed the session.");
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { Status($"The session ended: {e.Message}"); }
        finally { decoder?.Dispose(); }
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
