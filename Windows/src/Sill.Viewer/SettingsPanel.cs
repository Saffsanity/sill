using System.Drawing.Drawing2D;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The Settings panel, as the iPad's (iOSClient/HostSettingsPanel.swift): a card hanging under the
/// bar on the right with the Mac's name and what streams, Done, the Mac's streaming settings
/// (Quality, Resolution, Frame Rate, Prioritize Encoding Speed, Virtual Display, Direct Wireless)
/// with the iPad's footnotes, and This PC's own (decoding on the GPU or in software). The values
/// come from the form's <see cref="SettingsLedger"/>; a control's pick goes back to the form, which
/// sends it. Disconnect is pinned at the foot, as the iPad's, and only the rest scrolls. Drawn by
/// hand; it takes no keyboard focus, so keys stay the Mac's.
/// </summary>
sealed class SettingsPanel : Control
{
    public event Action<HostSettingsChange>? Pick;
    public event Action<bool>? SoftwareDecoding;
    public event Action? Done;
    /// <summary>The foot's Disconnect: back to the connect screen.</summary>
    public event Action? Disconnect;

    private const float CardWidth = 360, Pad = 16, Radius = 20, Row = 44, GroupRadius = 12, Gap = 8;

    private enum Kind { Header, Title, Readout, Done, Group, RowTitle, Quality, Segments, Switch, Footnote, Note, Disconnect }
    private sealed record Item(Kind Kind, RectangleF Rect, string Text = "", string[]? Options = null, int Selected = -1,
        bool On = false, bool Enabled = true, bool Pending = false, Action<int>? Choose = null, Color? Tint = null);

    private SettingsLedger? ledger;
    private string mac = "Mac", note = "";
    private bool gpuAvailable, software;
    private string gpuName = "";
    private List<Item> items = [];
    private float scroll, content, middle;
    private int hover = -1;
    private Font titleFont, rowFont, smallFont, headerFont;

    public SettingsPanel()
    {
        SetStyle(ControlStyles.Selectable, false);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        TabStop = false;
        Visible = false;
        BackColor = Palette.Bar;
        MakeFonts();
    }

    [System.Diagnostics.CodeAnalysis.MemberNotNull(nameof(titleFont), nameof(rowFont), nameof(smallFont), nameof(headerFont))]
    private void MakeFonts()
    {
        titleFont = Palette.UiFont(17, DeviceDpi, semibold: true);
        rowFont = Palette.UiFont(15, DeviceDpi);
        smallFont = Palette.UiFont(12.5f, DeviceDpi);
        headerFont = Palette.UiFont(13, DeviceDpi, semibold: true);
    }

    private float S(float points) => points * DeviceDpi / 96f;
    public int CardPixels => (int)S(CardWidth);
    /// <summary>How tall the panel wants to be: all of it, before the form caps it to the window.</summary>
    public int ContentHeight => (int)Math.Ceiling(content);

    /// <summary>What to show: the ledger (the Mac's settings with this PC's picks over them), the
    /// Mac's name, a note ("kept its setting"), and this PC's decoder.</summary>
    public void Show(SettingsLedger ledger, string mac, string note, bool gpuAvailable, string gpuName, bool software)
    {
        this.ledger = ledger; this.mac = mac; this.note = note;
        this.gpuAvailable = gpuAvailable; this.gpuName = gpuName; this.software = software;
        Relayout();
    }

    // ---- layout ----

