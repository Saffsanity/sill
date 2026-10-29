using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 10d: the checker against a fake feed on loopback (a raw TCP listener, so every header
/// it sends is seen): the headers, what it keeps in update.json, If-None-Match and 304, the 1 MB cap,
/// a redirect elsewhere refused, the timeout, the switch, and the test hooks.</summary>
public sealed class UpdateCheckerTests : IDisposable
{
    private readonly string dir = Path.Combine(Path.GetTempPath(), "sill-update-" + Guid.NewGuid().ToString("N"));
    private string StatePath => Path.Combine(dir, "update.json");

    public UpdateCheckerTests() => Directory.CreateDirectory(dir);
    public void Dispose() { try { Directory.Delete(dir, true); } catch (IOException) { } }

    /// <summary>One answer per request, in order; the requests' heads are kept.</summary>
    private sealed class Feed : IDisposable
    {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);
        public readonly List<string> Requests = [];
        public readonly Queue<Func<string>> Answers = new();
        public int Port => ((IPEndPoint)listener.LocalEndpoint).Port;
        public Uri Url => new($"http://127.0.0.1:{Port}/latest");

        public Feed()
        {
            listener.Start();
            _ = Task.Run(async () =>
            {
                while (true)
                {
                    TcpClient client;
                    try { client = await listener.AcceptTcpClientAsync(); } catch { return; }
                    using (client)
                    {
                        var stream = client.GetStream();
                        var head = new StringBuilder();
                        var buf = new byte[1];
                        while (!head.ToString().EndsWith("\r\n\r\n") && await stream.ReadAsync(buf) == 1) head.Append((char)buf[0]);
                        lock (Requests) Requests.Add(head.ToString());
                        Func<string> answer;
                        lock (Answers) answer = Answers.Count > 0 ? Answers.Dequeue() : () => Response(500, "{}");
                        var text = answer();
                        if (text == "hang") { await Task.Delay(5000); continue; }
                        try { await stream.WriteAsync(Encoding.UTF8.GetBytes(text)); } catch (IOException) { }
                    }
                }
            });
        }

        public void Dispose() => listener.Stop();
    }

    private static string Response(int status, string body, string? extra = null) =>
        $"HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {Encoding.UTF8.GetByteCount(body)}\r\nConnection: close\r\n{extra}\r\n{body}";

    private static string Release(string tag, string page = "http://127.0.0.1/release") =>
        $$"""{"tag_name":"{{tag}}","html_url":"{{page}}","draft":false,"prerelease":false}""";

    private UpdateChecker Checker(Feed feed, string running = "0.5.1", TimeSpan? timeout = null, List<string>? log = null) =>
        new(new UpdateChecker.Configuration
        {
            Feed = feed.Url, TestFeed = true, Running = running, StatePath = StatePath, Jitter = TimeSpan.Zero,
            Timeout = timeout ?? TimeSpan.FromSeconds(5),
        }, line => { if (log is not null) lock (log) log.Add(line); });

    [Fact]
    public async Task OffersANewerReleaseWithTheHeadersAndKeepsIt()
    {
        using var feed = new Feed();
        feed.Answers.Enqueue(() => Response(200, Release("v0.6.0"), "ETag: W/\"abc\"\r\nSet-Cookie: x=1\r\n"));
        feed.Answers.Enqueue(() => Response(304, ""));
        var log = new List<string>();
        using (var c = Checker(feed, log: log))
        {
            var o = await c.CheckNowAsync();
            Assert.Equal("0.6", Assert.IsType<UpdatePolicy.Outcome.Newer>(o).Offer.Version.ToString());
            Assert.Equal("Sill 0.6 Is Available…", UpdatePolicy.MenuTitle(c.Offer!));
            Assert.Equal(c.Offer, c.UnshownOffer);
            c.NoteShown(c.Offer!);
            Assert.Null(c.UnshownOffer);
            Assert.Equal("Sill 0.6 is available.", c.Pane.Line);
        }
        var head = feed.Requests[0];
        Assert.StartsWith("GET /latest HTTP/1.1", head);
        Assert.Contains("User-Agent: Sill-Windows/0.5.1\r\n", head);
        Assert.Contains("Accept: application/vnd.github+json\r\n", head);
        Assert.Contains("X-GitHub-Api-Version: 2022-11-28\r\n", head);
        Assert.Contains("Accept-Language: en\r\n", head);
        Assert.DoesNotContain("If-None-Match", head);
        Assert.DoesNotContain("Cookie", head);
        Assert.DoesNotContain("Authorization", head);
        Assert.Contains(log, l => l.StartsWith("Update check: Sill 0.6 is available (this is 0.5.1)"));

        // The next run: what was kept, If-None-Match, a 304 that is still newer, no cookie sent back.
        using var again = Checker(feed);
        Assert.NotNull(again.Offer);
        Assert.Null(again.UnshownOffer);
        Assert.IsType<UpdatePolicy.Outcome.Newer>(await again.CheckNowAsync());
        Assert.Contains("If-None-Match: W/\"abc\"\r\n", feed.Requests[1]);
        Assert.DoesNotContain("Cookie", feed.Requests[1]);
    }

    [Fact]
    public async Task StaysQuietForTheSameVersion()
    {
        using var feed = new Feed();
        feed.Answers.Enqueue(() => Response(200, Release("v0.5.1")));
        using var c = Checker(feed);
        Assert.Equal(new UpdatePolicy.Outcome.UpToDate("v0.5.1"), await c.CheckNowAsync());
        Assert.Null(c.Offer);
        Assert.Equal("Sill is up to date.", c.Pane.Line);
    }

    [Fact]
    public async Task CapsRedirectsAndTimeouts()
    {
        using var feed = new Feed();
        feed.Answers.Enqueue(() => Response(200, "\"" + new string('a', (1 << 20) + 10) + "\""));
        feed.Answers.Enqueue(() => Response(302, "", "Location: https://evil.example/latest\r\n"));
        feed.Answers.Enqueue(() => "hang");
        using var c = Checker(feed, timeout: TimeSpan.FromSeconds(1));
        Assert.Equal(new UpdatePolicy.Outcome.NotARelease("more than 1 MB"), await c.CheckNowAsync());
        Assert.Equal(new UpdatePolicy.Outcome.NotARelease("a redirect to evil.example"), await c.CheckNowAsync());
        Assert.Equal(new UpdatePolicy.Outcome.Timeout(), await c.CheckNowAsync());
        // Every request was the feed's: the redirect to evil.example was never followed.
        lock (feed.Requests) Assert.All(feed.Requests, r => Assert.StartsWith("GET /latest", r));
        Assert.Equal(3, feed.Requests.Count);
    }

    [Fact]
    public async Task NoConnection()
    {
        int port;
        using (var l = new TcpListener(IPAddress.Loopback, 0)) { l.Start(); port = ((IPEndPoint)l.LocalEndpoint).Port; l.Stop(); }
        using var c = new UpdateChecker(new UpdateChecker.Configuration
        {
            Feed = new Uri($"http://127.0.0.1:{port}/latest"), TestFeed = true, Running = "0.5.1", StatePath = StatePath,
        });
        var o = await c.CheckNowAsync();
        Assert.IsType<UpdatePolicy.Outcome.NoConnection>(o);
        Assert.False(o!.Answered);
        Assert.False(File.Exists(StatePath)); // nothing kept
    }

    [Fact]
    public void TheSwitchIsKept()
    {
        using var feed = new Feed();
        using (var c = Checker(feed))
        {
            Assert.True(c.Automatic);
            c.SetAutomatic(false);
        }
        using var again = Checker(feed);
        Assert.False(again.Automatic);
        Assert.Contains("\"automatic\": false", File.ReadAllText(StatePath));
    }

    [Fact]
    public async Task AnAutomaticCheckRunsAfterTheLaunchDelay()
    {
        using var feed = new Feed();
        feed.Answers.Enqueue(() => Response(200, Release("v0.6")));
        var changed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var c = new UpdateChecker(new UpdateChecker.Configuration
        {
            Feed = feed.Url, TestFeed = true, Running = "0.5.1", StatePath = StatePath, LaunchDelay = TimeSpan.FromMilliseconds(200), Jitter = TimeSpan.Zero,
        });
        c.Changed += () => { if (!c.Checking && c.Offer is not null) changed.TrySetResult(); };
        c.Start();
        await changed.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Null(c.Result); // an automatic check is not Check Now's result
        Assert.Single(feed.Requests);
    }

    [Fact]
    public void TestHooksOnlyOnLoopback()
    {
        var log = new List<string>();
        var env = new Dictionary<string, string>
        {
            ["SILL_TEST_UPDATE_FEED"] = "http://127.0.0.1:9/latest", ["SILL_TEST_UPDATE_VERSION"] = "0.4", ["SILL_TEST_UPDATE_NOW"] = "1",
            ["SILL_TEST_UPDATE_INTERVAL"] = "48",
        };
        var c = UpdateChecker.Configuration.FromEnvironment("x", log.Add, k => env.GetValueOrDefault(k));
        Assert.True(c.TestFeed);
        Assert.Equal("0.4", c.Running);
        Assert.True(c.CheckAtStart);
        Assert.Equal((48, 2), ((int)c.Period.TotalSeconds, (int)c.Retry.TotalSeconds));
        env["SILL_TEST_UPDATE_FEED"] = "https://api.github.com.evil.example/latest";
        c = UpdateChecker.Configuration.FromEnvironment("x", log.Add, k => env.GetValueOrDefault(k));
        Assert.False(c.TestFeed);
        Assert.Equal(UpdatePolicy.Feed, c.Feed);
        Assert.Contains(log, l => l.StartsWith("SILL_TEST_UPDATE_FEED ignored"));
        c = UpdateChecker.Configuration.FromEnvironment("x", null, _ => null);
        Assert.Equal(UpdatePolicy.Feed, c.Feed);
        Assert.False(c.CheckAtStart);
    }
}
