using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The bar across the top, as the iPad's landscape bar: Apps, the Desktop, a thumbnail for each
/// Mac window (click streams it; right-click for close, minimize, full screen), and the Mac's own
/// gestures as buttons (Mission Control, App Exposé, the Spaces, Show Desktop, Launchpad), which
/// the host turns into the Mac's shortcuts. Nothing in it takes keyboard focus, so keys keep going
/// to the Mac.
/// </summary>
sealed class MacBar : Panel
{
    public event Action? AppsClicked, DesktopClicked;
    public event Action<uint>? WindowClicked;
    public event Action<uint, string>? WindowCommand;
    public event Action<string>? GestureClicked;

    private static readonly Color Back = Color.FromArgb(28, 28, 30), LitColor = Color.FromArgb(10, 132, 255);
    private readonly FlowLayoutPanel strip;
    private readonly BarButton desktop;
    private readonly List<BarButton> gestureButtons = [];
    private readonly Dictionary<uint, ThumbButton> thumbs = [];
    private readonly ToolTip tips = new();

    public MacBar()
    {
        Dock = DockStyle.Top;
        BackColor = Back;
        Height = LogicalToDeviceUnits(64);
        Padding = new Padding(LogicalToDeviceUnits(6));

        var left = new FlowLayoutPanel { Dock = DockStyle.Left, AutoSize = true, WrapContents = false, BackColor = Back, Padding = Padding.Empty };
        var apps = Button("Apps", "Your Mac's apps: open one", () => AppsClicked?.Invoke());
        desktop = Button("Desktop", "Stream the whole Desktop", () => DesktopClicked?.Invoke());
        left.Controls.AddRange([apps, desktop]);

        var right = new FlowLayoutPanel { Dock = DockStyle.Right, AutoSize = true, WrapContents = false, BackColor = Back, Padding = Padding.Empty };
        foreach (var (text, tip, gesture) in new[]
        {
            ("Mission Control", "Mission Control (a three-finger swipe up)", Gestures.MissionControl),
            ("App Exposé", "This app's windows (a three-finger swipe down)", Gestures.AppExpose),
            ("◀ Space", "The Space on the left", Gestures.SpaceLeft),
            ("Space ▶", "The Space on the right", Gestures.SpaceRight),
            ("Show Desktop", "Move the windows aside", Gestures.ShowDesktop),
            ("Launchpad", "All apps (Launchpad)", Gestures.Apps),
        })
        {
            var b = Button(text, tip, () => GestureClicked?.Invoke(gesture));
            gestureButtons.Add(b);
            right.Controls.Add(b);
        }

        strip = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false, AutoScroll = true, BackColor = Back, Padding = new Padding(LogicalToDeviceUnits(8), 0, 0, 0) };
        Controls.Add(strip);
        Controls.Add(right);
        Controls.Add(left);
    }

    private BarButton Button(string text, string tip, Action click)
    {
        var b = new BarButton(text) { Height = Height - Padding.Vertical, Margin = new Padding(LogicalToDeviceUnits(2), 0, LogicalToDeviceUnits(2), 0) };
        b.Click += (_, _) => click();
        tips.SetToolTip(b, tip);
        return b;
    }

    /// <summary>Kind 2: the windows, in the host's order, and what streams.</summary>
    public void SetWindows(IReadOnlyList<WindowInfo> windows, uint? activeWindow, bool desktopActive, bool gestures)
    {
        desktop.Lit = desktopActive;
        foreach (var b in gestureButtons) b.Enabled = gestures;
        var keep = windows.Select(w => w.Id).ToHashSet();
        foreach (var gone in thumbs.Keys.Where(id => !keep.Contains(id)).ToList())
        {
            strip.Controls.Remove(thumbs[gone]);
            thumbs[gone].Dispose();
            thumbs.Remove(gone);
        }
        int index = 0;
        foreach (var w in windows)
        {
            if (!thumbs.TryGetValue(w.Id, out var t))
            {
                t = new ThumbButton(w.Id) { Size = new Size(LogicalToDeviceUnits(132), Height - Padding.Vertical - SystemInformation.HorizontalScrollBarHeight), Margin = new Padding(LogicalToDeviceUnits(3), 0, LogicalToDeviceUnits(3), 0) };
                t.MouseUp += (_, e) =>
                {
                    if (e.Button == MouseButtons.Left) WindowClicked?.Invoke(t.WindowId);
                    else if (e.Button == MouseButtons.Right) Menu(t).Show(t, e.Location);
                };
                thumbs[w.Id] = t;
                strip.Controls.Add(t);
            }
            t.AppName = w.AppName ?? "";
            t.Title = w.Title ?? "";
            t.Lit = w.Id == activeWindow;
            tips.SetToolTip(t, string.IsNullOrEmpty(w.Title) ? w.AppName : $"{w.AppName} — {w.Title}");
            strip.Controls.SetChildIndex(t, index++);
            t.Invalidate();
        }
    }

    private ContextMenuStrip Menu(ThumbButton t)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Close", null, (_, _) => WindowCommand?.Invoke(t.WindowId, "close"));
        menu.Items.Add("Minimize", null, (_, _) => WindowCommand?.Invoke(t.WindowId, "minimize"));
        menu.Items.Add("Full Screen", null, (_, _) => WindowCommand?.Invoke(t.WindowId, "fullScreen"));
        return menu;
    }

    /// <summary>Kind 3: a window's thumbnail, refreshed every second or two.</summary>
    public void SetThumbnail(uint id, Image image)
    {
        if (thumbs.TryGetValue(id, out var t)) { t.Thumbnail?.Dispose(); t.Thumbnail = image; t.Invalidate(); }
        else image.Dispose();
    }

    /// <summary>A button that never takes focus, so keys stay the Mac's.</summary>
    internal sealed class BarButton : Button
    {
        private bool lit;
        public bool Lit { get => lit; set { lit = value; BackColor = value ? LitColor : Color.FromArgb(58, 58, 60); } }

        public BarButton(string text)
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
            Text = text;
            AutoSize = true;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            ForeColor = Color.White;
            Lit = false;
            Font = new Font("Segoe UI", 9f);
        }
    }

    /// <summary>A window's thumbnail and app name; lit while it streams.</summary>
    internal sealed class ThumbButton : Control
    {
        public uint WindowId { get; }
        public Image? Thumbnail { get; set; }
        public string AppName { get; set; } = "";
        public string Title { get; set; } = "";
        public bool Lit { get; set; }

        public ThumbButton(uint id)
        {
            WindowId = id;
            SetStyle(ControlStyles.Selectable, false);
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            TabStop = false;
            Cursor = Cursors.Hand;
            Font = new Font("Segoe UI", 8f);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Back);
            int label = Font.Height + 2;
            var area = new Rectangle(0, 0, Width, Height - label);
            using (var frame = new SolidBrush(Color.FromArgb(44, 44, 46))) g.FillRectangle(frame, area);
            if (Thumbnail is { } img)
            {
                float s = Math.Min((float)area.Width / img.Width, (float)area.Height / img.Height);
                int w = (int)(img.Width * s), h = (int)(img.Height * s);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
                g.DrawImage(img, area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h);
            }
            if (Lit) using (var pen = new Pen(LitColor, 3)) g.DrawRectangle(pen, 1, 1, Width - 3, Height - label - 3);
            TextRenderer.DrawText(g, AppName, Font, new Rectangle(0, Height - label, Width, label), Color.Gainsboro,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }
}
