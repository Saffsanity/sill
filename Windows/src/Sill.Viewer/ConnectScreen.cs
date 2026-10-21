using System.Diagnostics;
using System.Drawing.Drawing2D;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The connect screen, as the iPad's (iOSClient/ContentView.swift): "Connect to a Mac", a status
/// line, the Macs this PC finds on the network (each with its word: Wired, Wi‑Fi, Not paired,
/// Update Sill), Add a Mac… last, and along the bottom the footer: "Needs the free Sill app on your
/// Mac." with the download, support and privacy links. A column 380 px wide, centred, drawn by hand
/// in the iPad's colours. While a pairing's <see cref="PairCard"/> is up it takes the rows' and
/// Add a Mac…'s place in the column (<see cref="ShowCard"/>). It only shows and reports clicks;
/// <see cref="ConnectForm"/> decides.
/// </summary>
sealed class ConnectScreen : Control
{
    public event Action<MacRow>? RowClicked;
    public event Action? AddMacClicked;

    public static readonly (string Text, string Url)[] Links =
    [
        ("Get it at getsill.app", "https://getsill.app/download"),
        ("Support", "https://getsill.app/support"),
        ("Privacy Policy", "https://getsill.app/privacy"),
    ];

    private const float ColumnWidth = 380, RowHeight = 50, Spacing = 6, ButtonHeight = 44, FooterGap = 24, LinkReach = 14;

    private IReadOnlyList<MacRow> rows = [];
    private string status = "";
    private string? busyRow;   // the row a click is dialing, lit as the iPad lights it
    private PairCard? card;
    private Font titleFont, rowFont, smallFont, buttonFont, iconFont;

    private enum Hit { None, Row, Add, Link }
    private readonly List<(Hit Kind, RectangleF Rect, int Index)> targets = [];
    private (Hit Kind, int Index) hover = (Hit.None, -1);

