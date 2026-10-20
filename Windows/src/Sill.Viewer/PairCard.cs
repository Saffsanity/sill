using System.Drawing.Drawing2D;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// Pairing's card on the connect screen, as the iPad's home card and Add a Mac card
/// (iOSClient/AddMacCard.swift), unfolded in the column in place of the rows. For a row whose Mac
/// shows its code ("Enter the Code from ‹Mac›"): the 12-digit field, grouped in fours as it is
/// typed and its check digit judged once all 12 are there. For Add a Mac…: a field for a pasted
/// <c>sill://pair</c> link or an address, then the code (not needed with a link). Under them the
/// problem in orange, the progress with a spinner, Pair and Cancel, and how the Mac will list this
/// PC (Rename…). It shows and reports; <see cref="ConnectForm"/> runs the <see cref="PairingFlow"/>.
/// Return pairs, Esc cancels.
/// </summary>
sealed class PairCard : Control
{
    public event Action<string, string>? Pair;   // (link or address, code); the home card's first is ""
    public event Action? Cancelled;
    public event Action? Rename;
    /// <summary>The card's height changed: the screen places it again.</summary>
    public event Action? Resized;

    private const float CardWidth = 380, Pad = 20, Radius = 20, FieldHeight = 48, FieldRadius = 12, ButtonHeight = 44, Spinner = 18;
    public static readonly Color Orange = Color.FromArgb(0xFF, 0xB0, 0x5C);

    private readonly TextBox where, code;
    private bool addMac, proving, grouping;
    private string title = "", line = "", progress = "", pcName = "", mac = "";
    private string? flowProblem, typingProblem;
    private float angle;
    private readonly System.Windows.Forms.Timer spin = new() { Interval = 16 };
    private Font titleFont, textFont, smallFont, buttonFont, fieldFont, codeFont;
    private RectangleF pairRect, cancelRect, renameRect, whereRect, codeRect;
    private enum Hit { None, Pair, Cancel, Rename }
    private Hit hover;

