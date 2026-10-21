using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sill.Protocol;

/// <summary>
/// The update check, ported from Sill.app's UpdateChecker.swift: asks GitHub's releases feed whether a
/// newer Sill is out, keeps what it learned in <c>update.json</c> (beside the app's other data in
/// <c>%LOCALAPPDATA%\Sill</c>), and says so through <see cref="Offer"/> and <see cref="Pane"/>, with
/// <see cref="Changed"/> raised whenever either may have changed. <see cref="UpdatePolicy"/> decides
/// what every answer means; this class does the asking and the timing. Portable (HttpClient), so the
/// tests run it against a feed on loopback on any OS.
///
/// When: automatic checks (<see cref="Automatic"/>, on by default, kept in update.json) run
/// <c>LaunchDelay</c> after <see cref="Start"/> when one is due, then a period plus a random jitter
/// after each answer, or <c>Retry</c> after a check that got no answer at all. Check Now runs at once,
/// whatever the switch and the period; during an automatic check it joins it.
///
/// What goes out: GET the feed with <c>User-Agent: Sill-Windows/‹version›</c>, GitHub's Accept and API
/// version headers, <c>Accept-Language: en</c>, and If-None-Match with a stored ETag and release; no
/// cookies, no cache, no credentials; redirects only to https://api.github.com/; at most 1 MB read,
/// 10 s for the whole request. Never a token, an identifier or anything about the PC or its Macs.
/// Nothing is downloaded or installed: the app opens the offer's page in the browser.
/// </summary>
public sealed class UpdateChecker : IDisposable
{
    /// <summary>Where and when it checks: GitHub and the plan's schedule, or a test's.</summary>
    public sealed record Configuration
    {
        public Uri Feed { get; init; } = UpdatePolicy.Feed;
        /// <summary>A feed on this PC (SILL_TEST_UPDATE_FEED): any http or https release page counts.</summary>
        public bool TestFeed { get; init; }
        /// <summary>This Sill's version as written; one that does not parse never checks.</summary>
        public string? Running { get; init; } = AppVersion.Current;
        /// <summary>SILL_TEST_UPDATE_NOW=1: one check right after <see cref="Start"/>, as Check Now.</summary>
        public bool CheckAtStart { get; init; }
        public TimeSpan Period { get; init; } = UpdatePolicy.Period;
        public TimeSpan Retry { get; init; } = UpdatePolicy.Retry;
        public TimeSpan LaunchDelay { get; init; } = UpdatePolicy.LaunchDelay;
        public TimeSpan Jitter { get; init; } = UpdatePolicy.Jitter;
        public TimeSpan Timeout { get; init; } = UpdatePolicy.RequestTimeout;
        /// <summary>update.json.</summary>
        public required string StatePath { get; init; }

        /// <summary>GitHub's feed, or the test hooks a run sets (TEST ONLY): SILL_TEST_UPDATE_FEED (a feed
        /// on loopback alone; anything else is ignored with a line), SILL_TEST_UPDATE_VERSION (the version
        /// this build says it is), SILL_TEST_UPDATE_NOW=1 (check at start), SILL_TEST_UPDATE_INTERVAL=s
        /// (24 h become s seconds, the retry s/24, the launch delay 1 s).</summary>
        public static Configuration FromEnvironment(string statePath, Action<string>? log = null, Func<string, string?>? env = null)
        {
            env ??= Environment.GetEnvironmentVariable;
            var c = new Configuration { StatePath = statePath };
            if (env("SILL_TEST_UPDATE_FEED") is { Length: > 0 } feed)
            {
                if (Uri.TryCreate(feed, UriKind.Absolute, out var url) && UpdatePolicy.IsLocalFeed(url))
                {
                    c = c with { Feed = url, TestFeed = true };
                    log?.Invoke($"TEST: the update check asks {url.AbsoluteUri} instead of GitHub.");
                }
                else log?.Invoke($"SILL_TEST_UPDATE_FEED ignored: {feed} is not on this PC (127.0.0.1, ::1 or localhost).");
            }
            if (env("SILL_TEST_UPDATE_VERSION") is { Length: > 0 } version) c = c with { Running = version };
            if (env("SILL_TEST_UPDATE_NOW") == "1") c = c with { CheckAtStart = true };
            if (double.TryParse(env("SILL_TEST_UPDATE_INTERVAL"), NumberStyles.Float, CultureInfo.InvariantCulture, out double s) && s > 0)
                c = c with
                {
                    Period = TimeSpan.FromSeconds(s), Retry = TimeSpan.FromSeconds(Math.Max(1, s / 24)),
                    LaunchDelay = TimeSpan.FromSeconds(1), Jitter = TimeSpan.Zero,
                };
            return c;
        }
    }

