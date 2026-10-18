using System.Drawing.Drawing2D;

namespace Sill.Viewer;

/// <summary>
/// What the viewer is doing while there is no live picture (connecting, waiting for the first
/// picture, reconnecting, a Mac that ended the session), as a card centred over the picture's
/// place: the Mac's name, the status under it in the muted colour, and a spinner while the viewer
/// is working on it. Over the last picture when a session ends, so it reads as "this is old". Drawn
/// by hand in the bar's colours; it takes no focus and no clicks.
/// </summary>
sealed class StatusCard : Control
{
    private const float CardWidth = 380, Pad = 24, Radius = 20, Spinner = 28, Gap = 14;

    private string title = "", detail = "";
    private bool busy;
    private float angle;
    private readonly System.Windows.Forms.Timer spin = new() { Interval = 16 };
    private Font titleFont, detailFont;

    public StatusCard()
    {
        SetStyle(ControlStyles.Selectable, false);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        TabStop = false;
        BackColor = Palette.Bar;
        titleFont = Palette.UiFont(20, DeviceDpi, semibold: true);
        detailFont = Palette.UiFont(14, DeviceDpi);
        spin.Tick += (_, _) => { angle = (angle + 6) % 360; Invalidate(SpinnerRect); };
    }

    private float S(float points) => points * DeviceDpi / 96f;
    private Rectangle SpinnerRect => Rectangle.Round(new RectangleF((Width - S(Spinner)) / 2, S(Pad), S(Spinner), S(Spinner)));

    /// <summary>The card's content; it sizes itself and the caller centres it.</summary>
    public void Set(string title, string detail, bool busy)
    {
        this.title = title; this.detail = detail; this.busy = busy;
        int width = (int)S(CardWidth), inner = width - (int)(2 * S(Pad));
        var flags = TextFormatFlags.WordBreak | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding;
        int titleH = TextRenderer.MeasureText(title, titleFont, new Size(inner, int.MaxValue), flags).Height;
        int detailH = string.IsNullOrEmpty(detail) ? 0 : TextRenderer.MeasureText(detail, detailFont, new Size(inner, int.MaxValue), flags).Height;
        float height = S(Pad) + (busy ? S(Spinner) + S(Gap) : 0) + titleH + (detailH > 0 ? S(6) + detailH : 0) + S(Pad);
        Size = new Size(width, (int)height);
        spin.Enabled = busy && Visible;
        Invalidate();
    }

    protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); spin.Enabled = busy && Visible; }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        using var path = Palette.Rounded(new RectangleF(0, 0, Width, Height), S(Radius));
        Region = new Region(path);
    }

    protected override void WndProc(ref Message m)
    {
        const int WM_NCHITTEST = 0x0084, HTTRANSPARENT = -1;
        if (m.Msg == WM_NCHITTEST) { m.Result = HTTRANSPARENT; return; }   // clicks go to the form, as over the picture
        base.WndProc(ref m);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Palette.Bar);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (var edge = new Pen(Color.FromArgb(26, 255, 255, 255), S(1)))
        using (var outline = Palette.Rounded(new RectangleF(S(0.5f), S(0.5f), Width - S(1), Height - S(1)), S(Radius)))
            g.DrawPath(edge, outline);
        float y = S(Pad);
        if (busy)
        {
            var r = SpinnerRect;
            using var track = new Pen(Palette.Control, S(3));
            using var arc = new Pen(Palette.Accent, S(3)) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            var circle = RectangleF.Inflate(r, -S(2), -S(2));
            g.DrawEllipse(track, circle);
            g.DrawArc(arc, circle, angle, 100);
            y += S(Spinner) + S(Gap);
        }
        int inner = Width - (int)(2 * S(Pad));
        var flags = TextFormatFlags.WordBreak | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding;
        int titleH = TextRenderer.MeasureText(title, titleFont, new Size(inner, int.MaxValue), flags).Height;
        TextRenderer.DrawText(g, title, titleFont, new Rectangle((int)S(Pad), (int)y, inner, titleH), Palette.Text, flags);
        y += titleH + S(6);
        if (!string.IsNullOrEmpty(detail))
            TextRenderer.DrawText(g, detail, detailFont, new Rectangle((int)S(Pad), (int)y, inner, Height - (int)y), Palette.Muted, flags);
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        titleFont.Dispose(); detailFont.Dispose();
        titleFont = Palette.UiFont(20, DeviceDpi, semibold: true);
        detailFont = Palette.UiFont(14, DeviceDpi);
        Set(title, detail, busy);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { spin.Dispose(); titleFont.Dispose(); detailFont.Dispose(); }
        base.Dispose(disposing);
    }
}