    public PairCard()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        BackColor = Palette.Bar;
        MakeFonts();
        where = Field(fieldFont, "sill://pair… or 100.101.102.103");
        code = Field(codeFont, "0000 0000 0000");
        code.TextChanged += (_, _) => CodeTyped();
        where.TextChanged += (_, _) => { flowProblem = null; code.Enabled = !AddMacInput.IsLink(where.Text); Relayout(); };
        Controls.Add(where);
        Controls.Add(code);
        spin.Tick += (_, _) => { angle = (angle + 6) % 360; Invalidate(); };
    }

    private TextBox Field(Font font, string placeholder)
    {
        var box = new TextBox { BorderStyle = BorderStyle.None, BackColor = Palette.Control, ForeColor = Palette.Text, Font = font, PlaceholderText = placeholder };
        box.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Submit(); }
            else if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Cancelled?.Invoke(); }
        };
        return box;
    }

    [System.Diagnostics.CodeAnalysis.MemberNotNull(nameof(titleFont), nameof(textFont), nameof(smallFont), nameof(buttonFont), nameof(fieldFont), nameof(codeFont))]
    private void MakeFonts()
    {
        titleFont = Palette.UiFont(17, DeviceDpi, semibold: true);
        textFont = Palette.UiFont(13, DeviceDpi);
        smallFont = Palette.UiFont(12.5f, DeviceDpi);
        buttonFont = Palette.UiFont(15, DeviceDpi, semibold: true);
        fieldFont = Palette.UiFont(15, DeviceDpi);
        // Digits that line up, as the iPad's monospaced field.
        codeFont = new Font(FontFamily.Families.Any(f => f.Name == "Cascadia Mono") ? "Cascadia Mono" : "Consolas", 16 * DeviceDpi / 96f, GraphicsUnit.Pixel);
    }

    private float S(float points) => points * DeviceDpi / 96f;
    public int CardPixels => (int)S(CardWidth);

    /// <summary>The home card for <paramref name="mac"/>, or Add a Mac (<paramref name="mac"/> null), empty.</summary>
    public void Open(string? mac, string pcName)
    {
        addMac = mac is null;
        this.mac = mac ?? "your Mac";
        this.pcName = pcName;
        title = addMac ? PairingCopy.AddTitle : PairingCopy.CardTitle(this.mac);
        line = addMac ? PairingCopy.AddLine + " " + PairingCopy.AddHow : PairingCopy.TypeCode(this.mac);
        where.Text = ""; code.Text = ""; code.Enabled = true;
        where.Visible = addMac;
        flowProblem = typingProblem = null;
        proving = false;
        Relayout();
        (addMac ? where : code).Focus();
    }

    /// <summary>The flow's state: its problem, and whether a proof is on its way (fields and Pair wait).</summary>
    public void Set(PairingFlow flow)
    {
        flowProblem = flow.Problem;
        proving = flow.Step == PairingFlow.Steps.Proving;
        progress = flow.Line ?? PairingCopy.Pairing(mac);
        where.Enabled = !proving;
        code.Enabled = !proving && !(addMac && AddMacInput.IsLink(where.Text));
        spin.Enabled = proving && Visible;
        Relayout();
        if (!proving && flowProblem is not null) code.Focus();
    }

    public void SetPcName(string name) { pcName = name; Relayout(); }

    private void CodeTyped()
    {
        if (grouping) return;
        string grouped = CodeEntry.Grouped(code.Text);
        if (grouped != code.Text)
        {
            grouping = true;
            code.Text = grouped;
            code.SelectionStart = grouped.Length;
            grouping = false;
        }
        flowProblem = null;
        typingProblem = CodeEntry.WhileTyping(grouped);
        Relayout();
    }

    private bool CanPair => !proving && (addMac
        ? AddMacInput.IsLink(where.Text) || (where.Text.Trim().Length > 0 && CodeEntry.Ready(code.Text))
        : CodeEntry.Ready(code.Text));

    private void Submit()
    {
        if (proving) return;
        if (!CanPair && !addMac && CodeEntry.OnSubmit(code.Text, out _) is { } p) { typingProblem = p; Relayout(); return; }
        Pair?.Invoke(addMac ? where.Text : "", code.Text);
    }

    // ---- layout ----

    private string? Problem => typingProblem ?? flowProblem;
    private string Footnote => $"{(addMac ? "Your Mac" : mac)} will list this PC as “{pcName}”.";

    private float Measure(string text, Font font, float width) =>
        TextRenderer.MeasureText(text, font, new Size((int)width, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;

    private void Relayout()
    {
        float w = Width > 0 ? Width : CardPixels, inner = w - 2 * S(Pad), y = S(Pad);
        y += Measure(title, titleFont, inner) + S(6);
        y += Measure(line, textFont, inner) + S(14);
        if (addMac) { whereRect = new RectangleF(S(Pad), y, inner, S(FieldHeight)); y += S(FieldHeight) + S(8); }
        codeRect = new RectangleF(S(Pad), y, inner, S(FieldHeight));
        y += S(FieldHeight) + S(8);
        if (Problem is { } p) y += Measure(p, textFont, inner) + S(8);
        if (proving) y += S(24) + S(4);
        y += S(4);
        var pairSize = TextRenderer.MeasureText("Pair", buttonFont);
        pairRect = new RectangleF(S(Pad), y, Math.Max(S(88), pairSize.Width + S(24)), S(ButtonHeight));
        var cancelSize = TextRenderer.MeasureText("Cancel", buttonFont);
        cancelRect = new RectangleF(pairRect.Right + S(18), y, cancelSize.Width + S(8), S(ButtonHeight));
        y += S(ButtonHeight) + S(10);
        float noteH = Measure(Footnote, smallFont, inner - S(70));
        var renameSize = TextRenderer.MeasureText("Rename…", smallFont);
        renameRect = new RectangleF(w - S(Pad) - renameSize.Width, y, renameSize.Width, Math.Max(noteH, renameSize.Height));
        y += noteH + S(Pad);

        int textHeight = code.PreferredHeight;
        code.SetBounds((int)(codeRect.X + S(14)), (int)(codeRect.Y + (codeRect.Height - textHeight) / 2), (int)(codeRect.Width - S(28)), textHeight);
        int whereHeight = where.PreferredHeight;
        where.SetBounds((int)(whereRect.X + S(14)), (int)(whereRect.Y + (whereRect.Height - whereHeight) / 2), (int)(whereRect.Width - S(28)), whereHeight);
        var size = new Size((int)w, (int)Math.Ceiling(y));
        if (Size != size) { Size = size; Resized?.Invoke(); }
        Invalidate();
    }

    private int laidWidth;

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        if (Width != laidWidth) { laidWidth = Width; Relayout(); }
        using var path = Palette.Rounded(new RectangleF(0, 0, Width, Height), S(Radius));
        Region = new Region(path);
    }

    protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); spin.Enabled = proving && Visible; }

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
        float inner = Width - 2 * S(Pad), y = S(Pad);
        var wrap = TextFormatFlags.NoPadding | TextFormatFlags.WordBreak;
        float h = Measure(title, titleFont, inner);
        TextRenderer.DrawText(g, title, titleFont, Rectangle.Round(new RectangleF(S(Pad), y, inner, h)), Palette.Text, wrap);
        y += h + S(6);
        h = Measure(line, textFont, inner);
        TextRenderer.DrawText(g, line, textFont, Rectangle.Round(new RectangleF(S(Pad), y, inner, h)), addMac ? Palette.Muted : Palette.Text, wrap);

        if (addMac) Palette.FillRounded(g, Palette.Control, whereRect, S(FieldRadius));
        Palette.FillRounded(g, code.Enabled || proving ? Palette.Control : Palette.ControlPressed, codeRect, S(FieldRadius));
        y = codeRect.Bottom + S(8);
        if (Problem is { } p)
        {
            h = Measure(p, textFont, inner);
            TextRenderer.DrawText(g, p, textFont, Rectangle.Round(new RectangleF(S(Pad), y, inner, h)), Orange, wrap);
            y += h + S(8);
        }
        if (proving)
        {
            var r = new RectangleF(S(Pad), y + (S(24) - S(Spinner)) / 2, S(Spinner), S(Spinner));
            using var track = new Pen(Palette.Control, S(2.5f));
            using var arc = new Pen(Palette.Accent, S(2.5f)) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            g.DrawEllipse(track, r);
            g.DrawArc(arc, r, angle, 100);
            TextRenderer.DrawText(g, progress, textFont, Rectangle.Round(new RectangleF(r.Right + S(8), y, inner - S(30), S(24))), Palette.Muted,
                TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }

        var center = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter;
        var fill = CanPair ? (hover == Hit.Pair ? Color.FromArgb(0xB4, 0xC9, 0xFF) : Palette.Accent) : Color.FromArgb(0x4A, 0x55, 0x73);
        Palette.FillRounded(g, fill, pairRect, S(12));
        TextRenderer.DrawText(g, "Pair", buttonFont, Rectangle.Round(pairRect), Color.Black, center);
        if (hover == Hit.Cancel) Palette.FillRounded(g, Palette.ControlHover, cancelRect, S(10));
        TextRenderer.DrawText(g, "Cancel", buttonFont, Rectangle.Round(cancelRect), Palette.Accent, center);

        TextRenderer.DrawText(g, Footnote, smallFont, Rectangle.Round(new RectangleF(S(Pad), renameRect.Y, inner - S(70), renameRect.Height)), Palette.Muted, wrap);
        TextRenderer.DrawText(g, "Rename…", smallFont, Rectangle.Round(renameRect), Palette.Accent, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        if (hover == Hit.Rename)
            using (var under = new Pen(Palette.Accent, S(1))) g.DrawLine(under, renameRect.X, renameRect.Y + smallFont.Height, renameRect.Right, renameRect.Y + smallFont.Height);
    }

    // ---- input ----

    private Hit HitAt(Point p) =>
        pairRect.Contains(p) ? Hit.Pair : cancelRect.Contains(p) ? Hit.Cancel : renameRect.Contains(p) ? Hit.Rename : Hit.None;

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var at = HitAt(e.Location);
        Cursor = at == Hit.None ? Cursors.Default : Cursors.Hand;
        if (at != hover) { hover = at; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = Hit.None; Invalidate(); }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left) return;
        switch (HitAt(e.Location))
        {
            case Hit.Pair: Submit(); break;
            case Hit.Cancel: Cancelled?.Invoke(); break;
            case Hit.Rename: Rename?.Invoke(); break;
        }
    }

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        DisposeFonts();
        MakeFonts();
        where.Font = fieldFont; code.Font = codeFont;
        Relayout();
    }

    private void DisposeFonts() { titleFont.Dispose(); textFont.Dispose(); smallFont.Dispose(); buttonFont.Dispose(); fieldFont.Dispose(); codeFont.Dispose(); }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { spin.Dispose(); DisposeFonts(); }
        base.Dispose(disposing);
    }
}