    /// <summary>update.json: what the checker keeps between runs.</summary>
    public sealed record State(
        [property: JsonPropertyName("automatic")] bool Automatic = true,
        [property: JsonPropertyName("lastCheck")] long? LastCheck = null,
        [property: JsonPropertyName("etag")] string? ETag = null,
        [property: JsonPropertyName("latestTag")] string? LatestTag = null,
        [property: JsonPropertyName("latestUrl")] string? LatestUrl = null,
        [property: JsonPropertyName("shownTag")] string? ShownTag = null)
    {
        private static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull, WriteIndented = true };

        [JsonIgnore]
        public UpdatePolicy.Stored Stored => new(LastCheck is { } t ? DateTimeOffset.FromUnixTimeSeconds(t) : null, ETag, LatestTag, LatestUrl);

        public State With(UpdatePolicy.Stored s) =>
            this with { LastCheck = s.LastCheck?.ToUnixTimeSeconds(), ETag = s.ETag, LatestTag = s.LatestTag, LatestUrl = s.LatestUrl };

        public static State Load(string path)
        {
            try { return JsonSerializer.Deserialize<State>(File.ReadAllText(path), Json) ?? new State(); }
            catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new State(); }
        }

        public void Save(string path)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
                File.WriteAllText(path, JsonSerializer.Serialize(this, Json));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
    }

    private readonly object gate = new();
    private readonly HttpClient http;
    private readonly SillVersion? running;
    private readonly Action<string> log;
    private State state;
    private SynchronizationContext? context;
    private Timer? timer;
    private bool started, inFlight, manualPending, disposed;
    private DateTimeOffset? retryAt;
    private TimeSpan jitter;

    public Configuration Config { get; }
    /// <summary>A check is in flight.</summary>
    public bool Checking { get { lock (gate) return inFlight; } }
    /// <summary>This run's last Check Now result, until an automatic check that GitHub answers replaces it.</summary>
    public UpdatePolicy.Outcome? Result { get; private set; }
    public int ResultCount { get; private set; }
    public bool Automatic { get { lock (gate) return state.Automatic; } }
    public UpdatePolicy.Stored Stored { get { lock (gate) return state.Stored; } }
    public SillVersion? Running => running;
    /// <summary>Whether this build can check at all: it has a version.</summary>
    public bool CanCheck => running is not null;

    /// <summary>The stored release, when it is newer than what runs.</summary>
    public UpdatePolicy.Offer? Offer => UpdatePolicy.OfferFor(Stored, running, Config.TestFeed);

    /// <summary>The offer, if the app has not yet told the person about it (<see cref="NoteShown"/>).</summary>
    public UpdatePolicy.Offer? UnshownOffer
    {
        get { var o = Offer; lock (gate) return o is not null && o.Tag != state.ShownTag ? o : null; }
    }

    /// <summary>Settings' line and buttons.</summary>
    public UpdatePolicy.Pane Pane => UpdatePolicy.PaneFor(Checking, Result, ResultCount, Offer, Stored.LastCheck, running is not null, Time, Date);

    /// <summary>Raised (on the context given to <see cref="Start"/>, if any) after a check ends or a setting changes.</summary>
    public event Action? Changed;

    public static string Time(DateTimeOffset d) => d.ToLocalTime().ToString("t", CultureInfo.CurrentCulture);
    public static string Date(DateTimeOffset d) => d.ToLocalTime().ToString("g", CultureInfo.CurrentCulture);

    public UpdateChecker(Configuration configuration, Action<string>? log = null, HttpMessageHandler? handler = null)
    {
        Config = configuration;
        this.log = log ?? (_ => { });
        running = SillVersion.Parse(configuration.Running);
        state = State.Load(configuration.StatePath);
        jitter = Draw();
        http = new HttpClient(handler ?? new SocketsHttpHandler
        {
            UseCookies = false,
            AllowAutoRedirect = false, // followed by hand, only to api.github.com
            Credentials = null,
            PreAuthenticate = false,
            AutomaticDecompression = DecompressionMethods.All,
        }, disposeHandler: true) { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
        var h = http.DefaultRequestHeaders;
        h.TryAddWithoutValidation("User-Agent", $"Sill-Windows/{configuration.Running ?? "unknown"}");
        h.TryAddWithoutValidation("Accept", "application/vnd.github+json");
        h.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        h.TryAddWithoutValidation("Accept-Language", "en");
        h.CacheControl = new CacheControlHeaderValue { NoCache = true };
    }

    private TimeSpan Draw() => Config.Jitter > TimeSpan.Zero ? TimeSpan.FromSeconds(Random.Shared.NextDouble() * Config.Jitter.TotalSeconds) : TimeSpan.Zero;

    /// <summary>Once the app has started: says what an earlier check found, runs SILL_TEST_UPDATE_NOW's
    /// check, and schedules the automatic ones. <paramref name="context"/> is where <see cref="Changed"/>
    /// is raised (the UI's).</summary>
    public void Start(SynchronizationContext? context = null)
    {
        lock (gate)
        {
            if (started) return;
            started = true;
            this.context = context;
        }
        if (Offer is { } offer) log($"Update: Sill {offer.Version} is available (found by an earlier check).");
        if (Config.CheckAtStart)
        {
            if (running is null) log("SILL_TEST_UPDATE_NOW ignored: this build has no version number (SILL_TEST_UPDATE_VERSION gives it one).");
            else CheckNow();
        }
        Schedule();
    }

    /// <summary>The "Check for updates automatically" switch, kept in update.json. Off: nothing more is
    /// scheduled; a check in flight finishes, and what was found stays offered.</summary>
    public void SetAutomatic(bool on)
    {
        lock (gate)
        {
            if (state.Automatic == on) return;
            state = state with { Automatic = on };
            state.Save(Config.StatePath);
        }
        Schedule();
        Raise();
    }

    /// <summary>The PC woke (SystemEvents.PowerModeChanged's Resume): timers may not have counted the
    /// sleep, so the next check is worked out again (one that fell due runs LaunchDelay later).</summary>
    public void SystemDidWake() => Schedule();

    /// <summary>The app told the person about <paramref name="offer"/>: <see cref="UnshownOffer"/> leaves it out from now on.</summary>
    public void NoteShown(UpdatePolicy.Offer offer)
    {
        lock (gate)
        {
            if (state.ShownTag == offer.Tag) return;
            state = state with { ShownTag = offer.Tag };
            state.Save(Config.StatePath);
        }
    }

    /// <summary>Check Now: at once, whatever the switch and the period; during a check it joins it.</summary>
    public void CheckNow()
    {
        if (!CanCheck) return;
        bool run;
        lock (gate)
        {
            if (disposed) return;
            manualPending = true;
            run = !inFlight;
            if (run) inFlight = true;
        }
        if (run) Run();
    }

    /// <summary>A check now, as Check Now, awaited (for tests and a Settings button that waits).</summary>
    public Task<UpdatePolicy.Outcome?> CheckNowAsync()
    {
        var done = new TaskCompletionSource<UpdatePolicy.Outcome?>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Once() { if (!Checking) { Changed -= Once; done.TrySetResult(Result); } }
        Changed += Once;
        CheckNow();
        if (!CanCheck) { Changed -= Once; done.TrySetResult(null); }
        return done.Task;
    }

    private void Schedule()
    {
        lock (gate)
        {
            timer?.Dispose();
            timer = null;
            if (!started || disposed || !state.Automatic || !CanCheck || inFlight) return;
            var now = DateTimeOffset.UtcNow;
            var at = UpdatePolicy.NextCheck(state.Stored.LastCheck, retryAt, now, Config.Period, jitter, Config.LaunchDelay);
            var wait = at - now;
            if (wait < TimeSpan.Zero) wait = TimeSpan.Zero;
            if (wait > TimeSpan.FromDays(40)) wait = TimeSpan.FromDays(40); // Timer's limit; re-armed then
            timer = new Timer(_ => TimerFired(), null, wait, System.Threading.Timeout.InfiniteTimeSpan);
        }
    }

    private void TimerFired()
    {
        bool due;
        lock (gate)
        {
            timer?.Dispose();
            timer = null;
            if (!started || disposed || !state.Automatic || !CanCheck || inFlight) return;
            // The 40-day cap: run only once it is really due, else arm the timer again.
            var now = DateTimeOffset.UtcNow;
            due = UpdatePolicy.NextCheck(state.Stored.LastCheck, retryAt, now, Config.Period, jitter, TimeSpan.Zero) <= now + TimeSpan.FromSeconds(1);
            if (due) inFlight = true;
        }
        if (due) Run(); else Schedule();
    }

    private void Run()
    {
        Raise();
        UpdatePolicy.Stored stored;
        lock (gate) { timer?.Dispose(); timer = null; stored = state.Stored; }
        _ = Task.Run(async () =>
        {
            var answer = await FetchAsync(stored).ConfigureAwait(false);
            Finish(answer);
        });
    }

    private void Finish(UpdatePolicy.Answer answer)
    {
        bool manual;
        UpdatePolicy.Outcome outcome;
        lock (gate)
        {
            manual = manualPending;
            manualPending = false;
            inFlight = false;
            if (running is null || disposed) return;
            var now = DateTimeOffset.UtcNow;
            (outcome, var next) = UpdatePolicy.Interpret(answer, state.Stored, running, now, Config.TestFeed);
            if (next != state.Stored)
            {
                state = state.With(next);
                state.Save(Config.StatePath);
            }
            if (manual) { Result = outcome; ResultCount++; }
            else if (outcome.Answered) Result = null;
            if (outcome.Answered) { retryAt = null; jitter = Draw(); }
            else retryAt = now + Config.Retry;
        }
        if (UpdatePolicy.LogLine(outcome, manual, Config.Running ?? running!.ToString(), Config.Retry, Time) is { } line) log(line);
        Schedule();
        Raise();
    }

    private void Raise()
    {
        var handler = Changed;
        if (handler is null) return;
        if (context is { } c) c.Post(_ => handler(), null);
        else handler();
    }

    /// <summary>One GET, as UpdatePolicy reads it: the status, at most MaxBody of the body, the ETag and
    /// the rate limit's reset; redirects followed only to api.github.com (a test feed's own host too).</summary>
    private async Task<UpdatePolicy.Answer> FetchAsync(UpdatePolicy.Stored stored)
    {
        using var cts = new CancellationTokenSource(Config.Timeout);
        var url = Config.Feed;
        try
        {
            for (int hop = 0; ; hop++)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                if (stored.ETag is { } etag && stored.LatestTag is not null && stored.LatestUrl is not null)
                    request.Headers.TryAddWithoutValidation("If-None-Match", etag);
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
                int status = (int)response.StatusCode;
                if (status is 301 or 302 or 303 or 307 or 308 && response.Headers.Location is { } location)
                {
                    var next = location.IsAbsoluteUri ? location : new Uri(url, location);
                    if (hop >= 5 || !UpdatePolicy.RedirectAllowed(next)) return new UpdatePolicy.Answer.Redirected(next.IsAbsoluteUri ? next.Host : "an address without a host");
                    url = next;
                    continue;
                }
                if (response.Content.Headers.ContentLength > UpdatePolicy.MaxBody) return new UpdatePolicy.Answer.TooLarge();
                await using var stream = await response.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false);
                var body = new MemoryStream();
                var buffer = new byte[16 * 1024];
                int n;
                while ((n = await stream.ReadAsync(buffer, cts.Token).ConfigureAwait(false)) > 0)
                {
                    body.Write(buffer, 0, n);
                    if (body.Length > UpdatePolicy.MaxBody) return new UpdatePolicy.Answer.TooLarge();
                }
                string? etagOut = response.Headers.TryGetValues("ETag", out var e) ? e.FirstOrDefault() : null;
                DateTimeOffset? reset = response.Headers.TryGetValues("X-RateLimit-Reset", out var r)
                    && double.TryParse(r.FirstOrDefault(), NumberStyles.Float, CultureInfo.InvariantCulture, out double secs)
                    ? DateTimeOffset.FromUnixTimeMilliseconds((long)(secs * 1000)) : null;
                return new UpdatePolicy.Answer.Http(status, body.ToArray(), etagOut, reset);
            }
        }
        catch (OperationCanceledException) when (cts.IsCancellationRequested)
        {
            return new UpdatePolicy.Answer.Failed(UpdatePolicy.FailureKind.Timeout, "timed out");
        }
        catch (HttpRequestException e)
        {
            var kind = e.HttpRequestError switch
            {
                HttpRequestError.NameResolutionError or HttpRequestError.ConnectionError or HttpRequestError.ProxyTunnelError => UpdatePolicy.FailureKind.NoConnection,
                HttpRequestError.SecureConnectionError => UpdatePolicy.FailureKind.Tls,
                _ => UpdatePolicy.FailureKind.Other,
            };
            return new UpdatePolicy.Answer.Failed(kind, e.Message);
        }
        catch (Exception e) when (e is IOException or InvalidOperationException)
        {
            return new UpdatePolicy.Answer.Failed(UpdatePolicy.FailureKind.Other, e.Message);
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            disposed = true;
            timer?.Dispose();
            timer = null;
        }
        http.Dispose();
    }
}
