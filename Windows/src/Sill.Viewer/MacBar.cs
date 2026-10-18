using System.Drawing.Drawing2D;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The bar across the top, drawn as the iPad's landscape bar (iOSClient/StreamScreen.swift's
/// <c>TopBar</c> at its regular <c>BarMetrics</c>): Apps on the left, then a thumbnail for each Mac
/// window (104×66, the app's icon as a badge, the streamed one in an accent halo; click streams it,
/// right-click closes, minimizes or makes it full screen), and on the right Spaces (the Mac's
/// gestures, which the iPad does with three fingers, as a menu) and Desktop. One control drawn by
/// hand: it never takes keyboard focus, so keys keep going to the Mac. The strip scrolls with the
/// wheel or a drag and fades where it continues.
/// </summary>
sealed class MacBar : Control
{
    public event Action? AppsClicked, DesktopClicked;
    public event Action<uint>? WindowClicked;
    public event Action<uint, string>? WindowCommand;
    public event Action<string>? GestureClicked;

    // BarMetrics.regular, in points; ×dpi/96 in pixels.
    private const float BarHeight = 86, EdgePad = 22, Gap = 12, ButtonSize = 66, ButtonRadius = 16,
        ThumbWidth = 104, ThumbHeight = 66, ThumbRadius = 10, ThumbSpacing = 16, ThumbPad = 10, Badge = 24, Fade = 28;

    private enum Part { None, Apps, Spaces, Desktop, Thumb }
    private readonly record struct Hit(Part Part, uint Window = 0);

    private IReadOnlyList<WindowInfo> windows = [];
    private uint? activeWindow;
    private bool desktopActive, gesturesAvailable, appsOpen;
    private readonly Dictionary<uint, Image> thumbnails = [];
    private readonly Dictionary<string, Image> icons = [];
    private float scroll;   // the strip's offset, in pixels
    private Hit hover, pressed;
    private Point pressAt;
    private float pressScroll;
    private bool dragging;
    private readonly ToolTip tips = new() { InitialDelay = 500 };
    private readonly System.Windows.Forms.Timer tipTimer = new() { Interval = 500 };
    private Font labelFont, iconFont, badgeFont;
    private string tipText = "";