/// <summary>This PC's name as the Mac lists it, asked for in a small dark window (Settings › This
/// PC, and the pairing card's Rename…). OK saves it to <c>pc.json</c>; empty is the computer's name.</summary>
static class RenameDialog
{
    /// <summary>The new name, or null when cancelled.</summary>
    public static string? Ask(IWin32Window owner, string current, int dpi)
    {
        float s = dpi / 96f;
        using var form = new Form
        {
            Text = "This PC’s Name", FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false,
            ShowInTaskbar = false, StartPosition = FormStartPosition.CenterParent, BackColor = Palette.Bar, ForeColor = Palette.Text,
            ClientSize = new Size((int)(380 * s), (int)(150 * s)), Font = Palette.UiFont(13, dpi),
        };
        form.HandleCreated += (_, _) => Palette.DarkTitleBar(form.Handle);
        var label = new Label
        {
            Text = "The name your Mac lists this PC under when it pairs. A Mac already paired keeps the name it was given (rename it in Sill’s Settings › Devices on the Mac).",
            ForeColor = Palette.Muted, Location = new Point((int)(16 * s), (int)(12 * s)), Size = new Size((int)(348 * s), (int)(48 * s)),
        };
        var box = new TextBox
        {
            Text = current, BorderStyle = BorderStyle.FixedSingle, BackColor = Palette.Control, ForeColor = Palette.Text,
            Font = Palette.UiFont(15, dpi), Location = new Point((int)(16 * s), (int)(66 * s)), Width = (int)(348 * s), MaxLength = 64,
        };
        Button Make(string text, DialogResult result, int x) => new()
        {
            Text = text, DialogResult = result, FlatStyle = FlatStyle.Flat, BackColor = result == DialogResult.OK ? Palette.Accent : Palette.Control,
            ForeColor = result == DialogResult.OK ? Color.Black : Palette.Text, Location = new Point(x, (int)(104 * s)),
            Size = new Size((int)(88 * s), (int)(32 * s)),
        };
        var ok = Make("OK", DialogResult.OK, (int)(276 * s));
        var cancel = Make("Cancel", DialogResult.Cancel, (int)(180 * s));
        ok.FlatAppearance.BorderSize = 0; cancel.FlatAppearance.BorderSize = 0;
        form.Controls.AddRange([label, box, ok, cancel]);
        form.AcceptButton = ok; form.CancelButton = cancel;
        return form.ShowDialog(owner) == DialogResult.OK ? box.Text : null;
    }
}
