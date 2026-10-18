using System.Drawing.Drawing2D;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The Apps drawer, as the iPad's (iOSClient/StreamScreen.swift's <c>AppDrawer</c>): a floating
/// card under the bar on the left, a search field ("Search apps on ‹Mac›"), then "Open now" (the
/// apps with windows, how many; a click streams one, again the next) and "All apps" (a click opens
/// it, kind 7), each row an icon (kind 4) and a name, scrolled by the wheel with no scrollbar.
/// While it is open its field takes the keys (Return opens the first row, Esc closes); closing
/// gives them back to the Mac.
/// </summary>
sealed class AppsDrawer : Control
{
    public event Action<string>? Launch;
    public event Action<uint>? ShowWindow;
    public event Action? Closed;

    // The iPad's drawer, in points.
    private const float CardWidth = 380, Inset = 14, Radius = 20, FieldHeight = 48, FieldRadius = 12,
        OpenRow = 50, AppRow = 46, RowGap = 6, RowRadius = 10, Icon = 32, IconRadius = 9, Header = 32;

    private sealed record Row(string Title, string BundleId, string? Trailing, bool Open, bool Lit, float Height);

    private readonly TextBox search;
    private IReadOnlyList<AppInfo> apps = [];
    private IReadOnlyList<WindowInfo> windows = [];
    private uint? activeWindow;
    private readonly Dictionary<string, Image> icons = [];
    private List<(Row? Row, string? Header, RectangleF Rect)> layout = [];
    private float scroll;
    private int hover = -1;
    private Font rowFont, smallFont, headerFont, glyphFont, letterFont;