    private void Relayout()
    {
        var list = new List<Item>();
        float x = S(Pad), w = Width - 2 * S(Pad), y = S(Pad);
        var state = ledger?.Host;
        var shown = ledger?.Displayed;

        // The header: the Mac, what streams, Done.
        var doneSize = TextRenderer.MeasureText("Done", headerFont);
        list.Add(new(Kind.Done, new RectangleF(Width - S(Pad) - doneSize.Width - S(8), y - S(4), doneSize.Width + S(16), S(30)), "Done"));
        list.Add(new(Kind.Title, new RectangleF(x, y, w - doneSize.Width - S(20), S(24)), mac));
        y += S(26);
        string readout = state?.Stream is { } st
            ? $"{st.Width}×{st.Height} · {st.Fps} fps · {st.Mbps} Mbps" + (st.OnVirtualDisplay ? "\nOn the virtual display" : "")
            : "Not streaming";
        float h = Measure(readout, smallFont, w);
        list.Add(new(Kind.Readout, new RectangleF(x, y, w, h), readout));
        y += h + S(12);
        if (note.Length > 0)
        {
            h = Measure(note, smallFont, w - S(20)) + S(16);
            list.Add(new(Kind.Note, new RectangleF(x, y, w, h), note));
            y += h + S(10);
        }

        if (shown is null || state is null)
        {
            list.Add(new(Kind.Footnote, new RectangleF(x, y, w, S(40)), "Loading settings…"));
            y += S(40);
        }
        else
        {
            bool Pend(SettingsLedger.Field f) => ledger!.IsPending(f);
            // Quality, Resolution, Frame Rate.
            y = Group(list, x, y, w, 3);
            list.Add(new(Kind.RowTitle,RowRect(x, y, 0), "Quality", Pending: Pend(SettingsLedger.Field.Bitrate)));
            list.Add(new(Kind.Quality,RowRect(x, y, 0), SettingsChoices.QualityTitle(shown.Bitrate), Pending: Pend(SettingsLedger.Field.Bitrate)));
            int scale = Array.IndexOf(SettingsChoices.CaptureScale, shown.CaptureScale);
            list.Add(new(Kind.RowTitle,RowRect(x, y, 1), "Resolution", Pending: Pend(SettingsLedger.Field.CaptureScale)));
            list.Add(new(Kind.Segments, Segments(x, y, 1, w), Options: ["Retina", "Standard"], Selected: scale,
                Choose: i => Pick?.Invoke(new HostSettingsChange(CaptureScale: SettingsChoices.CaptureScale[i]))));
            int fps = Array.IndexOf(SettingsChoices.MaxFps, shown.MaxFps);
            list.Add(new(Kind.RowTitle,RowRect(x, y, 2), "Frame Rate", Pending: Pend(SettingsLedger.Field.MaxFps)));
            list.Add(new(Kind.Segments, Segments(x, y, 2, w), Options: ["60 fps", "120 fps"], Selected: fps,
                Choose: i => Pick?.Invoke(new HostSettingsChange(MaxFps: SettingsChoices.MaxFps[i]))));
            y += 3 * S(Row);
            y = Footnote(list, x, y, w, "Quality is per 60 fps; a 120 fps stream gets twice as much. " + SettingsChoices.FastLinkNote);

            y = Group(list, x, y, w, 1);
            list.Add(new(Kind.RowTitle,RowRect(x, y, 0), "Prioritize Encoding Speed", Pending: Pend(SettingsLedger.Field.PrioritizeSpeed)));
            list.Add(new(Kind.Switch, SwitchRect(x, y, 0, w), On: shown.PrioritizeSpeed,
                Choose: _ => Pick?.Invoke(new HostSettingsChange(PrioritizeSpeed: !shown.PrioritizeSpeed))));
            y += S(Row);
            y = Footnote(list, x, y, w, $"Lower latency when {mac} is busy, at a softer picture.");

            y = Group(list, x, y, w, 1);
            list.Add(new(Kind.RowTitle,RowRect(x, y, 0), "Virtual Display", Enabled: state.VirtualDisplayAvailable, Pending: Pend(SettingsLedger.Field.VirtualDisplay)));
            list.Add(new(Kind.Switch, SwitchRect(x, y, 0, w), On: shown.VirtualDisplay, Enabled: state.VirtualDisplayAvailable,
                Choose: _ => Pick?.Invoke(new HostSettingsChange(VirtualDisplay: !shown.VirtualDisplay))));
            y += S(Row);
            y = Footnote(list, x, y, w, state.VirtualDisplayNote
                ?? $"The window you pick moves onto an invisible display on {mac} while it streams, so it keeps updating when covered.",
                state.VirtualDisplayNote is null ? null : Color.FromArgb(0xFF, 0xB0, 0x5C));
            y = Footnote(list, x, y - S(4), w, $"Applies to every device streaming from {mac}. The stream restarts for a moment.");

            if (shown.DirectWireless is { } direct)
            {
                y = Group(list, x, y, w, 1);
                list.Add(new(Kind.RowTitle,RowRect(x, y, 0), "Direct Wireless Connection", Pending: Pend(SettingsLedger.Field.DirectWireless)));
                list.Add(new(Kind.Switch, SwitchRect(x, y, 0, w), On: direct,
                    Choose: _ => Pick?.Invoke(new HostSettingsChange(DirectWireless: !direct))));
                y += S(Row);
                y = Footnote(list, x, y, w, $"Lets devices reach {mac} without a shared Wi‑Fi network, the way AirDrop does. While it’s on, streaming over Wi‑Fi can stutter.");
            }
            if (!state.Persistent) y = Footnote(list, x, y, w, "SillHost keeps these until it quits.");
        }

        // This PC.
        list.Add(new(Kind.Header, new RectangleF(x + S(4), y + S(6), w, S(24)), "This PC"));
        y += S(30);
        y = Group(list, x, y, w, 1);
        list.Add(new(Kind.RowTitle,RowRect(x, y, 0), "Decoding"));
        list.Add(new(Kind.Segments, Segments(x, y, 0, w), Options: ["GPU", "Software"], Selected: software ? 1 : 0, Enabled: gpuAvailable,
            Choose: i => SoftwareDecoding?.Invoke(i == 1)));
        y += S(Row);
        y = Footnote(list, x, y, w, gpuAvailable
            ? $"The GPU ({gpuName}) decodes and draws the picture; Software uses the processor. The picture reconnects when this changes."
            : "This PC's GPU can't decode the picture, so the processor does.");

        middle = y + S(Pad);
        content = middle + FootHeight;
        // The foot, pinned: drawn and hit at the panel's bottom, whatever the scroll (Pinned).
        float footY = Math.Max(0, Math.Min(middle, Height - FootHeight)) + S(10);
        string leave = $"Disconnect from {mac}";
        if (TextRenderer.MeasureText(leave, rowFont).Width + S(60) > w) leave = "Disconnect";
        list.Add(new(Kind.Disconnect, new RectangleF(x, footY, w, S(Row)), leave));
        items = list;
        hover = -1;
        scroll = Math.Clamp(scroll, 0, MaxScroll);
        Invalidate();
    }

