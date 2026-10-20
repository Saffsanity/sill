using System.Drawing;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>
/// Where the viewer's window was when it closed (and This PC's settings: decoding, the clipboard), kept beside the device's key (<c>window.json</c>),
/// and where it goes at the next start: as it was if it still lands on a screen, else at the
/// default size centred on the main one (a display unplugged, a resolution changed). Pure.
/// </summary>
public sealed record WindowPlacement(
    [property: JsonPropertyName("x")] int X,
    [property: JsonPropertyName("y")] int Y,
    [property: JsonPropertyName("width")] int Width,
    [property: JsonPropertyName("height")] int Height,
    [property: JsonPropertyName("maximized")] bool Maximized,
    [property: JsonPropertyName("fullScreen")] bool FullScreen,
    [property: JsonPropertyName("softwareDecoding")] bool SoftwareDecoding = false,
    [property: JsonPropertyName("shareClipboard")] bool ShareClipboard = true)
{
    [JsonIgnore] public Rectangle Bounds => new(X, Y, Width, Height);

    /// <summary>The bounds to open at: the saved ones while enough of the title bar (the top
    /// <paramref name="grab"/> pixels, at least <paramref name="grab"/> wide) is on one of the
    /// <paramref name="screens"/>' working areas to drag it by, its size no larger than that
    /// screen; else <paramref name="fallback"/> centred on the first screen.</summary>
    public static Rectangle Fit(WindowPlacement? saved, IReadOnlyList<Rectangle> screens, Size fallback, int grab = 48)
    {
        if (screens.Count == 0) return new Rectangle(Point.Empty, fallback);
        if (saved is { Width: > 0, Height: > 0 })
        {
            var titleBar = new Rectangle(saved.X, saved.Y, saved.Width, grab);
            foreach (var area in screens)
            {
                var shown = Rectangle.Intersect(titleBar, area);
                if (shown.Width >= grab && shown.Height >= grab / 2)
                    return new Rectangle(saved.X, saved.Y, Math.Min(saved.Width, area.Width), Math.Min(saved.Height, area.Height));
            }
        }
        var main = screens[0];
        var size = new Size(Math.Min(fallback.Width, main.Width), Math.Min(fallback.Height, main.Height));
        return new Rectangle(main.X + (main.Width - size.Width) / 2, main.Y + (main.Height - size.Height) / 2, size.Width, size.Height);
    }

    public static WindowPlacement? Load(string path)
    {
        try { return JsonSerializer.Deserialize<WindowPlacement>(File.ReadAllText(path)); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return null; }
    }

    public void Save(string path)
    {
        try { File.WriteAllText(path, JsonSerializer.Serialize(this)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