    public AppsDrawer()
    {
        SetStyle(ControlStyles.Selectable, false);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        TabStop = false;
        Visible = false;
        BackColor = Palette.Bar;
        MakeFonts();
        search = new TextBox
        {
            BorderStyle = BorderStyle.None, BackColor = Palette.Control, ForeColor = Palette.Text,
            Font = Palette.UiFont(15, DeviceDpi), PlaceholderText = "Search apps on your Mac",
        };
        search.TextChanged += (_, _) => { scroll = 0; Relayout(); };
        search.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Close(); }
            if (e.KeyCode == Keys.Enter && layout.FirstOrDefault(l => l.Row is not null).Row is { } first) { e.SuppressKeyPress = true; Activate(first); }
        };
        Controls.Add(search);
    }

    [System.Diagnostics.CodeAnalysis.MemberNotNull(nameof(rowFont), nameof(smallFont), nameof(headerFont), nameof(glyphFont), nameof(letterFont))]
    private void MakeFonts()
    {
        rowFont = Palette.UiFont(15, DeviceDpi);
        smallFont = Palette.UiFont(13, DeviceDpi);
        headerFont = Palette.UiFont(13, DeviceDpi, semibold: true);
        glyphFont = Palette.IconFont(18, DeviceDpi);
        letterFont = Palette.UiFont(12, DeviceDpi, semibold: true);
    }

    private float S(float points) => points * DeviceDpi / 96f;

    /// <summary>The card's width in pixels, for the form to place it.</summary>
    public int CardPixels => (int)S(CardWidth);

    public bool Typing => Visible && search.Focused;

    public void Toggle()
    {
        if (Visible) { Close(); return; }
        search.Text = "";
        scroll = 0;
        Relayout();
        Show();
        BringToFront();
        search.Focus();
    }

    public void Close()
    {
        if (!Visible) return;
        Hide();
        Closed?.Invoke();
    }

    public void SetMacName(string name) { search.PlaceholderText = $"Search apps on {name}"; }

    public void SetApps(IReadOnlyList<AppInfo> apps) { this.apps = apps; if (Visible) Relayout(); }

    public void SetWindows(IReadOnlyList<WindowInfo> windows, uint? activeWindow)
    {
        this.windows = windows;
        this.activeWindow = activeWindow;
        if (Visible) Relayout();
    }

    public void SetIcon(string bundleId, Image image)
    {
        if (icons.Remove(bundleId, out var old)) old.Dispose();
        icons[bundleId] = image;
        if (Visible) Invalidate();
    }

    // ---- layout ----

    private RectangleF FieldRect => new(S(Inset), S(Inset), Width - 2 * S(Inset), S(FieldHeight));
    private float ListTop => FieldRect.Bottom + S(RowGap);

    private void Relayout()
    {
        string q = search.Text.Trim();
        bool Matches(string name) => q.Length == 0 || name.Contains(q, StringComparison.OrdinalIgnoreCase);
        string? activeBundle = windows.FirstOrDefault(w => w.Id == activeWindow)?.BundleId;
        var open = windows.Where(w => w.BundleId is not null).GroupBy(w => w.BundleId!)
            .Select(g => new Row(g.First().AppName ?? g.Key, g.Key, g.Count() == 1 ? "1 window" : $"{g.Count()} windows", true, g.Key == activeBundle, OpenRow))
            .Where(r => Matches(r.Title)).ToList();
        var running = open.Select(r => r.BundleId).ToHashSet();
        var all = apps.Where(a => !running.Contains(a.BundleId) && Matches(a.Name))
            .OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase)
            .Select(a => new Row(a.Name, a.BundleId, null, false, false, AppRow)).ToList();

        var next = new List<(Row?, string?, RectangleF)>();
        float y = 0, x = S(Inset), w = Width - 2 * S(Inset);
        void Section(string title, List<Row> rows)
        {
            if (rows.Count == 0) return;
            next.Add((null, title, new RectangleF(x, y, w, S(Header))));
            y += S(Header);
            foreach (var r in rows) { next.Add((r, null, new RectangleF(x, y, w, S(r.Height)))); y += S(r.Height) + S(RowGap); }
        }
        Section("Open now", open);
        Section("All apps", all);
        layout = next;
        hover = -1;
        ClampScroll();
        Invalidate();
    }

    private float ContentHeight => layout.Count == 0 ? 0 : layout[^1].Rect.Bottom + S(Inset);
    private void ClampScroll() => scroll = Math.Clamp(scroll, 0, Math.Max(0, ContentHeight - (Height - ListTop)));

    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);
        var f = FieldRect;
        int glyph = (int)S(40);
        int textHeight = search.PreferredHeight;
        search.SetBounds((int)(f.X + glyph), (int)(f.Y + (f.Height - textHeight) / 2), (int)(f.Width - glyph - S(12)), textHeight);
        // The card's corners: the picture shows through them.
        using var path = Palette.Rounded(new RectangleF(0, 0, Width, Height), S(Radius));
        Region = new Region(path);
        if (Visible) Relayout();
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        MakeFonts();
        search.Font = Palette.UiFont(15, DeviceDpi);
        PerformLayout();
    }

    // ---- drawing ----

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Palette.Bar);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        using (var edge = new Pen(Color.FromArgb(26, 255, 255, 255), S(1)))
        using (var outline = Palette.Rounded(new RectangleF(S(0.5f), S(0.5f), Width - S(1), Height - S(1)), S(Radius)))
            g.DrawPath(edge, outline);

        var f = FieldRect;
        Palette.FillRounded(g, Palette.Control, f, S(FieldRadius));
        TextRenderer.DrawText(g, "", glyphFont, Rectangle.Round(new RectangleF(f.X, f.Y, S(40), f.Height)), Palette.Muted,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        var list = new RectangleF(0, ListTop, Width, Height - ListTop - S(Inset) / 2);
        var state = g.Save();
        g.SetClip(list);
        for (int i = 0; i < layout.Count; i++)
        {
            var (row, header, rect) = layout[i];
            var r = new RectangleF(rect.X, rect.Y + list.Y - scroll, rect.Width, rect.Height);
            if (r.Bottom < list.Y || r.Y > list.Bottom) continue;
            if (header is not null)
            {
                TextRenderer.DrawText(g, header, headerFont, Rectangle.Round(new RectangleF(r.X + S(10), r.Y + S(10), r.Width, r.Height - S(10))),
                    Palette.Muted, TextFormatFlags.Left | TextFormatFlags.NoPadding);
                continue;
            }
            DrawRow(g, row!, r, i == hover);
        }
        // Where the list continues under the field or the card's foot, it fades.
        if (scroll > 0.5f) Fade(g, new RectangleF(0, list.Y, Width, S(18)), down: true);
        if (scroll < ContentHeight - list.Height - 0.5f) Fade(g, new RectangleF(0, list.Bottom - S(18), Width, S(18)), down: false);
        g.Restore(state);
    }

    private static void Fade(Graphics g, RectangleF r, bool down)
    {
        var clear = Color.FromArgb(0, Palette.Bar);
        using var brush = new LinearGradientBrush(new RectangleF(r.X, r.Y - 1, r.Width, r.Height + 2),
            down ? Palette.Bar : clear, down ? clear : Palette.Bar, LinearGradientMode.Vertical);
        g.FillRectangle(brush, r);
    }

    private void DrawRow(Graphics g, Row row, RectangleF r, bool hovered)
    {
        if (row.Lit || hovered) Palette.FillRounded(g, row.Lit ? Palette.Control : Palette.ControlHover, r, S(RowRadius));
        var icon = new RectangleF(r.X + S(10), r.Y + (r.Height - S(Icon)) / 2, S(Icon), S(Icon));
        if (icons.TryGetValue(row.BundleId, out var image))
        {
            using var path = Palette.Rounded(icon, S(IconRadius));
            var state = g.Save();
            g.SetClip(path, CombineMode.Intersect);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(image, icon);
            g.Restore(state);
        }
        else
        {
            Palette.FillRounded(g, Palette.IconFallback, icon, S(IconRadius));
            TextRenderer.DrawText(g, row.Title.Length >= 2 ? row.Title[..2] : row.Title, letterFont, Rectangle.Round(icon), Color.White,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
        float textX = icon.Right + S(12), right = r.Right - S(10);
        if (row.Trailing is { } trailing)
        {
            var size = TextRenderer.MeasureText(trailing, smallFont);
            TextRenderer.DrawText(g, trailing, smallFont, Rectangle.Round(new RectangleF(right - size.Width, r.Y, size.Width, r.Height)),
                Palette.Muted, TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            right -= size.Width + S(12);
        }
        TextRenderer.DrawText(g, row.Title, rowFont, Rectangle.Round(new RectangleF(textX, r.Y, right - textX, r.Height)), Palette.Text,
            TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }

    // ---- input ----

    private int RowAt(Point p)
    {
        if (p.Y < ListTop) return -1;
        for (int i = 0; i < layout.Count; i++)
        {
            var (row, _, rect) = layout[i];
            if (row is not null && new RectangleF(rect.X, rect.Y + ListTop - scroll, rect.Width, rect.Height).Contains(p)) return i;
        }
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        int at = RowAt(e.Location);
        if (at != hover) { hover = at; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = -1; Invalidate(); }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button == MouseButtons.Left && RowAt(e.Location) is var at and >= 0 && layout[at].Row is { } row) Activate(row);
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        scroll -= e.Delta / 120f * S(AppRow + RowGap) * 2;
        ClampScroll();
        hover = RowAt(PointToClient(MousePosition));
        Invalidate();
        if (e is HandledMouseEventArgs handled) handled.Handled = true;
    }

    private void Activate(Row row)
    {
        if (row.Open)
        {
            // As the iPad's: an open app's window; again, its next one.
            var its = windows.Where(w => w.BundleId == row.BundleId).ToList();
            int now = its.FindIndex(w => w.Id == activeWindow);
            ShowWindow?.Invoke(its[(now + 1) % its.Count].Id);
        }
        else Launch?.Invoke(row.BundleId);
        Close();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            foreach (var i in icons.Values) i.Dispose();
            rowFont.Dispose(); smallFont.Dispose(); headerFont.Dispose(); glyphFont.Dispose(); letterFont.Dispose();
        }
        base.Dispose(disposing);
    }
}