    public ConnectScreen()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        BackColor = Palette.Panel;
        MakeFonts();
    }

    [System.Diagnostics.CodeAnalysis.MemberNotNull(nameof(titleFont), nameof(rowFont), nameof(smallFont), nameof(buttonFont), nameof(iconFont))]
    private void MakeFonts()
    {
        titleFont = Palette.UiFont(17, DeviceDpi, semibold: true);
        rowFont = Palette.UiFont(15, DeviceDpi);
        smallFont = Palette.UiFont(13, DeviceDpi);
        buttonFont = Palette.UiFont(15, DeviceDpi, semibold: true);
        iconFont = Palette.IconFont(16, DeviceDpi);
    }

    private float S(float points) => points * DeviceDpi / 96f;

    public void Show(IReadOnlyList<MacRow> rows, string status, string? busyRow)
    {
        this.rows = rows; this.status = status; this.busyRow = busyRow;
        Invalidate();
    }

    /// <summary>The pairing card in the column in place of the rows; null puts the rows back.</summary>
    public void ShowCard(PairCard? next)
    {
        if (card == next) return;
        if (card is not null) { card.Resized -= Invalidate; Controls.Remove(card); }
        card = next;
        if (card is not null)
        {
            card.Width = (int)ColumnPixels;
            card.Resized += Invalidate;
            Controls.Add(card);
        }
        hover = (Hit.None, -1);
        Invalidate();
    }

    // ---- layout ----

    private float ColumnPixels => Math.Min(S(ColumnWidth), Math.Max(S(200), Width - S(32)));
    private float ColumnX => (Width - ColumnPixels) / 2;

    private float StatusHeight(float w) =>
        status.Length == 0 ? 0 : TextRenderer.MeasureText(status, smallFont, new Size((int)w, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;

    private float ColumnHeight(float w) =>
        S(24) + S(Spacing) + StatusHeight(w - S(20)) + S(4)
        + (card is not null ? card.Height : rows.Count * (S(RowHeight) + S(Spacing)) + S(ButtonHeight));

    private float FooterHeight => S(18) + S(8) + S(18) + S(LinkReach);

    // ---- drawing ----

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Palette.Panel);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        targets.Clear();
        float x = ColumnX, w = ColumnPixels;
        float column = ColumnHeight(w), footerTop = Height - FooterHeight;
        // Centred in the window, risen only to keep the gap above the footer, never above 16 px.
        float y = Math.Max(S(16), Math.Min((Height - column) / 2, footerTop - S(FooterGap) - column));
        var line = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis;

        TextRenderer.DrawText(g, "Connect to a Mac", titleFont, Rectangle.Round(new RectangleF(x + S(10), y, w - S(20), S(24))), Palette.Text, line);
        y += S(24) + S(Spacing);
        float sh = StatusHeight(w - S(20));
        if (sh > 0)
            TextRenderer.DrawText(g, status, smallFont, Rectangle.Round(new RectangleF(x + S(10), y, w - S(20), sh)), Palette.Muted,
                TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
        y += sh + S(4);

        if (card is not null)
        {
            if (card.Width != (int)w) card.Width = (int)w;   // its Resized puts it right next paint
            var at = new Point((int)x, (int)y);
            if (card.Location != at) card.Location = at;
            DrawFooter(g, x + S(10), footerTop);
            return;
        }

        for (int i = 0; i < rows.Count; i++)
        {
            var r = new RectangleF(x, y, w, S(RowHeight));
            DrawRow(g, rows[i], r, hover == (Hit.Row, i) || rows[i].Key == busyRow);
            targets.Add((Hit.Row, r, i));
            y += S(RowHeight) + S(Spacing);
        }

        var add = new RectangleF(x, y, w, S(ButtonHeight));
        if (hover.Kind == Hit.Add) Palette.FillRounded(g, Palette.ControlHover, add, S(10));
        TextRenderer.DrawText(g, "Add a Mac…", buttonFont, Rectangle.Round(new RectangleF(x + S(10), y, w - S(20), add.Height)), Palette.Accent, line);
        targets.Add((Hit.Add, add, 0));

        DrawFooter(g, x + S(10), footerTop);
    }

    private void DrawRow(Graphics g, MacRow row, RectangleF r, bool lit)
    {
        if (lit) Palette.FillRounded(g, Palette.Control, r, S(10));
        var icon = new RectangleF(r.X + S(10), r.Y + (r.Height - S(32)) / 2, S(32), S(32));
        Palette.FillRounded(g, Palette.IconFallback, icon, S(9));
        TextRenderer.DrawText(g, "" /* a monitor */, iconFont, Rectangle.Round(icon), Color.White,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        float trailing = 0;
        if (row.Word is { } word)
        {
            var size = TextRenderer.MeasureText(word, smallFont);
            trailing = size.Width + S(12);
            TextRenderer.DrawText(g, word, smallFont, Rectangle.Round(new RectangleF(r.Right - S(10) - size.Width, r.Y, size.Width, r.Height)),
                Palette.Muted, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter);
        }
        float tx = icon.Right + S(12);
        TextRenderer.DrawText(g, row.Name, rowFont, Rectangle.Round(new RectangleF(tx, r.Y, r.Right - S(10) - trailing - tx, r.Height)), Palette.Text,
            TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
    }

    private void DrawFooter(Graphics g, float x, float y)
    {
        var line = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
        TextRenderer.DrawText(g, "Needs the free Sill app on your Mac.", smallFont, new Point((int)x, (int)y), Palette.Muted, line);
        y += S(18) + S(8);
        var dot = TextRenderer.MeasureText(" · ", smallFont, Size.Empty, line);
        for (int i = 0; i < Links.Length; i++)
        {
            var size = TextRenderer.MeasureText(Links[i].Text, smallFont, Size.Empty, line);
            var r = new RectangleF(x, y, size.Width, size.Height);
            TextRenderer.DrawText(g, Links[i].Text, smallFont, new Point((int)x, (int)y), Palette.Accent,
                line);
            if (hover == (Hit.Link, i))
                using (var under = new Pen(Palette.Accent, S(1))) g.DrawLine(under, r.X, r.Bottom, r.Right, r.Bottom);
            targets.Add((Hit.Link, RectangleF.Inflate(r, 0, S(LinkReach) / 2), i));
            x += size.Width;
            if (i < Links.Length - 1)
            {
                TextRenderer.DrawText(g, " · ", smallFont, new Point((int)x, (int)y), Palette.Muted, line);
                x += dot.Width;
            }
        }
    }

    // ---- input ----

    private (Hit Kind, int Index) HitAt(Point p)
    {
        foreach (var t in targets)
            if (t.Rect.Contains(p)) return (t.Kind, t.Index);
        return (Hit.None, -1);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var at = HitAt(e.Location);
        Cursor = at.Kind == Hit.None ? Cursors.Default : Cursors.Hand;
        if (at != hover) { hover = at; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = (Hit.None, -1); Invalidate(); }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left) return;
        var at = HitAt(e.Location);
        switch (at.Kind)
        {
            case Hit.Row when at.Index < rows.Count: RowClicked?.Invoke(rows[at.Index]); break;
            case Hit.Add: AddMacClicked?.Invoke(); break;
            case Hit.Link:
                try { Process.Start(new ProcessStartInfo(Links[at.Index].Url) { UseShellExecute = true }); }
                catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException) { }
                break;
        }
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        titleFont.Dispose(); rowFont.Dispose(); smallFont.Dispose(); buttonFont.Dispose(); iconFont.Dispose();
        MakeFonts();
        Invalidate();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { titleFont.Dispose(); rowFont.Dispose(); smallFont.Dispose(); buttonFont.Dispose(); iconFont.Dispose(); }
        base.Dispose(disposing);
    }
}