    public MacBar()
    {
        SetStyle(ControlStyles.Selectable, false);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        TabStop = false;
        Dock = DockStyle.Top;
        BackColor = Palette.Bar;
        labelFont = Palette.UiFont(11, DeviceDpi);
        iconFont = Palette.IconFont(20, DeviceDpi);
        badgeFont = Palette.UiFont(10, DeviceDpi, semibold: true);
        Height = Px(BarHeight);
        tipTimer.Tick += (_, _) => { tipTimer.Stop(); ShowTip(); };
        // The tooltip in the bar's colours, not Windows' light one.
        tips.OwnerDraw = true;
        tips.Popup += (_, e) =>
        {
            var size = TextRenderer.MeasureText(tipText, labelFont);
            e.ToolTipSize = new Size(size.Width + Px(16), size.Height + Px(10));
        };
        tips.Draw += (_, e) =>
        {
            using (var back = new SolidBrush(Palette.Control)) e.Graphics.FillRectangle(back, e.Bounds);
            using (var edge = new Pen(Palette.ControlHover)) e.Graphics.DrawRectangle(edge, 0, 0, e.Bounds.Width - 1, e.Bounds.Height - 1);
            TextRenderer.DrawText(e.Graphics, e.ToolTipText, labelFont, e.Bounds, Palette.Text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        };
    }

    private int Px(float points) => (int)Math.Round(points * DeviceDpi / 96f);
    private float S(float points) => points * DeviceDpi / 96f;

    protected override void OnDpiChangedAfterParent(EventArgs e)
    {
        base.OnDpiChangedAfterParent(e);
        labelFont.Dispose(); iconFont.Dispose(); badgeFont.Dispose();
        labelFont = Palette.UiFont(11, DeviceDpi);
        iconFont = Palette.IconFont(20, DeviceDpi);
        badgeFont = Palette.UiFont(10, DeviceDpi, semibold: true);
        Height = Px(BarHeight);
        Invalidate();
    }

    /// <summary>Whether the Apps drawer is showing (its button is lit while it is).</summary>
    public bool AppsOpen { get => appsOpen; set { appsOpen = value; Invalidate(); } }

    /// <summary>Kind 2: the windows, in the host's order, and what streams.</summary>
    public void SetWindows(IReadOnlyList<WindowInfo> windows, uint? activeWindow, bool desktopActive, bool gestures)
    {
        this.windows = windows;
        this.activeWindow = activeWindow;
        this.desktopActive = desktopActive;
        gesturesAvailable = gestures;
        var keep = windows.Select(w => w.Id).ToHashSet();
        foreach (var gone in thumbnails.Keys.Where(id => !keep.Contains(id)).ToList())
        {
            thumbnails[gone].Dispose();
            thumbnails.Remove(gone);
        }
        ClampScroll();
        Invalidate();
    }

    /// <summary>Kind 3: a window's thumbnail, refreshed every second or two.</summary>
    public void SetThumbnail(uint id, Image image)
    {
        if (thumbnails.Remove(id, out var old)) old.Dispose();
        thumbnails[id] = image;
        Invalidate(ThumbRect(id) is { } r ? Rectangle.Inflate(Rectangle.Round(r), Px(12), Px(12)) : ClientRectangle);
    }

    /// <summary>Kind 4: an app's icon, for the thumbnails' badges.</summary>
    public void SetIcon(string bundleId, Image image)
    {
        if (icons.Remove(bundleId, out var old)) old.Dispose();
        icons[bundleId] = image;
        Invalidate();
    }

    // ---- layout ----

    private float ButtonTop => (Height - S(ButtonSize)) / 2;
    private RectangleF AppsRect => new(S(EdgePad), ButtonTop, S(ButtonSize), S(ButtonSize));
    private RectangleF DesktopRect => new(Width - S(EdgePad) - S(ButtonSize), ButtonTop, S(ButtonSize), S(ButtonSize));
    private RectangleF SpacesRect => new(DesktopRect.X - S(Gap) - S(ButtonSize), ButtonTop, S(ButtonSize), S(ButtonSize));
    private RectangleF StripRect
    {
        get
        {
            float left = AppsRect.Right + S(Gap), right = SpacesRect.X - S(Gap);
            return new RectangleF(left, 0, Math.Max(0, right - left), Height);
        }
    }

    private float StripContent => windows.Count == 0 ? 0 : S(ThumbPad) * 2 + windows.Count * S(ThumbWidth) + (windows.Count - 1) * S(ThumbSpacing);

    private RectangleF? ThumbRect(uint id)
    {
        int i = windows.ToList().FindIndex(w => w.Id == id);
        return i < 0 ? null : ThumbRectAt(i);
    }

    private RectangleF ThumbRectAt(int index) =>
        new(StripRect.X + S(ThumbPad) + index * (S(ThumbWidth) + S(ThumbSpacing)) - scroll, (Height - S(ThumbHeight)) / 2, S(ThumbWidth), S(ThumbHeight));

    private void ClampScroll() => scroll = Math.Clamp(scroll, 0, Math.Max(0, StripContent - StripRect.Width));

    private Hit HitAt(Point p)
    {
        if (AppsRect.Contains(p)) return new(Part.Apps);
        if (DesktopRect.Contains(p)) return new(Part.Desktop);
        if (SpacesRect.Contains(p)) return new(Part.Spaces);
        if (StripRect.Contains(p))
            for (int i = 0; i < windows.Count; i++)
                if (ThumbRectAt(i).Contains(p)) return new(Part.Thumb, windows[i].Id);
        return new(Part.None);
    }

    // ---- drawing ----

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Palette.Bar);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;

        DrawButton(g, AppsRect, "", "Apps", appsOpen, new(Part.Apps), enabled: true);
        DrawButton(g, SpacesRect, "", "Spaces", false, new(Part.Spaces), gesturesAvailable);
        DrawButton(g, DesktopRect, "", "Desktop", desktopActive, new(Part.Desktop), enabled: true);

