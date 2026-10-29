using System.Drawing;

namespace Sill.Protocol.Tests;

public class WindowPlacementTests
{
    private static readonly Rectangle Laptop = new(0, 0, 1920, 1032), Monitor = new(1920, 0, 2560, 1400);
    private static readonly Size Default = new(1280, 800);

    [Fact]
    public void AWindowStillOnAScreenOpensWhereItWas() =>
        Assert.Equal(new Rectangle(2000, 100, 1600, 900), WindowPlacement.Fit(new(2000, 100, 1600, 900, false, false), [Laptop, Monitor], Default));

    [Fact]
    public void AWindowOnAScreenThatWentOpensCentredOnTheMainOne() =>
        Assert.Equal(new Rectangle(320, 116, 1280, 800), WindowPlacement.Fit(new(2000, 100, 1600, 900, false, false), [Laptop], Default));

    [Fact]
    public void ATitleBarOffTheTopOrNearlyOffTheSideCountsAsGone()
    {
        Assert.Equal(new Rectangle(320, 116, 1280, 800), WindowPlacement.Fit(new(100, -200, 800, 600, false, false), [Laptop], Default));
        Assert.Equal(new Rectangle(320, 116, 1280, 800), WindowPlacement.Fit(new(1900, 100, 800, 600, false, false), [Laptop], Default));
    }

    [Fact]
    public void ASizeLargerThanItsScreenShrinksToIt() =>
        Assert.Equal(new Rectangle(0, 0, 1920, 1032), WindowPlacement.Fit(new(0, 0, 2560, 1400, false, false), [Laptop], Default));

    [Fact]
    public void NothingSavedOpensCentred() =>
        Assert.Equal(new Rectangle(320, 116, 1280, 800), WindowPlacement.Fit(null, [Laptop], Default));

    [Fact]
    public void SavesAndLoads()
    {
        string path = Path.Combine(Path.GetTempPath(), $"sill-window-{Guid.NewGuid():N}.json");
        try
        {
            var p = new WindowPlacement(10, 20, 1000, 700, true, false, true);
            p.Save(path);
            Assert.Equal(p, WindowPlacement.Load(path));
            Assert.Null(WindowPlacement.Load(path + ".missing"));
        }
        finally { File.Delete(path); }
    }
}
