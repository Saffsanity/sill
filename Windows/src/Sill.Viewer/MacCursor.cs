using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace Sill.Viewer;

/// <summary>
/// The Mac's cursor (kind 14: its image, hotspot and size in Mac points) as a Windows cursor, drawn
/// at Windows' own scale (a Mac point is a Windows logical pixel, as the iPad draws it 1:1 in its
/// points), so an I-beam over text or a hand over a link looks as it does on the Mac. The Mac leaves
/// its cursor out of the video, so without this the picture shows Windows' arrow everywhere.
/// </summary>
sealed class MacCursor : IDisposable
{
    public Cursor Cursor { get; }
    private IntPtr handle;

    private MacCursor(IntPtr handle) { this.handle = handle; Cursor = new Cursor(handle); }

    /// <summary>Null when the PNG doesn't load or the result would be empty.</summary>
    public static MacCursor? Create(byte[] png, float hotX, float hotY, float width, float height, int dpi)
    {
        Bitmap source;
        try { using var ms = new MemoryStream(png); using var loaded = Image.FromStream(ms); source = new Bitmap(loaded); }
        catch (Exception e) when (e is ArgumentException or ExternalException) { return null; }
        using (source)
        {
            float scale = dpi / 96f;
            int w = Math.Clamp((int)MathF.Round(width * scale), 1, 256), h = Math.Clamp((int)MathF.Round(height * scale), 1, 256);
            using var sized = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(sized))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(source, 0, 0, w, h);
            }
            // An icon from the bitmap keeps its alpha; its info, with the Mac's hotspot and as a
            // cursor, makes the cursor.
            IntPtr icon = sized.GetHicon();
            try
            {
                if (!GetIconInfo(icon, out var info)) return null;
                try
                {
                    info.IsIcon = false;
                    info.HotX = Math.Clamp((int)MathF.Round(hotX * scale), 0, w - 1);
                    info.HotY = Math.Clamp((int)MathF.Round(hotY * scale), 0, h - 1);
                    IntPtr cursor = CreateIconIndirect(ref info);
                    return cursor == IntPtr.Zero ? null : new MacCursor(cursor);
                }
                finally
                {
                    if (info.Mask != IntPtr.Zero) DeleteObject(info.Mask);
                    if (info.Color != IntPtr.Zero) DeleteObject(info.Color);
                }
            }
            finally { DestroyIcon(icon); }
        }
    }

    public void Dispose()
    {
        if (handle == IntPtr.Zero) return;
        Cursor.Dispose();
        DestroyCursor(handle);   // a Cursor made from a handle does not own it
        handle = IntPtr.Zero;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IconInfo { [MarshalAs(UnmanagedType.Bool)] public bool IsIcon; public int HotX, HotY; public IntPtr Mask, Color; }

    [DllImport("user32.dll")] private static extern bool GetIconInfo(IntPtr icon, out IconInfo info);
    [DllImport("user32.dll")] private static extern IntPtr CreateIconIndirect(ref IconInfo info);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern bool DestroyCursor(IntPtr cursor);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);
}
