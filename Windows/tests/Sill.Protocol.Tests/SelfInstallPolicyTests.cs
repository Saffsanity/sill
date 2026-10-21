using D = Sill.Protocol.SelfInstallPolicy.Decision;
using S = Sill.Protocol.SelfInstallPolicy;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 10d: where Sill.exe installs itself and what it offers at a start.</summary>
public class SelfInstallPolicyTests
{
    private const string Local = @"C:\Users\jo\AppData\Local";
    private static readonly string Installed = S.InstalledPath(Local);
    private static SillVersion V(string s) => SillVersion.Parse(s)!;

    [Fact]
    public void Paths()
    {
        Assert.Equal(@"C:\Users\jo\AppData\Local\Programs\Sill\Sill.exe", Installed);
        Assert.Equal(@"C:\Users\jo\AppData\Local\Programs\Sill", S.InstallDir(Local + @"\"));
        Assert.Equal(@"C:\Users\jo\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Sill.lnk",
            S.ShortcutPath(@"C:\Users\jo\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"));
        Assert.Equal(@"C:\Users\jo\AppData\Local\Sill\install.json", S.StatePath(Local));
        Assert.True(S.SamePath(Installed, @"c:/users/JO/appdata/local/programs/sill/SILL.EXE"));
        Assert.True(S.SamePath(Installed, @"\\?\" + Installed));
        Assert.True(S.SamePath(@"C:\x\", @"C:\x"));
        Assert.False(S.SamePath(Installed, @"C:\Users\jo\Downloads\Sill.exe"));
    }

    [Theory]
    [InlineData(@"C:\Users\jo\Downloads\Sill.exe", 0, null, true)]
    [InlineData(@"C:\Users\jo\Downloads\sill.EXE", 0, null, true)]
    [InlineData(@"C:\Users\jo\Downloads\Sill.exe", 1, null, false)]          // options: a developer's launch
    [InlineData(@"C:\Users\jo\SillViewer\Sill.Viewer.exe", 0, null, false)]  // the spike's viewer, as before
    [InlineData(@"C:\Users\jo\Downloads\Sill.exe", 0, "1", false)]
    [InlineData(null, 0, null, false)]
    public void Applies(string? path, int args, string? env, bool want) =>
        Assert.Equal(want, S.Applies(path, Enumerable.Repeat("--host", args).ToList(), env));

    [Fact]
    public void Decisions()
    {
        const string here = @"C:\Users\jo\Downloads\Sill-0.6-windows-x64\Sill.exe";
        Assert.Equal(D.RunHere, S.Decide(Installed, V("0.6"), Installed, true, V("0.6")));
        Assert.Equal(D.RunHere, S.Decide(Installed.ToUpperInvariant(), V("0.6"), Installed, true, V("0.5")));
        Assert.Equal(D.OfferInstall, S.Decide(here, V("0.6"), Installed, false, null));
        Assert.Equal(D.OfferReplace, S.Decide(here, V("0.6"), Installed, true, V("0.5.1")));
        Assert.Equal(D.OfferReplace, S.Decide(here, V("0.6"), Installed, true, null)); // no version resource
        Assert.Equal(D.OfferOpenInstalled, S.Decide(here, V("0.6"), Installed, true, V("0.6.0")));
        Assert.Equal(D.OfferOpenInstalled, S.Decide(here, V("0.6"), Installed, true, V("0.7")));
        Assert.Equal(D.OfferOpenInstalled, S.Decide(here, null, Installed, true, V("0.5")));
        Assert.Equal(D.RunHere, S.Decide(here, V("0.6"), Installed, false, null, [here.ToLowerInvariant()]));
        Assert.Equal(D.OfferInstall, S.Decide(here, V("0.6"), Installed, false, null, [@"C:\elsewhere\Sill.exe"]));
    }

    [Fact]
    public void Words()
    {
        Assert.Null(S.Words(D.RunHere, V("0.6"), null));
        Assert.Equal("Install", S.Words(D.OfferInstall, V("0.6"), null)!.Value.Accept);
        var replace = S.Words(D.OfferReplace, V("0.6"), V("0.5.1"))!.Value;
        Assert.Equal("Replace the installed Sill 0.5.1?", replace.Heading);
        Assert.Contains("This is Sill 0.6.", replace.Text);
        Assert.Equal("Replace the installed Sill?", S.Words(D.OfferReplace, V("0.6"), null)!.Value.Heading);
        Assert.Equal("Sill 0.7 is already installed", S.Words(D.OfferOpenInstalled, V("0.6"), V("0.7"))!.Value.Heading);
    }
}
