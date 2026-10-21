using System.Text.Json;

namespace Sill.Protocol;

/// <summary>
/// The update check as pure rules, ported from Sill.app's UpdatePolicy.swift (docs/update-notice-plan.md
/// §6): the feed, what one answer from it means and what is kept afterwards, when the next automatic
/// check is due, and every word the app and its log say about it. <see cref="UpdateChecker"/> does
/// the asking and the timing; this class decides.
///
/// A check, not an updater: a newer release is offered, and opening it shows its page on GitHub,
/// where the person downloads the zip. Nothing is downloaded or installed by Sill, and the only feed
/// is GitHub's (no server of Sill's, no token, no identifier). Sill for Mac and Sill for Windows share
/// one version and one release (docs/release-checklist.md), so the same feed serves both.
/// </summary>
public static class UpdatePolicy
{
    /// <summary>GitHub's latest published release of Sill (drafts and prereleases are never listed there).</summary>
    public static readonly Uri Feed = new("https://api.github.com/repos/Saffsanity/sill/releases/latest");

    /// <summary>Where a redirect may lead (a renamed repository answers 301 to its new address there).</summary>
    public static bool RedirectAllowed(Uri url) =>
        url.IsAbsoluteUri && url.Scheme == "https" && url.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase);

    public static readonly TimeSpan Period = TimeSpan.FromHours(24);
    /// <summary>A random 0–30 minutes on top of the period, so PCs behind one address drift apart.</summary>
    public static readonly TimeSpan Jitter = TimeSpan.FromMinutes(30);
    /// <summary>After a check that got no HTTP answer at all (offline, a timeout): again this much later.</summary>
    public static readonly TimeSpan Retry = TimeSpan.FromHours(1);
    /// <summary>The first automatic check, when due, this long after the app has started.</summary>
    public static readonly TimeSpan LaunchDelay = TimeSpan.FromSeconds(30);
    public static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(10);
    /// <summary>The most of a body read; more is not a release.</summary>
    public const int MaxBody = 1 << 20;

    // What is kept

    /// <summary>What update.json keeps: GitHub's last answer of any kind, and the last published release
    /// it named, which is offered whenever it is newer than what runs.</summary>
    public sealed record Stored(DateTimeOffset? LastCheck = null, string? ETag = null, string? LatestTag = null, string? LatestUrl = null);

    /// <summary>A newer release to offer.</summary>
    public sealed record Offer(SillVersion Version, string Tag, Uri Url);

    /// <summary>The stored release when it is newer than <paramref name="running"/> and its page is one
    /// Sill opens (on github.com over https; with a test feed, any http or https page). Read again at
    /// every use, so the offer goes by itself once the new version runs.</summary>
    public static Offer? OfferFor(Stored stored, SillVersion? running, bool anyReleaseUrl = false)
    {
        if (running is null || stored.LatestTag is not { } tag || SillVersion.Parse(tag) is not { } version || !(version > running)
            || stored.LatestUrl is not { } text || ReleasePage(text, anyReleaseUrl) is not { } url) return null;
        return new Offer(version, tag, url);
    }

    /// <summary>A release's html_url as a page Sill opens: https on github.com, or with a test feed any
    /// http or https URL with a host.</summary>
    public static Uri? ReleasePage(string text, bool anyReleaseUrl)
    {
        if (!Uri.TryCreate(text, UriKind.Absolute, out var url) || string.IsNullOrEmpty(url.Host)) return null;
        var scheme = url.Scheme.ToLowerInvariant();
        if (anyReleaseUrl) return scheme is "https" or "http" ? url : null;
        return scheme == "https" && url.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) ? url : null;
    }

    /// <summary>A test feed (SILL_TEST_UPDATE_FEED): on this PC only (127.0.0.1, ::1 or localhost, over http or https).</summary>
    public static bool IsLocalFeed(Uri url)
    {
        if (!url.IsAbsoluteUri || url.Scheme is not ("http" or "https")) return false;
        var host = url.Host.ToLowerInvariant();
        return host is "127.0.0.1" or "::1" or "[::1]" or "localhost";
    }

    // One answer

    /// <summary>Why a request got no HTTP answer.</summary>
    public enum FailureKind { Timeout, NoConnection, Tls, Other }

    /// <summary>What one request came back with, as the checker saw it.</summary>
    public abstract record Answer
    {
        /// <summary>Any HTTP status, with the body (at most <see cref="MaxBody"/>), the ETag and X-RateLimit-Reset.</summary>
        public sealed record Http(int Status, byte[] Body, string? ETag, DateTimeOffset? RateLimitReset) : Answer;
        /// <summary>A redirect somewhere other than api.github.com, refused.</summary>
        public sealed record Redirected(string Host) : Answer;
        /// <summary>A body over <see cref="MaxBody"/>.</summary>
        public sealed record TooLarge : Answer;
        /// <summary>No HTTP answer.</summary>
        public sealed record Failed(FailureKind Kind, string Description) : Answer;
    }

    /// <summary>What an answer comes to.</summary>
    public abstract record Outcome
    {
        /// <summary>A published release newer than this Sill.</summary>
        public sealed record Newer(Offer Offer) : Outcome;
        /// <summary>The latest release is not newer (its tag as written).</summary>
        public sealed record UpToDate(string Tag) : Outcome;
        /// <summary>404: GitHub has no release of Sill.</summary>
        public sealed record NoRelease : Outcome;
        /// <summary>403 or 429: GitHub is limiting this address (its X-RateLimit-Reset, when sent).</summary>
        public sealed record Limited(int Status, DateTimeOffset? Reset) : Outcome;
        public sealed record HttpError(int Status) : Outcome;
        /// <summary>An answer that is not a published release, and why.</summary>
        public sealed record NotARelease(string Why) : Outcome;
        /// <summary>No connection (offline, no DNS, refused, TLS intercepted).</summary>
        public sealed record NoConnection(bool Tls, string Description) : Outcome;
        public sealed record Timeout : Outcome;
        public sealed record Failed(string Description) : Outcome;

        /// <summary>GitHub answered with some HTTP status: the next automatic check is a period later.
        /// Otherwise it is <see cref="Retry"/> later, and nothing is stored.</summary>
        public bool Answered => this is not (NoConnection or Timeout or Failed);
    }

    /// <summary><paramref name="answer"/> from the feed, given what is stored and the running version:
    /// the outcome and what to store afterwards (§6.4's table).</summary>
    public static (Outcome Outcome, Stored Next) Interpret(Answer answer, Stored stored, SillVersion running, DateTimeOffset now, bool anyReleaseUrl)
    {
        switch (answer)
        {
            case Answer.Failed f:
                return f.Kind switch
                {
                    FailureKind.Timeout => (new Outcome.Timeout(), stored),
                    FailureKind.NoConnection => (new Outcome.NoConnection(false, f.Description), stored),
                    FailureKind.Tls => (new Outcome.NoConnection(true, f.Description), stored),
                    _ => (new Outcome.Failed(f.Description), stored),
                };
            case Answer.Redirected r:
                return (new Outcome.NotARelease($"a redirect to {r.Host}"), stored with { LastCheck = now });
            case Answer.TooLarge:
                return (new Outcome.NotARelease("more than 1 MB"), stored with { LastCheck = now });
            case Answer.Http h:
                var next = stored with { LastCheck = now };
                switch (h.Status)
                {
                    case 200:
                        var (release, why) = Release(h.Body, anyReleaseUrl);
                        if (release is null) return (new Outcome.NotARelease(why!), next);
                        // A 200 without an ETag clears it: the next request sends none.
                        next = next with { ETag = h.ETag, LatestTag = release.Tag, LatestUrl = release.Url.AbsoluteUri };
                        return (release.Version > running ? new Outcome.Newer(new Offer(release.Version, release.Tag, release.Url)) : new Outcome.UpToDate(release.Tag), next);
                    case 304:
                        // Only sent back for a stored release (If-None-Match goes out with one alone).
                        if (stored.LatestTag is not { } tag || SillVersion.Parse(tag) is not { } version || stored.LatestUrl is not { } text
                            || ReleasePage(text, anyReleaseUrl) is not { } url)
                            return (new Outcome.NotARelease("a 304 before any release"), next);
                        return (version > running ? new Outcome.Newer(new Offer(version, tag, url)) : new Outcome.UpToDate(tag), next);
                    case 404:
                        // A withdrawn release stops being offered.
                        return (new Outcome.NoRelease(), new Stored(now));
                    case 403 or 429:
                        return (new Outcome.Limited(h.Status, h.RateLimitReset), next);
                    default:
                        return (new Outcome.HttpError(h.Status), next);
                }
            default:
                throw new ArgumentOutOfRangeException(nameof(answer));
        }
    }

    public sealed record ReleaseInfo(string Tag, SillVersion Version, Uri Url);

    /// <summary>A 200's body as a published release: a JSON object with a string <c>tag_name</c> that
    /// parses, <c>draft</c> and <c>prerelease</c> not true, and an <c>html_url</c> Sill opens. Every
    /// other field is ignored.</summary>
    public static (ReleaseInfo? Release, string? Why) Release(byte[] body, bool anyReleaseUrl)
    {
        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(body);
            root = doc.RootElement.Clone();
        }
        catch (JsonException) { return (null, "not a JSON object"); }
        if (root.ValueKind != JsonValueKind.Object) return (null, "not a JSON object");
        if (!root.TryGetProperty("tag_name", out var tagElement) || tagElement.ValueKind != JsonValueKind.String) return (null, "no tag_name");
        if (root.TryGetProperty("draft", out var d) && d.ValueKind == JsonValueKind.True) return (null, "a draft");
        if (root.TryGetProperty("prerelease", out var p) && p.ValueKind == JsonValueKind.True) return (null, "a prerelease");
        var tag = tagElement.GetString()!;
        if (SillVersion.Parse(tag) is not { } version) return (null, $"the tag “{(tag.Length > 40 ? tag[..40] : tag)}” is not a version");
        if (!root.TryGetProperty("html_url", out var h) || h.ValueKind != JsonValueKind.String || ReleasePage(h.GetString()!, anyReleaseUrl) is not { } url)
            return (null, "html_url is not on github.com");
        return (new ReleaseInfo(tag, version, url), null);
    }

    // When

    /// <summary>An automatic check is due: never checked, a period or more ago, or "in the future" (the clock went back).</summary>
    public static bool IsDue(DateTimeOffset? lastCheck, DateTimeOffset now, TimeSpan period) =>
        lastCheck is not { } last || now - last >= period || last > now;

    /// <summary>When the next automatic check runs: at <paramref name="retryAt"/> after a check with no
    /// HTTP answer (never sooner than <paramref name="delay"/> from now), <paramref name="delay"/> from
    /// now when one is due, else a period and the jitter after the last answer.</summary>
    public static DateTimeOffset NextCheck(DateTimeOffset? lastCheck, DateTimeOffset? retryAt, DateTimeOffset now, TimeSpan period, TimeSpan jitter, TimeSpan delay)
    {
        if (retryAt is { } r) return r > now + delay ? r : now + delay;
        if (IsDue(lastCheck, now, period)) return now + delay;
        return lastCheck!.Value + period + jitter;
    }

    // This run

    /// <summary>Whether this run checks at all: Sill.exe does (<paramref name="sillExe"/>), the spike's
    /// Sill.Viewer.exe only with a test feed (SILL_TEST_UPDATE_FEED); and a test run
    /// (SILL_TEST_IDENTITY_DIR) never asks GitHub, only a test feed if it gives one.</summary>
    public static bool ChecksThisRun(bool sillExe, string? testFeed, string? testIdentityDir)
    {
        bool feed = !string.IsNullOrEmpty(testFeed);
        if (feed) return true;
        return sillExe && string.IsNullOrEmpty(testIdentityDir);
    }

    /// <summary>Where update.json and update.log go: <c>%LOCALAPPDATA%\Sill</c>, or a test run's own
    /// folder (SILL_TEST_IDENTITY_DIR), so a test never touches the PC's real state.</summary>
    public static string StateDirectory(string localAppData, string? testIdentityDir) =>
        !string.IsNullOrEmpty(testIdentityDir) ? testIdentityDir : localAppData.TrimEnd('\\', '/') + "\\Sill";

    // Words

    /// <summary>"Sill 0.6 Is Available…": the item the app shows.</summary>
    public static string MenuTitle(Offer offer) => $"Sill {offer.Version} Is Available…";
    /// <summary>"You have 0.5; opens its download page".</summary>
    public static string MenuSubtitle(SillVersion running) => $"You have {running}; opens its download page";

    /// <summary>The log's line for an outcome, null for none (an automatic check that found nothing new).</summary>
    public static string? LogLine(Outcome outcome, bool manual, string running, TimeSpan retryIn, Func<DateTimeOffset, string> time)
    {
        string again = manual ? "" : $"; trying again in {Duration(retryIn)}";
        return outcome switch
        {
            Outcome.Newer n => $"Update check: Sill {n.Offer.Version} is available (this is {running}): {n.Offer.Url.AbsoluteUri}",
            Outcome.UpToDate u => manual ? $"Update check: up to date (this is {running}; the latest release is {u.Tag})." : null,
            Outcome.NoRelease => "Update check failed: GitHub has no release of Sill (HTTP 404).",
            Outcome.Limited l => $"Update check failed: GitHub is limiting requests from this network (HTTP {l.Status}"
                + (l.Reset is { } reset ? $"; it resets at {time(reset)}" : "") + ").",
            Outcome.HttpError e => $"Update check failed: HTTP {e.Status}.",
            Outcome.NotARelease w => $"Update check failed: the answer is not a published release ({w.Why}).",
            Outcome.NoConnection c => $"Update check failed: no connection ({c.Description}){again}.",
            Outcome.Timeout => $"Update check failed: no answer in {(int)RequestTimeout.TotalSeconds} s{again}.",
            Outcome.Failed f => $"Update check failed: {f.Description}{again}.",
            _ => null,
        };
    }

    /// <summary>"1 hour", "15 minutes", "4 s": the retry's length as the log gives it.</summary>
    public static string Duration(TimeSpan span)
    {
        double s = span.TotalSeconds;
        if (s == 3600) return "1 hour";
        if (s >= 3600 && s % 3600 == 0) return $"{(int)(s / 3600)} hours";
        if (s >= 120) return $"{(int)Math.Round(s / 60)} minutes";
        return $"{(int)Math.Round(s)} s";
    }

    /// <summary>Settings' line after Check Now, and whether it is a failure.</summary>
    public static (string Text, bool Failed) ResultLine(Outcome outcome, Func<DateTimeOffset, string> time) => outcome switch
    {
        Outcome.Newer n => ($"Sill {n.Offer.Version} is available.", false),
        Outcome.UpToDate => ("Sill is up to date.", false),
        Outcome.NoRelease => ("Couldn’t check: GitHub has no release of Sill yet.", true),
        Outcome.Limited l => ("Couldn’t check: GitHub is limiting requests from this network. "
            + (l.Reset is { } reset ? $"Try again after {time(reset)}." : "Try again in an hour."), true),
        Outcome.HttpError e => ($"Couldn’t check: GitHub answered with an error (HTTP {e.Status}).", true),
        Outcome.NotARelease => ("Couldn’t check: GitHub’s answer wasn’t a release Sill understands.", true),
        Outcome.NoConnection c => (c.Tls ? $"Couldn’t check: {c.Description}" : "Couldn’t check: this PC isn’t connected to the internet.", true),
        Outcome.Timeout => ($"Couldn’t check: GitHub didn’t answer within {(int)RequestTimeout.TotalSeconds} seconds.", true),
        Outcome.Failed f => ($"Couldn’t check: {f.Description}", true),
        _ => ("", true),
    };

    /// <summary>What Settings shows about updates, as plain values.</summary>
    public sealed record Pane(string Line, bool Failed = false, Uri? ReleasePage = null, bool CanCheck = true, int ResultId = 0);

    public const string NotCheckedLine = "Not checked yet.";
    public const string NoVersionLine = "This build of Sill has no version number, so it can’t check.";

    /// <summary>The pane's line, first match wins: a check running; this run's Check Now result; no
    /// version; a newer release offered; when it last checked; never.</summary>
    public static Pane PaneFor(bool checking, Outcome? result, int resultId, Offer? offer, DateTimeOffset? lastCheck, bool hasVersion,
                               Func<DateTimeOffset, string> time, Func<DateTimeOffset, string> date)
    {
        var p = new Pane(NotCheckedLine, false, offer?.Url, hasVersion && !checking, resultId);
        if (checking) return p with { Line = "Checking…" };
        if (result is not null) { var (text, failed) = ResultLine(result, time); return p with { Line = text, Failed = failed }; }
        if (!hasVersion) return p with { Line = NoVersionLine };
        if (offer is not null) return p with { Line = $"Sill {offer.Version} is available." };
        if (lastCheck is { } last) return p with { Line = $"Last checked {date(last)}." };
        return p;
    }

    /// <summary>The setting's footnote.</summary>
    public const string Footnote = "Once a day, Sill asks GitHub whether a newer version is out. GitHub sees this PC’s IP address and which version of Sill it has; nothing else is sent. Sill never downloads or installs anything by itself: a new version opens its page on GitHub, where you download it.";
}
