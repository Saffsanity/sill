namespace Sill.Protocol;

/// <summary>
/// A mouse wheel as a trackpad scroll. A Windows wheel notch is one jump, so sent as one delta the
/// Mac's content moves once per notch and repaints once: scrolling looks steppy whatever the
/// stream's frame rate. This spreads each notch over a short eased glide, a delta per tick (60 a
/// second), and brackets a run of them with the scroll gesture's began and ended, as the iPad's
/// finger scrolling is, so the Mac's apps scroll smoothly (and rubber-band at an edge). Notches
/// that come while a glide runs add to it; a precision touchpad's small, frequent deltas glide the
/// same way. Every bit of distance asked for is sent: the deltas of a glide add up to its notches.
/// Pure: the caller gives the time and sends what comes out. Not thread-safe.
/// </summary>
public sealed class WheelGlide
{
    public abstract record Output(double X, double Y);
    public sealed record Began(double X, double Y) : Output(X, Y);
    public sealed record Delta(double X, double Y, double Dx, double Dy) : Output(X, Y);
    public sealed record Ended(double X, double Y) : Output(X, Y);

    /// <summary>How fast a glide eases out: the distance still to go falls by e every this many seconds.</summary>
    public double TimeConstant { get; init; } = 0.045;

    /// <summary>How long the gesture stays open after the last delta, so a quick run of notches is one gesture.</summary>
    public double HoldOpen { get; init; } = 0.08;

    /// <summary>Distance left under this (a fraction of the frame, about a third of a Mac point at
    /// 1080) goes out at once rather than easing on.</summary>
    public double Settle { get; init; } = 0.0003;

    private double pendingX, pendingY, x, y, lastTick, lastInput;
    public bool Active { get; private set; }

    /// <summary>A wheel's movement at (x, y), as frame fractions in the protocol's natural sign.
    /// Returns the gesture's began when this starts one.</summary>
    public IReadOnlyList<Output> Wheel(double dx, double dy, double atX, double atY, double now)
    {
        x = atX; y = atY;
        pendingX += dx; pendingY += dy;
        lastInput = now;
        if (Active) return [];
        Active = true;
        lastTick = now;
        return [new Began(x, y)];
    }

    /// <summary>One tick: the next eased step of the glide, and the gesture's end once it has come
    /// to rest and nothing more came for <see cref="HoldOpen"/>.</summary>
    public IReadOnlyList<Output> Tick(double now)
    {
        if (!Active) return [];
        double dt = Math.Max(0, now - lastTick);
        lastTick = now;
        var outputs = new List<Output>(2);
        if (pendingX != 0 || pendingY != 0)
        {
            double share = 1 - Math.Exp(-dt / TimeConstant);
            double sx = pendingX * share, sy = pendingY * share;
            if (Math.Abs(pendingX - sx) < Settle) sx = pendingX;
            if (Math.Abs(pendingY - sy) < Settle) sy = pendingY;
            pendingX -= sx; pendingY -= sy;
            if (sx != 0 || sy != 0) outputs.Add(new Delta(x, y, sx, sy));
        }
        if (pendingX == 0 && pendingY == 0 && now - lastInput >= HoldOpen)
        {
            Active = false;
            outputs.Add(new Ended(x, y));
        }
        return outputs;
    }

    /// <summary>Ends a glide at once (the window lost the pointer, the session ended): the rest of
    /// its distance in one delta, then the end, so the Mac never keeps an open gesture.</summary>
    public IReadOnlyList<Output> Finish()
    {
        if (!Active) return [];
        var outputs = new List<Output>(2);
        if (pendingX != 0 || pendingY != 0) outputs.Add(new Delta(x, y, pendingX, pendingY));
        pendingX = pendingY = 0;
        Active = false;
        outputs.Add(new Ended(x, y));
        return outputs;
    }
}