        var strip = StripRect;
        var state = g.Save();
        g.SetClip(strip);
        for (int i = 0; i < windows.Count; i++)
        {
            var r = ThumbRectAt(i);
            if (r.Right < strip.X - S(12) || r.X > strip.Right + S(12)) continue;
            DrawThumb(g, windows[i], r);
        }
        // Where the strip continues, it fades into the bar.
        if (scroll > 0.5f) FadeEdge(g, new RectangleF(strip.X, 0, S(Fade), Height), LinearGradientMode.Horizontal, leftToRight: true);
        if (scroll < StripContent - strip.Width - 0.5f) FadeEdge(g, new RectangleF(strip.Right - S(Fade), 0, S(Fade), Height), LinearGradientMode.Horizontal, leftToRight: false);
        g.Restore(state);
    }

    private void FadeEdge(Graphics g, RectangleF r, LinearGradientMode mode, bool leftToRight)
    {
        var solid = Palette.Bar;
        var clear = Color.FromArgb(0, solid);
        using var brush = new LinearGradientBrush(new RectangleF(r.X - 1, r.Y, r.Width + 2, r.Height), leftToRight ? solid : clear, leftToRight ? clear : solid, mode);
        g.FillRectangle(brush, r);
    }

    private void DrawButton(Graphics g, RectangleF r, string glyph, string label, bool open, Hit which, bool enabled)
    {
        Color fill = open ? Palette.ControlOpen : Palette.Control;
        if (enabled && pressed == which && hover == which) fill = Palette.ControlPressed;
        else if (enabled && hover == which && !open) fill = Palette.ControlHover;
        Palette.FillRounded(g, fill, r, S(ButtonRadius));
        // The icon over its label, as the iPad's: a 4 pt gap, the pair centred.
        int iconH = iconFont.Height, labelH = labelFont.Height;
        float total = iconH + S(2) + labelH, y = r.Y + (r.Height - total) / 2;
        var text = enabled ? Palette.Text : Palette.Muted;
        TextRenderer.DrawText(g, glyph, iconFont, Rectangle.Round(new RectangleF(r.X, y, r.Width, iconH)), text,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoClipping);
        TextRenderer.DrawText(g, label, labelFont, Rectangle.Round(new RectangleF(r.X, y + iconH + S(2), r.Width, labelH)),
            enabled ? Palette.BarLabel : Palette.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoClipping);
    }

    private void DrawThumb(Graphics g, WindowInfo w, RectangleF r)
    {
        float radius = S(ThumbRadius);
        using (var path = Palette.Rounded(r, radius))
        {
            var state = g.Save();
            g.SetClip(path, CombineMode.Intersect);
            if (thumbnails.TryGetValue(w.Id, out var img))
            {
                // Aspect fill, as the iPad's thumbnails: the window's middle, cropped to the card.
                float s = Math.Max(r.Width / img.Width, r.Height / img.Height);
                float iw = img.Width * s, ih = img.Height * s;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(img, r.X + (r.Width - iw) / 2, r.Y + (r.Height - ih) / 2, iw, ih);
            }
            else
            {
                using var body = new SolidBrush(Palette.ThumbBody);
                using var titleBar = new SolidBrush(Palette.ThumbTitleBar);
                g.FillRectangle(body, r);
                g.FillRectangle(titleBar, r.X, r.Y, r.Width, S(9));
            }
            if (hover.Part == Part.Thumb && hover.Window == w.Id)
                using (var lighten = new SolidBrush(Color.FromArgb(28, 255, 255, 255))) g.FillRectangle(lighten, r);
            g.Restore(state);
            using var edge = new Pen(Color.FromArgb(31, 255, 255, 255), S(1));
            g.DrawPath(edge, path);
        }
        if (w.Id == activeWindow)
        {
            // The halo: 2 pt of accent, 3 pt clear of the card, following its radius.
            float inset = S(5) - S(1);
            using var halo = Palette.Rounded(RectangleF.Inflate(r, inset, inset), radius + S(5));
            using var pen = new Pen(Palette.Accent, S(2));
            g.DrawPath(pen, halo);
        }
        DrawBadge(g, w, new PointF(r.X - S(6), r.Bottom + S(6) - S(Badge)));
    }

    // The app's icon at the card's bottom-left corner, in a 2 pt ring of the bar's colour so it cuts
    // through the card's edge and its halo.
    private void DrawBadge(Graphics g, WindowInfo w, PointF at)
    {
        float size = S(Badge), corner = MathF.Round(Badge * 0.29f) * DeviceDpi / 96f;
        Palette.FillRounded(g, Palette.Bar, new RectangleF(at.X - S(2), at.Y - S(2), size + S(4), size + S(4)), corner + S(2));
        var r = new RectangleF(at.X, at.Y, size, size);
        if (w.BundleId is { } id && icons.TryGetValue(id, out var icon))
        {
            using var path = Palette.Rounded(r, corner);
            var state = g.Save();
            g.SetClip(path, CombineMode.Intersect);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(icon, r);
            g.Restore(state);
        }
        else
        {
            Palette.FillRounded(g, Palette.IconFallback, r, corner);
            string letters = (w.AppName ?? "?").Length >= 2 ? (w.AppName ?? "?")[..2] : w.AppName ?? "?";
            TextRenderer.DrawText(g, letters, badgeFont, Rectangle.Round(r), Color.White,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    // ---- input ----

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (pressed.Part == Part.Thumb || (pressed.Part == Part.None && e.Button == MouseButtons.Left && StripRect.Contains(pressAt)))
        {
            if (!dragging && Math.Abs(e.X - pressAt.X) > S(4)) dragging = true;
            if (dragging) { scroll = pressScroll - (e.X - pressAt.X); ClampScroll(); Invalidate(); return; }
        }
        var hit = HitAt(e.Location);
        if (hit != hover)
        {
            hover = hit;
            tips.Hide(this);
            tipTimer.Stop();
            if (hit.Part != Part.None) tipTimer.Start();
            Invalidate();
        }
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        hover = default;
        tipTimer.Stop();
        tips.Hide(this);
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        tipTimer.Stop();
        tips.Hide(this);
        pressAt = e.Location;
        pressScroll = scroll;
        dragging = false;
        pressed = e.Button == MouseButtons.Left ? HitAt(e.Location) : default;
        Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        var hit = HitAt(e.Location);
        var was = pressed;
        bool dragged = dragging;
        pressed = default;
        dragging = false;
        Invalidate();
        if (e.Button == MouseButtons.Right && hit.Part == Part.Thumb) { WindowMenu(hit.Window).Show(this, e.Location); return; }
        if (e.Button != MouseButtons.Left || dragged || hit != was) return;
        switch (hit.Part)
        {
            case Part.Apps: AppsClicked?.Invoke(); break;
            case Part.Desktop: DesktopClicked?.Invoke(); break;
            case Part.Spaces when gesturesAvailable: SpacesMenu().Show(this, Point.Round(new PointF(SpacesRect.X, SpacesRect.Bottom + S(6)))); break;
            case Part.Thumb: WindowClicked?.Invoke(hit.Window); break;
        }
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        // Over the strip the wheel scrolls it, a notch a thumbnail; elsewhere on the bar it does nothing.
        if (StripContent > StripRect.Width)
        {
            scroll -= e.Delta / 120f * (S(ThumbWidth) + S(ThumbSpacing));
            ClampScroll();
            Invalidate();
        }
        if (e is HandledMouseEventArgs handled) handled.Handled = true;
    }

    private ContextMenuStrip WindowMenu(uint id)
    {
        var menu = Palette.Menu();
        menu.Items.Add("Close", null, (_, _) => WindowCommand?.Invoke(id, "close"));
        menu.Items.Add("Minimize", null, (_, _) => WindowCommand?.Invoke(id, "minimize"));
        menu.Items.Add("Full Screen", null, (_, _) => WindowCommand?.Invoke(id, "fullScreen"));
        return menu;
    }

    private ContextMenuStrip SpacesMenu()
    {
        var menu = Palette.Menu();
        foreach (var (text, gesture) in new[]
        {
            ("Mission Control", Gestures.MissionControl),
            ("App Exposé", Gestures.AppExpose),
            ("Space on the Left", Gestures.SpaceLeft),
            ("Space on the Right", Gestures.SpaceRight),
            ("Show Desktop", Gestures.ShowDesktop),
            ("Launchpad", Gestures.Apps),
        })
            menu.Items.Add(text, null, (_, _) => GestureClicked?.Invoke(gesture));
        return menu;
    }

    private void ShowTip()
    {
        string? text = hover.Part switch
        {
            Part.Apps => "Your Mac's apps: open one",
            Part.Desktop => "Stream the whole Desktop",
            Part.Spaces => gesturesAvailable ? "Mission Control, the Spaces, Show Desktop" : "This Mac doesn't take gestures (update Sill on it)",
            Part.Thumb => windows.FirstOrDefault(w => w.Id == hover.Window) is { } w
                ? (string.IsNullOrEmpty(w.Title) ? w.AppName : $"{w.AppName} — {w.Title}") : null,
            _ => null,
        };
        if (text is null) return;
        tipText = text;
        var r = hover.Part switch
        {
            Part.Apps => AppsRect, Part.Desktop => DesktopRect, Part.Spaces => SpacesRect,
            _ => ThumbRect(hover.Window) ?? RectangleF.Empty,
        };
        tips.Show(text, this, (int)r.X, (int)(r.Bottom + S(10)), 4000);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            foreach (var i in thumbnails.Values) i.Dispose();
            foreach (var i in icons.Values) i.Dispose();
            labelFont.Dispose(); iconFont.Dispose(); badgeFont.Dispose();
            tips.Dispose(); tipTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