    private float FootHeight => S(10) + S(Row) + S(Pad);
    private float MaxScroll => Math.Max(0, middle - (Height - FootHeight));
    private static bool Pinned(Item it) => it.Kind == Kind.Disconnect;

    private RectangleF RowRect(float x, float groupTop, int index) => new(x + S(14), groupTop + index * S(Row), Width - 2 * S(Pad) - S(28), S(Row));

    private RectangleF Segments(float x, float groupTop, int index, float w)
    {
        float width = S(150);
        return new RectangleF(x + w - S(8) - width, groupTop + index * S(Row) + S(7), width, S(Row) - S(14));
    }

    private RectangleF SwitchRect(float x, float groupTop, int index, float w) =>
        new(x + w - S(12) - S(46), groupTop + index * S(Row) + (S(Row) - S(28)) / 2, S(46), S(28));

    private float Group(List<Item> list, float x, float y, float w, int rows)
    {
        list.Add(new(Kind.Group, new RectangleF(x, y, w, rows * S(Row))));
        return y;
    }

    private float Footnote(List<Item> list, float x, float y, float w, string text, Color? tint = null)
    {
        float h = Measure(text, smallFont, w - S(28));
        list.Add(new(Kind.Footnote, new RectangleF(x + S(14), y + S(6), w - S(28), h), text, Tint: tint));
        return y + S(6) + h + S(Gap) + S(6);
    }

