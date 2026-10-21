using System.Text;
using System.Text.Json;
using P = Sill.Protocol.UpdatePolicy;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 10d: UpdatePolicy.swift's rules as Tests/checks/update-policy checks them, row by row
/// where they carry over (every row of the plan's §6.4, the offer, the schedule, feeds, pages, words).</summary>
public class UpdatePolicyTests
{
    private static readonly SillVersion V03 = SillVersion.Parse("0.3.0")!, V04 = SillVersion.Parse("0.4")!;
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_790_265_600);
    private const string Page = "https://github.com/Saffsanity/sill/releases/tag/v0.4.0";
    private static readonly P.Stored Empty = new();
    private static readonly P.Stored StoredRelease = new(Now.AddDays(-1), "W/\"e0\"", "v0.4.0", Page);
    private static readonly P.Offer Offer04 = new(V04, "v0.4.0", new Uri(Page));

    private static byte[] Body(object? tag = null, object? html = null, object? draft = null, object? prerelease = null, bool noTag = false, bool noHtml = false)
    {
        var d = new Dictionary<string, object?> { ["name"] = "x", ["assets"] = Array.Empty<int>() };
        if (!noTag) d["tag_name"] = tag ?? "v0.4.0";
        if (!noHtml) d["html_url"] = html ?? Page;
        d["draft"] = draft ?? false;
        d["prerelease"] = prerelease ?? false;
        return JsonSerializer.SerializeToUtf8Bytes(d);
    }

    private static P.Answer Ok(byte[] b, string? etag = "W/\"e1\"") => new P.Answer.Http(200, b, etag, null);
    private static P.Answer Status(int s, DateTimeOffset? reset = null) => new P.Answer.Http(s, "{}"u8.ToArray(), null, reset);
    private static (P.Outcome O, P.Stored S) Interpret(P.Answer a, P.Stored? s = null, SillVersion? running = null, bool test = false) =>
        P.Interpret(a, s ?? Empty, running ?? V03, Now, test);

    [Fact]
    public void Versions()
    {
        Assert.Equal("0.4", SillVersion.Parse("v0.4.0")!.ToString());
        Assert.Equal(SillVersion.Parse("0.4"), SillVersion.Parse("V0.4.0"));
        Assert.True(SillVersion.Parse("0.10")! > SillVersion.Parse("0.9.5")!);
        Assert.Equal(SillVersion.Parse("0.3.0"), SillVersion.Parse("0.3.0 (85)"));
        Assert.Equal(SillVersion.Parse("0.5.1"), SillVersion.Parse("0.5.1+4d990e9abc"));
        Assert.Null(SillVersion.Parse("nightly"));
        Assert.Null(SillVersion.Parse(""));
        Assert.Null(SillVersion.Parse("1.2.3.4.5.6.7.8.9"));
        Assert.Null(SillVersion.Parse("1234567890"));
        Assert.Equal("0.0", new SillVersion([]).ToString());
        // Directory.Build.props' Version, without the "+commit" the SDK appends.
        var built = AppVersion.Read(typeof(SillVersion).Assembly);
        Assert.NotNull(SillVersion.Parse(built));
        Assert.DoesNotContain("+", built);
    }

    [Fact]
    public void TwoHundreds()
    {
        var (o, s) = Interpret(Ok(Body()));
        Assert.Equal(new P.Outcome.Newer(Offer04), o);
        Assert.Equal(new P.Stored(Now, "W/\"e1\"", "v0.4.0", Page), s);
        (o, s) = Interpret(Ok(Body("v0.3.0", "https://github.com/Saffsanity/sill/releases/tag/v0.3.0")));
        Assert.Equal(new P.Outcome.UpToDate("v0.3.0"), o);
        Assert.Equal(Now, s.LastCheck);
        Assert.Equal(new P.Outcome.UpToDate("0.2.9"), Interpret(Ok(Body("0.2.9"))).O);
        Assert.Equal(new P.Outcome.UpToDate("v0.3.0"), Interpret(Ok(Body("v0.3.0")), running: SillVersion.Parse("0.3.0 (85)")).O);
        Assert.IsType<P.Outcome.Newer>(Interpret(Ok(Body("v0.10.0")), running: SillVersion.Parse("0.9.5")).O);
        Assert.Equal(new P.Outcome.Newer(new P.Offer(V04, "0.4", new Uri(Page))), Interpret(Ok(Body("0.4"))).O);
        // A 200 without an ETag clears it.
        (o, s) = Interpret(Ok(Body(), etag: null), StoredRelease);
        Assert.Null(s.ETag);
        Assert.Equal("v0.4.0", s.LatestTag);
        // Draft and prerelease missing count as false.
        Assert.Equal(new P.Outcome.Newer(Offer04), Interpret(Ok("""{"tag_name":"v0.4.0","html_url":"https://github.com/Saffsanity/sill/releases/tag/v0.4.0","draft":null}"""u8.ToArray())).O);
    }

    [Fact]
    public void OtherStatuses()
    {
        var (o, s) = Interpret(Status(304), StoredRelease);
        Assert.Equal(new P.Outcome.Newer(Offer04), o);
        Assert.Equal(StoredRelease with { LastCheck = Now }, s);
        Assert.Equal(new P.Outcome.UpToDate("v0.4.0"), Interpret(Status(304), StoredRelease, V04).O);
        (o, s) = Interpret(Status(304));
        Assert.Equal(new P.Outcome.NotARelease("a 304 before any release"), o);
        Assert.Equal(Now, s.LastCheck);
        (o, s) = Interpret(Status(404), StoredRelease);
        Assert.Equal(new P.Outcome.NoRelease(), o);
        Assert.Equal(new P.Stored(Now), s);
        var reset = Now.AddMinutes(42);
        (o, s) = Interpret(Status(403, reset), StoredRelease);
        Assert.Equal(new P.Outcome.Limited(403, reset), o);
        Assert.Equal(StoredRelease with { LastCheck = Now }, s);
        Assert.Equal(new P.Outcome.Limited(429, null), Interpret(Status(429)).O);
        Assert.Equal(new P.Outcome.HttpError(502), Interpret(Status(502)).O);
        Assert.Equal(new P.Outcome.HttpError(301), Interpret(Status(301)).O);
        Assert.Equal("v0.4.0", Interpret(Status(500), StoredRelease).S.LatestTag);
    }

    public static TheoryData<byte[], string> NotReleases => new()
    {
        { Body(noTag: true), "no tag_name" },
        { Body(tag: 4), "no tag_name" },
        { Body("nightly"), "the tag “nightly” is not a version" },
        { Body(draft: true), "a draft" },
        { Body(prerelease: true), "a prerelease" },
        { Body(html: "https://evil.example/sill"), "html_url is not on github.com" },
        { Body(html: "http://github.com/x"), "html_url is not on github.com" },
        { Body(noHtml: true), "html_url is not on github.com" },
        { Body(html: "https://github.com.evil.example/x"), "html_url is not on github.com" },
        { "[1,2]"u8.ToArray(), "not a JSON object" },
        { "<html>"u8.ToArray(), "not a JSON object" },
        { Array.Empty<byte>(), "not a JSON object" },
    };

    [Theory, MemberData(nameof(NotReleases))]
    public void NotAPublishedRelease(byte[] body, string why)
    {
        var (o, s) = Interpret(Ok(body), StoredRelease);
        Assert.Equal(new P.Outcome.NotARelease(why), o);
        Assert.Equal(StoredRelease with { LastCheck = Now }, s);
    }

    [Fact]
    public void TestFeedsRedirectsAndFailures()
    {
        Assert.Equal(new P.Outcome.Newer(new P.Offer(V04, "v0.4.0", new Uri("http://127.0.0.1:8080/release"))),
            Interpret(Ok(Body(html: "http://127.0.0.1:8080/release")), test: true).O);
        Assert.Equal(new P.Outcome.NotARelease("html_url is not on github.com"), Interpret(Ok(Body(html: "file:///etc/passwd")), test: true).O);
        var (o, s) = Interpret(new P.Answer.Redirected("evil.example"), StoredRelease);
        Assert.Equal(new P.Outcome.NotARelease("a redirect to evil.example"), o);
        Assert.Equal(Now, s.LastCheck);
        Assert.Equal("v0.4.0", s.LatestTag);
        Assert.Equal(new P.Outcome.NotARelease("more than 1 MB"), Interpret(new P.Answer.TooLarge()).O);
        foreach (var (kind, want) in new (P.FailureKind, P.Outcome)[]
                 {
                     (P.FailureKind.NoConnection, new P.Outcome.NoConnection(false, "d")),
                     (P.FailureKind.Tls, new P.Outcome.NoConnection(true, "d")),
                     (P.FailureKind.Timeout, new P.Outcome.Timeout()),
                     (P.FailureKind.Other, new P.Outcome.Failed("d")),
                 })
        {
            (o, s) = Interpret(new P.Answer.Failed(kind, "d"), StoredRelease);
            Assert.Equal(want, o);
            Assert.Equal(StoredRelease, s);
            Assert.False(o.Answered);
        }
        Assert.True(new P.Outcome.NoRelease().Answered && new P.Outcome.Limited(403, null).Answered && new P.Outcome.HttpError(500).Answered
                    && new P.Outcome.NotARelease("x").Answered && new P.Outcome.UpToDate("v").Answered);
    }

    [Fact]
    public void TheOffer()
    {
        Assert.Equal(Offer04, P.OfferFor(StoredRelease, V03));
        Assert.Null(P.OfferFor(StoredRelease, V04));
        Assert.Null(P.OfferFor(StoredRelease, SillVersion.Parse("0.5")));
        Assert.Equal(Offer04, P.OfferFor(StoredRelease, SillVersion.Parse("0.2")));
        Assert.Null(P.OfferFor(StoredRelease, null));
        Assert.Null(P.OfferFor(StoredRelease with { LatestUrl = "https://evil.example/sill" }, V03));
        Assert.Null(P.OfferFor(new P.Stored(LatestTag: "nightly", LatestUrl: Page), V03));
    }

    [Fact]
    public void When()
    {
        Assert.True(P.IsDue(null, Now, P.Period));
        Assert.True(P.IsDue(Now.AddSeconds(-86_400), Now, P.Period));
        Assert.False(P.IsDue(Now.AddSeconds(-86_399), Now, P.Period));
        Assert.True(P.IsDue(Now.AddHours(1), Now, P.Period));
        var last = Now.AddHours(-1);
        var d = TimeSpan.FromSeconds(30);
        Assert.Equal(last.AddSeconds(86_400 + 600), P.NextCheck(last, null, Now, P.Period, TimeSpan.FromSeconds(600), d));
        Assert.Equal(Now + d, P.NextCheck(null, null, Now, P.Period, TimeSpan.FromSeconds(600), d));
        Assert.Equal(Now + d, P.NextCheck(Now.AddSeconds(-90_000), null, Now, P.Period, TimeSpan.FromSeconds(600), d));
        Assert.Equal(Now.AddHours(1), P.NextCheck(last, Now.AddHours(1), Now, P.Period, TimeSpan.Zero, d));
        Assert.Equal(Now + d, P.NextCheck(last, Now.AddSeconds(-10), Now, P.Period, TimeSpan.Zero, d));
        Assert.Equal((86_400, 1800, 3600, 30, 10, 1 << 20),
            ((int)P.Period.TotalSeconds, (int)P.Jitter.TotalSeconds, (int)P.Retry.TotalSeconds, (int)P.LaunchDelay.TotalSeconds, (int)P.RequestTimeout.TotalSeconds, P.MaxBody));
    }

    [Theory]
    [InlineData("http://127.0.0.1:8080/latest", true)]
    [InlineData("https://127.0.0.1/x", true)]
    [InlineData("http://[::1]:9/latest", true)]
    [InlineData("http://localhost:1/", true)]
    [InlineData("http://LOCALHOST:1/", true)]
    [InlineData("http://127.0.0.2/", false)]
    [InlineData("https://api.github.com/repos/Saffsanity/sill/releases/latest", false)]
    [InlineData("ftp://127.0.0.1/x", false)]
    [InlineData("http://localhost.evil.example/", false)]
    [InlineData("http://127.0.0.1.nip.io/", false)]
    [InlineData("file:///tmp/feed.json", false)]
    [InlineData("http://192.168.1.2/", false)]
    public void LocalFeeds(string url, bool want) => Assert.Equal(want, P.IsLocalFeed(new Uri(url)));

    [Fact]
    public void Redirects()
    {
        Assert.True(P.RedirectAllowed(new Uri("https://api.github.com/repositories/1/releases/latest")));
        Assert.False(P.RedirectAllowed(new Uri("http://api.github.com/x")));
        Assert.False(P.RedirectAllowed(new Uri("https://api.github.com.evil.example/x")));
        Assert.False(P.RedirectAllowed(new Uri("https://github.com/x")));
        Assert.False(P.RedirectAllowed(new Uri("http://127.0.0.1/x")));
        Assert.Equal("https://api.github.com/repos/Saffsanity/sill/releases/latest", P.Feed.AbsoluteUri);
    }

    [Fact]
    public void Words()
    {
        string T(DateTimeOffset _) => "15:42";
        Assert.Equal("Sill 0.4 Is Available…", P.MenuTitle(Offer04));
        Assert.Equal("You have 0.3; opens its download page", P.MenuSubtitle(V03));
        string? Log(P.Outcome o, bool manual = false) => P.LogLine(o, manual, "0.3.0", P.Retry, T);
        Assert.Equal($"Update check: Sill 0.4 is available (this is 0.3.0): {Page}", Log(new P.Outcome.Newer(Offer04)));
        Assert.Null(Log(new P.Outcome.UpToDate("v0.3.0")));
        Assert.Equal("Update check: up to date (this is 0.3.0; the latest release is v0.3.0).", Log(new P.Outcome.UpToDate("v0.3.0"), true));
        Assert.Equal("Update check failed: GitHub has no release of Sill (HTTP 404).", Log(new P.Outcome.NoRelease()));
        Assert.Equal("Update check failed: GitHub is limiting requests from this network (HTTP 403; it resets at 15:42).", Log(new P.Outcome.Limited(403, Now)));
        Assert.Equal("Update check failed: GitHub is limiting requests from this network (HTTP 429).", Log(new P.Outcome.Limited(429, null)));
        Assert.Equal("Update check failed: HTTP 502.", Log(new P.Outcome.HttpError(502)));
        Assert.Equal("Update check failed: the answer is not a published release (a draft).", Log(new P.Outcome.NotARelease("a draft")));
        Assert.Equal("Update check failed: no connection (No such host is known.); trying again in 1 hour.", Log(new P.Outcome.NoConnection(false, "No such host is known.")));
        Assert.Equal("Update check failed: no answer in 10 s.", Log(new P.Outcome.Timeout(), true));
        Assert.Equal(("1 hour", "2 hours", "30 minutes", "4 s"),
            (P.Duration(TimeSpan.FromHours(1)), P.Duration(TimeSpan.FromHours(2)), P.Duration(TimeSpan.FromMinutes(30)), P.Duration(TimeSpan.FromSeconds(4))));
        Assert.Equal(("Sill 0.4 is available.", false), P.ResultLine(new P.Outcome.Newer(Offer04), T));
        Assert.Equal(("Sill is up to date.", false), P.ResultLine(new P.Outcome.UpToDate("v"), T));
        Assert.Equal(("Couldn’t check: this PC isn’t connected to the internet.", true), P.ResultLine(new P.Outcome.NoConnection(false, "x"), T));
        Assert.Equal(("Couldn’t check: The remote certificate is invalid.", true), P.ResultLine(new P.Outcome.NoConnection(true, "The remote certificate is invalid."), T));
        Assert.Equal(("Couldn’t check: GitHub is limiting requests from this network. Try again after 15:42.", true), P.ResultLine(new P.Outcome.Limited(403, Now), T));
        Assert.Equal(("Couldn’t check: GitHub didn’t answer within 10 seconds.", true), P.ResultLine(new P.Outcome.Timeout(), T));
        P.Pane Pane(bool checking = false, P.Outcome? result = null, P.Offer? offer = null, DateTimeOffset? last = null, bool hasVersion = true) =>
            P.PaneFor(checking, result, 3, offer, last, hasVersion, T, _ => "Sep 24, 2026 13:00");
        Assert.Equal(new P.Pane("Not checked yet.", false, null, true, 3), Pane());
        Assert.Equal("Last checked Sep 24, 2026 13:00.", Pane(last: Now).Line);
        Assert.Equal(new P.Pane("Checking…", false, null, false, 3), Pane(checking: true, result: new P.Outcome.NoRelease()));
        Assert.True(Pane(result: new P.Outcome.NoRelease(), offer: Offer04).Failed);
        Assert.Equal(new P.Pane("Sill 0.4 is available.", false, new Uri(Page), true, 3), Pane(offer: Offer04, last: Now));
        Assert.Equal(new P.Pane(P.NoVersionLine, false, null, false, 3), Pane(hasVersion: false));
        Assert.Contains("GitHub sees this PC’s IP address and which version of Sill it has; nothing else is sent.", P.Footnote);
    }
}
