using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace Sill.Viewer;

/// <summary>
/// The iPad app's colours (iOSClient/StreamScreen.swift's <c>Palette</c>), its type in Windows'
/// fonts, and the small drawing helpers the bar, the drawer and the menus share.
/// </summary>
static class Palette
{
    public static readonly Color Bar = Hex(0x16181C);          // top bar and drawer background
    public static readonly Color Control = Hex(0x23262C);      // bar buttons, search field, selected row
    public static readonly Color ControlOpen = Hex(0x2C3550);  // a bar button whose thing is showing
    public static readonly Color ControlHover = Hex(0x2B2F36); // Windows only: the pointer over a control
    public static readonly Color ControlPressed = Hex(0x1C1F24);
    public static readonly Color Accent = Hex(0x9BB7FF);
    public static readonly Color Text = Hex(0xEEF0F3);
    public static readonly Color BarLabel = Hex(0xC4C9D1);     // the small labels under the bar icons
    public static readonly Color Muted = Hex(0xA4ABB5);        // section headers, placeholder
    public static readonly Color Panel = Hex(0x1F2126);        // behind the picture
    public static readonly Color ThumbBody = Hex(0x26282D);    // thumbnail placeholder
    public static readonly Color ThumbTitleBar = Hex(0x34373D);
    public static readonly Color IconFallback = Hex(0x3A3D44);  // two-letter app badge

    public static Color Hex(int rgb) => Color.FromArgb((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);

    /// <summary>Windows 11's Segoe UI Variable where it is installed, else Segoe UI; size in pixels
    /// at 96 dpi, scaled by <paramref name="dpi"/>.</summary>
    public static Font UiFont(float pixels, int dpi, bool semibold = false)
    {
        string family = semibold
            ? (Has("Segoe UI Variable Display Semibold") ? "Segoe UI Variable Display Semibold" : "Segoe UI Semibold")
            : (Has("Segoe UI Variable Text") ? "Segoe UI Variable Text" : "Segoe UI");
        return new Font(family, pixels * dpi / 96f, GraphicsUnit.Pixel);
    }

    /// <summary>The icon font: Segoe Fluent Icons on Windows 11, Segoe MDL2 Assets on 10 (the same code points).</summary>
    public static Font IconFont(float pixels, int dpi) =>
        new(Has("Segoe Fluent Icons") ? "Segoe Fluent Icons" : "Segoe MDL2 Assets", pixels * dpi / 96f, GraphicsUnit.Pixel);

    private static readonly HashSet<string> families = FontFamily.Families.Select(f => f.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
    private static bool Has(string family) => families.Contains(family);

    public static GraphicsPath Rounded(RectangleF r, float radius)
    {
        var path = new GraphicsPath();
        float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        if (d <= 0) { path.AddRectangle(r); return path; }
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    public static void FillRounded(Graphics g, Color color, RectangleF r, float radius)
    {
        using var path = Rounded(r, radius);
        using var brush = new SolidBrush(color);
        g.FillPath(brush, path);
    }

    /// <summary>A dark context menu, as the bar's: the iPad's colours on Windows' menu.</summary>
    public static ContextMenuStrip Menu()
    {
        var menu = new ContextMenuStrip { Renderer = new DarkRenderer(), ShowImageMargin = false, BackColor = Bar, ForeColor = Text };
        menu.Font = UiFont(13, menu.DeviceDpi);
        return menu;
    }

    private sealed class DarkRenderer() : ToolStripProfessionalRenderer(new DarkColors())
    {
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? Text : Muted;
            base.OnRenderItemText(e);
        }
    }

    private sealed class DarkColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground => Bar;
        public override Color MenuBorder => Control;
        public override Color MenuItemBorder => ControlHover;
        public override Color MenuItemSelected => ControlHover;
        public override Color MenuItemSelectedGradientBegin => ControlHover;
        public override Color MenuItemSelectedGradientEnd => ControlHover;
        public override Color SeparatorDark => Control;
        public override Color SeparatorLight => Control;
        public override Color ImageMarginGradientBegin => Bar;
        public override Color ImageMarginGradientMiddle => Bar;
        public override Color ImageMarginGradientEnd => Bar;
    }

    /// <summary>The window's title bar dark and in the bar's colour, so the two read as one (Windows
    /// 11; Windows 10 takes the dark mode alone).</summary>
    public static void DarkTitleBar(IntPtr hwnd)
    {
        int on = 1;
        DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, ref on, sizeof(int));
        int caption = ColorRef(Bar), text = ColorRef(Text);
        DwmSetWindowAttribute(hwnd, 35 /* DWMWA_CAPTION_COLOR */, ref caption, sizeof(int));
        DwmSetWindowAttribute(hwnd, 36 /* DWMWA_TEXT_COLOR */, ref text, sizeof(int));
    }

    private static int ColorRef(Color c) => c.R | c.G << 8 | c.B << 16;

    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