    private static float Measure(string text, Font font, float width) =>
        TextRenderer.MeasureText(text, font, new Size((int)width, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        using var path = Palette.Rounded(new RectangleF(0, 0, Width, Height), S(Radius));
        Region = new Region(path);
        Relayout();
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        titleFont.Dispose(); rowFont.Dispose(); smallFont.Dispose(); headerFont.Dispose();
        MakeFonts();
        Relayout();
    }

    // ---- drawing ----

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Palette.Bar);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        // Scrolled by moving each item, not by a transform: TextRenderer (GDI) ignores transforms.
        for (int i = 0; i < items.Count; i++)
        {
            var it = items[i];
            if (Pinned(it) || it.Rect.Bottom - scroll < 0 || it.Rect.Y - scroll > Height) continue;
            DrawItem(g, it with { Rect = new RectangleF(it.Rect.X, it.Rect.Y - scroll, it.Rect.Width, it.Rect.Height) }, i == hover);
        }
        // The foot over whatever scrolled under it.
        using (var foot = new SolidBrush(Palette.Bar)) g.FillRectangle(foot, 0, Height - FootHeight, Width, FootHeight);
        for (int i = 0; i < items.Count; i++)
            if (Pinned(items[i])) DrawItem(g, items[i], i == hover);
        using var edge = new Pen(Color.FromArgb(26, 255, 255, 255), S(1));
        using var outline = Palette.Rounded(new RectangleF(S(0.5f), S(0.5f), Width - S(1), Height - S(1)), S(Radius));
        g.DrawPath(edge, outline);
    }

    private void DrawItem(Graphics g, Item it, bool hovered)
    {
        var r = it.Rect;
        var flags = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter;
        switch (it.Kind)
        {
            case Kind.Title:
                TextRenderer.DrawText(g, it.Text, titleFont, Rectangle.Round(r), Palette.Text, flags | TextFormatFlags.EndEllipsis);
                break;
            case Kind.Readout:
                TextRenderer.DrawText(g, it.Text, smallFont, Rectangle.Round(r), Palette.Muted, TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                break;
            case Kind.Done:
                if (hovered) Palette.FillRounded(g, Palette.ControlHover, r, S(8));
                TextRenderer.DrawText(g, it.Text, headerFont, Rectangle.Round(r), Palette.Accent, flags | TextFormatFlags.HorizontalCenter);
                break;
            case Kind.Note:
                Palette.FillRounded(g, Palette.ControlOpen, r, S(10));
                TextRenderer.DrawText(g, it.Text, smallFont, Rectangle.Round(RectangleF.Inflate(r, -S(10), -S(8))), Palette.Text,
                    TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                break;
            case Kind.Header:
                TextRenderer.DrawText(g, it.Text, headerFont, Rectangle.Round(r), Palette.Muted, flags);
                break;
            case Kind.Group:
                Palette.FillRounded(g, Palette.Control, r, S(GroupRadius));
                for (float y = r.Y + S(Row); y < r.Bottom - 1; y += S(Row))
                    using (var line = new Pen(Palette.ControlHover, S(1))) g.DrawLine(line, r.X + S(14), y, r.Right, y);
                break;
            case Kind.RowTitle:
                TextRenderer.DrawText(g, it.Text + (it.Pending ? "  …" : ""), rowFont, Rectangle.Round(r), it.Enabled ? Palette.Text : Palette.Muted, flags);
                break;
            case Kind.Quality:
                // The value as a pull-down, in the accent, as the iPad's menu picker.
                var size = TextRenderer.MeasureText(it.Text + "  ⌄", rowFont);
                var at = new RectangleF(r.Right - size.Width, r.Y, size.Width, r.Height);
                if (hovered) Palette.FillRounded(g, Palette.ControlHover, RectangleF.Inflate(at, S(6), -S(6)), S(8));
                TextRenderer.DrawText(g, it.Text + "  ⌄", rowFont, Rectangle.Round(at), it.Pending ? Palette.Muted : Palette.Accent, flags);
                break;
            case Kind.Segments:
                DrawSegments(g, it, hovered);
                break;
            case Kind.Switch:
                DrawSwitch(g, it);
                break;
            case Kind.Footnote:
                TextRenderer.DrawText(g, it.Text, smallFont, Rectangle.Round(r), it.Tint ?? Palette.Muted, TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                break;
            case Kind.Disconnect:
                Palette.FillRounded(g, hovered ? Palette.ControlHover : Palette.Control, r, S(GroupRadius));
                using (var icon = Palette.IconFont(15, DeviceDpi))
                    TextRenderer.DrawText(g, "\uE711" /* a cross */, icon, Rectangle.Round(new RectangleF(r.X + S(14), r.Y, S(20), r.Height)), Palette.Accent,
                        flags | TextFormatFlags.HorizontalCenter);
                TextRenderer.DrawText(g, it.Text, rowFont, Rectangle.Round(new RectangleF(r.X + S(42), r.Y, r.Width - S(56), r.Height)), Palette.Accent,
                    flags | TextFormatFlags.EndEllipsis);
                break;
        }
    }

    private void DrawSegments(Graphics g, Item it, bool hovered)
    {
        var r = it.Rect;
        Palette.FillRounded(g, Palette.Bar, r, S(8));
        int n = it.Options!.Length;
        float w = r.Width / n;
        for (int i = 0; i < n; i++)
        {
            var seg = new RectangleF(r.X + i * w, r.Y, w, r.Height);
            if (i == it.Selected) Palette.FillRounded(g, Palette.IconFallback, RectangleF.Inflate(seg, -S(2), -S(2)), S(7));
            else if (hovered && it.Enabled && seg.Contains(lastMouse)) Palette.FillRounded(g, Palette.ControlHover, RectangleF.Inflate(seg, -S(2), -S(2)), S(7));
            TextRenderer.DrawText(g, it.Options[i], smallFont, Rectangle.Round(seg), it.Enabled ? Palette.Text : Palette.Muted,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    private void DrawSwitch(Graphics g, Item it)
    {
        var r = it.Rect;
        var track = !it.Enabled ? Palette.ControlHover : it.On ? Palette.Accent : Palette.IconFallback;
        Palette.FillRounded(g, track, r, r.Height / 2);
        float knob = r.Height - S(4);
        float kx = it.On ? r.Right - S(2) - knob : r.X + S(2);
        using var brush = new SolidBrush(it.Enabled ? Color.White : Palette.Muted);
        g.FillEllipse(brush, kx, r.Y + S(2), knob, knob);
    }

    // ---- input ----

    private PointF lastMouse;

    private int ItemAt(Point p)
    {
        for (int i = items.Count - 1; i >= 0; i--)
        {
            if (items[i].Kind is not (Kind.Done or Kind.Quality or Kind.Segments or Kind.Switch or Kind.Disconnect) || !items[i].Enabled) continue;
            if (Pinned(items[i]) ? items[i].Rect.Contains(p) : p.Y < Height - FootHeight && items[i].Rect.Contains(new PointF(p.X, p.Y + scroll))) return i;
        }
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        lastMouse = new PointF(e.X, e.Y);
        int at = ItemAt(e.Location);
        if (at != hover || at >= 0) { hover = at; Invalidate(); }
        Cursor = at >= 0 ? Cursors.Hand : Cursors.Default;
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = -1; Invalidate(); }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left || ItemAt(e.Location) is not (>= 0 and var i)) return;
        var it = items[i];
        switch (it.Kind)
        {
            case Kind.Done: Done?.Invoke(); break;
            case Kind.Disconnect: Disconnect?.Invoke(); break;
            case Kind.Switch: it.Choose?.Invoke(0); break;
            case Kind.Segments:
                int seg = (int)((e.X - it.Rect.X) / (it.Rect.Width / it.Options!.Length));
                if (seg >= 0 && seg < it.Options.Length && seg != it.Selected) it.Choose?.Invoke(seg);
                break;
            case Kind.Quality:
                var menu = Palette.Menu();
                menu.ShowCheckMargin = true;
                foreach (var (name, bitrate) in SettingsChoices.Presets)
                {
                    var item = new ToolStripMenuItem(SettingsChoices.QualityTitle(bitrate)) { Checked = ledger?.Displayed?.Bitrate == bitrate };
                    item.Click += (_, _) => Pick?.Invoke(new HostSettingsChange(Bitrate: bitrate));
                    menu.Items.Add(item);
                }
                menu.Show(this, new Point((int)it.Rect.Right - menu.PreferredSize.Width, (int)(it.Rect.Bottom - scroll)));
                break;
        }
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        scroll = Math.Clamp(scroll - e.Delta / 120f * S(60), 0, MaxScroll);
        Invalidate();
        if (e is HandledMouseEventArgs handled) handled.Handled = true;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { titleFont.Dispose(); rowFont.Dispose(); smallFont.Dispose(); headerFont.Dispose(); }
        base.Dispose(disposing);
    }
}
