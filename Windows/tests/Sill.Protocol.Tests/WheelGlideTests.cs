namespace Sill.Protocol.Tests;

/// <summary>Ticket 08: a wheel notch as a glide the Mac reads as a trackpad scroll.</summary>
public class WheelGlideTests
{
    private static List<WheelGlide.Output> Run(WheelGlide glide, double from, double until, double step = 1 / 60.0)
    {
        var all = new List<WheelGlide.Output>();
        for (double t = from; t <= until + 1e-9; t += step) all.AddRange(glide.Tick(t));
        return all;
    }

    [Fact]
    public void ANotchGlidesThenEndsAndAddsUpExactly()
    {
        var glide = new WheelGlide();
        var start = glide.Wheel(0, 0.04, 0.5, 0.25, 0);
        Assert.IsType<WheelGlide.Began>(Assert.Single(start));
        var rest = Run(glide, 1 / 60.0, 1);
        var deltas = rest.OfType<WheelGlide.Delta>().ToList();
        Assert.True(deltas.Count >= 5, $"{deltas.Count} steps: a glide, not a jump");
        Assert.Equal(0.04, deltas.Sum(d => d.Dy), 12);
        Assert.All(deltas, d => Assert.Equal(0, d.Dx));
        // Eased: each step no bigger than the one before, but the last, which takes the sub-point rest.
        for (int i = 1; i < deltas.Count - 1; i++) Assert.True(deltas[i].Dy <= deltas[i - 1].Dy + 1e-12, $"step {i}");
        Assert.True(deltas[^1].Dy < 0.0006);
        // Most of the notch lands in the first ~100 ms.
        Assert.True(deltas.Take(6).Sum(d => d.Dy) > 0.035);
        Assert.IsType<WheelGlide.Ended>(rest[^1]);
        Assert.Single(rest.OfType<WheelGlide.Ended>());
        Assert.False(glide.Active);
        Assert.Empty(glide.Tick(2));
    }

    [Fact]
    public void NotchesDuringAGlideJoinIt()
    {
        var glide = new WheelGlide();
        var outputs = new List<WheelGlide.Output>(glide.Wheel(0, -0.04, 0.3, 0.3, 0));
        outputs.AddRange(Run(glide, 1 / 60.0, 0.05));
        outputs.AddRange(glide.Wheel(0, -0.04, 0.3, 0.3, 0.06));
        outputs.AddRange(glide.Wheel(0.02, -0.04, 0.3, 0.3, 0.07));
        outputs.AddRange(Run(glide, 0.08, 1.5));
        Assert.Single(outputs.OfType<WheelGlide.Began>());
        Assert.Single(outputs.OfType<WheelGlide.Ended>());
        Assert.IsType<WheelGlide.Began>(outputs[0]);
        Assert.IsType<WheelGlide.Ended>(outputs[^1]);
        Assert.Equal(-0.12, outputs.OfType<WheelGlide.Delta>().Sum(d => d.Dy), 12);
        Assert.Equal(0.02, outputs.OfType<WheelGlide.Delta>().Sum(d => d.Dx), 12);
    }

    [Fact]
    public void TheGestureStaysOpenBetweenQuickNotchesAndClosesAfterAPause()
    {
        var glide = new WheelGlide();
        glide.Wheel(0, 0.04, 0.5, 0.5, 0);
        var first = Run(glide, 1 / 60.0, 1);
        Assert.IsType<WheelGlide.Ended>(first[^1]);
        // A notch a second later starts a new gesture.
        Assert.IsType<WheelGlide.Began>(Assert.Single(glide.Wheel(0, 0.04, 0.5, 0.5, 2)));
    }

    [Fact]
    public void FinishSendsTheRestThenEnds()
    {
        var glide = new WheelGlide();
        glide.Wheel(0, 0.1, 0.5, 0.5, 0);
        var some = glide.Tick(1 / 60.0).OfType<WheelGlide.Delta>().Sum(d => d.Dy);
        var finish = glide.Finish();
        Assert.IsType<WheelGlide.Ended>(finish[^1]);
        Assert.Equal(0.1, some + finish.OfType<WheelGlide.Delta>().Sum(d => d.Dy), 12);
        Assert.Empty(glide.Finish());
    }

    [Fact]
    public void ScrollGestureMatchesSwiftsEncoding()
    {
        var bytes = InputMessages.ScrollGesture(InputMessages.ScrollPhase.MomentumBegan, 0.5, 0.25);
        Assert.Equal("""{"scrollGesture":{"_0":"momentumBegan","x":0.5,"y":0.25}}""", System.Text.Encoding.UTF8.GetString(bytes, 14, bytes.Length - 14));
    }
}
