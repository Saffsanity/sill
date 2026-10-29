using System.Net.Sockets;
using System.Security.Authentication;

namespace Sill.Protocol;

/// <summary>
/// Pairing's words on this PC: the iPad's (DiscoveryPolicy.swift's <c>HomeCopy</c>, the
/// <c>PairingProblem</c> texts of StreamClient+Remote.swift), with "click" for "tap" and "this PC"
/// for "this iPad".
/// </summary>
public static class PairingCopy
{
    public const string Device = "PC";

    public static string Pairing(string mac) => $"Pairing with {mac}…";
    public static string Showing(string mac) => $"{mac} is showing a code.";
    public static string CardTitle(string mac) => $"Enter the Code from {mac}";
    public static string TypeCode(string mac) => $"Type the code {mac} shows.";
    public static string Paired(string mac) => $"Paired with {mac}.";
    public static string OpenOnMac(string mac) =>
        $"{mac} didn’t show a code. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click {mac} again.";
    public static string Locked(string mac) => $"Unlock {mac}, then click it again.";
    public static string NoAnswer(string mac) => $"{mac} didn’t answer. Check that Sill is open on it, then click it again.";
    public static string NewKey(string mac) => $"{mac} has a new key since this {Device} paired. Click it to pair again.";
    public static string Stopped(string mac) =>
        $"{mac} stopped pairing after too many wrong codes. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click {mac} again.";
    public static string Expired(string mac) => $"That code expired. Click {mac} for a new one.";
    public static string Closed(string mac) =>
        $"That code no longer works. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click {mac} again.";
    public static string ProofFailed(string mac) => $"Pairing didn’t finish: {mac} couldn’t show it knows the code. Click it to try again.";

    public const string CodeLength = "A code has 12 digits.";
    public const string CodeTypo = "That code has a typo. Check it against your Mac.";
    public static string WrongCode(int left) => $"That code didn’t work. Check the code on your Mac. {left} tr{(left == 1 ? "y" : "ies")} left.";

    // Add a Mac…: a pasted link, or an address and a code (the iPad's typed path).
    public const string AddTitle = "Add a Mac";
    public const string AddLine = "Pair once, and Sill reaches your Mac from anywhere, through your VPN or the internet.";
    public const string AddHow = "Paste the link from Pair iPhone or iPad… on your Mac (Copy Link), or type the address and code it shows.";
    public const string Address = "That doesn’t look like an address. Try 100.101.102.103 or mac.example.net, with :port for another port.";
    public const string Zone = "Remove the part after %: it only works on this network.";
    public const string NotALink = "That isn’t a Sill pairing link.";
    public const string LinkNoAddress = "This link names no address. Type the Mac’s address instead, and the code.";
    public static string NothingAnswered(string host) => $"Nothing answered at {host}. Check the address, and that Sill is open on your Mac.";
    public static string NotSill(string host) => $"Something answered at {host}, but it isn’t Sill, or its Sill is too old to pair.";
    public static string OtherKey(string host) => $"The Mac at {host} isn’t the one this link is from.";
    public static string TypedProofFailed(string host) =>
        $"Pairing didn’t finish: the Mac at {host} couldn’t show it knows the code. Pair from the same network as your Mac, or paste its link instead.";

    /// <summary>A code refused at the home door (DiscoveryPolicy's <c>homeRefusal</c>): after a stop
    /// or a closed code the Mac keeps this device quiet a while, so the words send the person to the
    /// Mac's menu first; after an expiry a click is enough. A reason this build doesn't know shows
    /// the Mac's own words when it sent some.</summary>
    public static string HomeRefusal(PairResult r, string mac)
    {
        if (!PairResult.KnownReasons.Contains(r.Reason) && SafeText.Label(r.Message ?? "", 300) is { Length: > 0 } said) return said;
        return r.Reason switch
        {
            PairResult.WrongCode => WrongCode(Math.Max(0, r.TriesLeft ?? 0)),
            PairResult.Stopped => Stopped(mac),
            PairResult.Expired => Expired(mac),
            _ => Closed(mac),
        };
    }
}

/// <summary>The code field as it is typed: digits only, at most 12, in groups of four, and the
/// check digit judged once all 12 are there (a typo never costs one of the Mac's five tries).</summary>
public static class CodeEntry
{
    /// <summary>"4829 1355 7208": what the field shows for <paramref name="typed"/>
    /// (AddMacCard.swift's <c>PairingField.grouped</c>).</summary>
    public static string Grouped(string typed)
    {
        var digits = new string(typed.Where(char.IsAsciiDigit).Take(PairingCode.Length).ToArray());
        return PairingCode.Grouped(digits);
    }

    /// <summary>The problem to show under the field as it is typed: none until 12 digits, then the
    /// typo, if the check digit says so.</summary>
    public static string? WhileTyping(string typed) =>
        PairingCode.Check(typed, out _) == PairingCode.Problem.Typo ? PairingCopy.CodeTypo : null;

    /// <summary>Whether Pair can go: 12 digits whose check digit is right.</summary>
    public static bool Ready(string typed) => PairingCode.Check(typed, out _) == PairingCode.Problem.None;

    /// <summary>The problem when Pair is pressed, or null and the 12 digits.</summary>
    public static string? OnSubmit(string typed, out string code) => PairingCode.Check(typed, out code) switch
    {
        PairingCode.Problem.Length => PairingCopy.CodeLength,
        PairingCode.Problem.Typo => PairingCopy.CodeTypo,
        _ => null,
    };
}

/// <summary>Add a Mac…'s first field: a <c>sill://pair</c> link, or an address with an optional
/// port (the remote door's 7455 when it has none).</summary>
public static class AddMacInput
{
    /// <summary>The remote door's port by default (HostConfig's <c>remotePort</c>).</summary>
    public const int RemotePort = 7455;

    public static bool IsLink(string text) => text.TrimStart().StartsWith("sill://", StringComparison.OrdinalIgnoreCase);

    /// <summary><paramref name="text"/> as host and port: "100.101.102.103", "mac.example.net:7455",
    /// "[fd7a::1]:7455", "fd7a::1". Null and the problem's words when it isn't one.</summary>
    public static string? Address(string text, out string host, out int port)
    {
        host = ""; port = RemotePort;
        string s = text.Trim();
        if (s.Length == 0 || s.Any(char.IsWhiteSpace) || s.Contains('/') || s.Contains('@')) return PairingCopy.Address;
        if (s.Contains('%')) return PairingCopy.Zone;
        if (s.StartsWith('['))
        {
            int close = s.IndexOf(']');
            if (close < 2) return PairingCopy.Address;
            host = s[1..close];
            string rest = s[(close + 1)..];
            if (rest.Length > 0 && !(rest.StartsWith(':') && Port(rest[1..], out port))) return PairingCopy.Address;
            return System.Net.IPAddress.TryParse(host, out _) ? null : PairingCopy.Address;
        }
        if (s.Count(c => c == ':') > 1)   // a bare IPv6 address, no port
        {
            host = s;
            return System.Net.IPAddress.TryParse(s, out _) ? null : PairingCopy.Address;
        }
        int colon = s.IndexOf(':');
        if (colon >= 0)
        {
            if (!Port(s[(colon + 1)..], out port)) return PairingCopy.Address;
            s = s[..colon];
        }
        if (s.Length == 0 || s.StartsWith('.') || s.StartsWith('-') || !s.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_'))
            return PairingCopy.Address;
        host = s;
        return null;
    }

    private static bool Port(string text, out int port) =>
        int.TryParse(text, System.Globalization.NumberStyles.None, null, out port) && text.Length <= 5 && port is >= 1 and <= 65535;
}

/// <summary>An address to dial: a row's resolved address and port, a link's, or one typed.</summary>
public readonly record struct DoorAddress(string Host, int Port)
{
    public override string ToString() => Host.Contains(':') ? $"[{Host}]:{Port}" : $"{Host}:{Port}";

    /// <summary>"192.168.1.5:49880", "[fe80::1%12]:49880", "mac.local:49880": the last colon splits.</summary>
    public static DoorAddress? Parse(string text)
    {
        int colon = text.LastIndexOf(':');
        if (colon <= 0 || !int.TryParse(text[(colon + 1)..], out int port) || port is < 1 or > 65535) return null;
        string host = text[..colon].Trim('[', ']');
        return host.Length > 0 ? new DoorAddress(host, port) : null;
    }
}

/// <summary>The pairing connections a <see cref="PairingFlow"/> makes, so the flow runs without
/// a network in the tests. <see cref="TlsPairingDoor"/> is the real one.</summary>
public interface IPairingDoor
{
    Task<(PairResult? Result, byte[] MacFingerprint)> AskAsync(DoorAddress at, CancellationToken ct);
    Task<PairingClient.Outcome> CodeAsync(DoorAddress at, string code, byte[]? pin, CancellationToken ct);
    Task<PairingClient.Outcome> LinkAsync(DoorAddress at, PairLink link, CancellationToken ct);
    Task CancelAskAsync(DoorAddress at, byte[] pin, CancellationToken ct);
}

/// <summary>This PC's pairing connections over TLS (<see cref="PairingClient"/>), under its name.</summary>
public sealed class TlsPairingDoor(DeviceIdentity identity, Func<string> name) : IPairingDoor
{
    public const string Model = "Windows";

    public Task<(PairResult? Result, byte[] MacFingerprint)> AskAsync(DoorAddress at, CancellationToken ct) =>
        PairingClient.AskAsync(at.Host, at.Port, identity, name(), Model, ct);

    public Task<PairingClient.Outcome> CodeAsync(DoorAddress at, string code, byte[]? pin, CancellationToken ct) =>
        PairingClient.PairWithCodeAsync(at.Host, at.Port, code, identity, name(), Model, ct, pin);

    public Task<PairingClient.Outcome> LinkAsync(DoorAddress at, PairLink link, CancellationToken ct) =>
        PairingClient.PairWithLinkAsync(at.Host, at.Port, link, identity, name(), Model, ct);

    public async Task CancelAskAsync(DoorAddress at, byte[] pin, CancellationToken ct) =>
        await PairingClient.CancelAskAsync(at.Host, at.Port, identity, pin, name(), Model, ct).ConfigureAwait(false);
}

/// <summary>
/// One pairing from the connect screen, as the iPad's (StreamClient+Home.swift: <c>ask</c>,
/// <c>asked</c>, <c>pairHome</c>, <c>cancelHomeAsk</c>; StreamClient+Remote.swift's typed and link
/// paths), without any window: the form shows <see cref="Step"/>, <see cref="Line"/> and
/// <see cref="Problem"/> and calls in.
/// <list type="bullet">
/// <item>A "Not paired" row (<see cref="Home"/>): kind 19 "ask" to the row's addresses in turn, any
/// key; "shown" opens the code card, whose code goes to the address that answered, pinned to the key
/// it presented; "busy" is asked again once, silently; anything else ends with the iPad's words.</item>
/// <item>Add a Mac… (<see cref="AddMac"/>): a pasted link, pinned to its <c>k</c>, at its own
/// addresses in turn; or an address and a typed code, any key (the proofs bind both).</item>
/// </list>
/// A pairing saves the Mac (<see cref="ISavedMacs"/>; a row of a Mac set up again replaces its old
/// record) and ends at <see cref="Steps.Paired"/>, for the form to connect at <see cref="Reached"/>.
/// Cancel withdraws a code an ask put up (kind 19 "cancel"). Not thread-safe: one caller (the UI
/// thread) at a time.
/// </summary>
public sealed class PairingFlow
{
    public enum Steps
    {
        /// <summary>The ask is on its way (the connect screen's status line says so).</summary>
        Asking,
        /// <summary>The code card is up: waiting for the code (or the link, for Add a Mac).</summary>
        Code,
        /// <summary>A code or link is being proved; the card shows its progress.</summary>
        Proving,
        /// <summary>Paired and saved: connect.</summary>
        Paired,
        /// <summary>Over without pairing: <see cref="Line"/> says why (null for a Cancel).</summary>
        Ended,
    }

    /// <summary>How long each address has to answer when there are several (one alone gets the
    /// iPad's tap deadline, 10 s).</summary>
    public static readonly TimeSpan EachAddress = TimeSpan.FromSeconds(4), OneAddress = TimeSpan.FromSeconds(10);

    private readonly IPairingDoor door;
    private readonly ISavedMacs store;
    private readonly IReadOnlyList<DoorAddress> rowTargets;
    private readonly string? bonjourName;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private CancellationTokenSource cts = new();
    private DoorAddress? answered;
    private byte[]? askedKey;

    /// <summary>The Mac's name as the words give it: the row's, the link's, or the typed address.</summary>
    public string Mac { get; private set; }
    public bool IsAddMac { get; }
    public Steps Step { get; private set; }
    /// <summary>The status line: the connect screen's while asking and after the end; the card's progress while proving.</summary>
    public string? Line { get; private set; }
    /// <summary>The card's problem, under its field (orange).</summary>
    public string? Problem { get; private set; }
    /// <summary>The saved record a pairing from this row replaces (a Mac set up again).</summary>
    public string? Replaces { get; }
    /// <summary>Once paired: the Mac as saved, and the address the pairing reached.</summary>
    public SavedMac? Saved { get; private set; }
    public DoorAddress? Reached { get; private set; }
    public event Action? Changed;

    private PairingFlow(IPairingDoor door, ISavedMacs store, string mac, bool addMac, IReadOnlyList<DoorAddress> targets,
        string? replaces, string? bonjourName, Func<TimeSpan, CancellationToken, Task>? delay)
    {
        this.door = door; this.store = store; Mac = mac; IsAddMac = addMac; rowTargets = targets;
        Replaces = replaces; this.bonjourName = bonjourName;
        this.delay = delay ?? ((t, ct) => Task.Delay(t, ct));
        Step = addMac ? Steps.Code : Steps.Asking;
    }

    /// <summary>A row's pairing; start it with <see cref="AskAsync"/>.</summary>
    public static PairingFlow Home(IPairingDoor door, ISavedMacs store, string mac, IReadOnlyList<DoorAddress> targets,
        string? replaces = null, string? bonjourName = null, Func<TimeSpan, CancellationToken, Task>? delay = null) =>
        new(door, store, mac, addMac: false, targets, replaces, bonjourName, delay);

    /// <summary>Add a Mac…'s pairing: the card is up from the start.</summary>
    public static PairingFlow AddMac(IPairingDoor door, ISavedMacs store) =>
        new(door, store, "your Mac", addMac: true, [], null, null, null);

    private void Set(Steps step, string? line, string? problem = null)
    {
        Step = step; Line = line; Problem = problem;
        Changed?.Invoke();
    }

    // ---- the ask ----

    public async Task AskAsync()
    {
        var ct = cts.Token;
        Set(Steps.Asking, PairingCopy.Pairing(Mac));
        for (int round = 0; round < 2; round++)
        {
            (PairResult? Result, byte[] Key, DoorAddress At)? got = null;
            foreach (var at in rowTargets)
            {
                using var each = CancellationTokenSource.CreateLinkedTokenSource(ct);
                each.CancelAfter(rowTargets.Count > 1 ? EachAddress : OneAddress);
                try
                {
                    var (result, key) = await door.AskAsync(at, each.Token);
                    got = (result, key, at);
                    break;
                }
                catch (Exception) when (!ct.IsCancellationRequested) { }
                catch (OperationCanceledException) { return; }
            }
            if (ct.IsCancellationRequested) return;
            if (got is not { } a || a.Result is not { } r) { Set(Steps.Ended, PairingCopy.NoAnswer(Mac)); return; }
            if (r.Ok)
            {
                // An ok without a proof is the cable's, which this PC never claims.
                Set(Steps.Ended, PairingCopy.ProofFailed(Mac));
                return;
            }
            switch (r.Reason)
            {
                case PairResult.Shown:
                    answered = a.At; askedKey = a.Key;
                    Set(Steps.Code, PairingCopy.Showing(Mac));
                    return;
                case PairResult.Locked:
                    Set(Steps.Ended, PairingCopy.Locked(Mac));
                    return;
                case PairResult.Busy when round == 0:
                    try { await delay(TimeSpan.FromSeconds(Math.Clamp(r.RetryAfter ?? 1, 0.2, 10)), ct); }
                    catch (OperationCanceledException) { return; }
                    continue;
                default:
                    // openOnMac, a second busy, any refusal: the Mac's menu, which always works; a
                    // reason this build doesn't know shows the Mac's own words when it sent some.
                    string? said = PairResult.KnownReasons.Contains(r.Reason) ? null : SafeText.Label(r.Message ?? "", 300);
                    Set(Steps.Ended, said is { Length: > 0 } ? said : PairingCopy.OpenOnMac(Mac));
                    return;
            }
        }
    }

    // ---- the code card ----

    /// <summary>The home card's Pair: the typed code to the address the ask reached, pinned to its key.</summary>
    public async Task SubmitCodeAsync(string typed)
    {
        if (IsAddMac || Step is not Steps.Code || answered is not { } at || askedKey is not { } pin) return;
        if (CodeEntry.OnSubmit(typed, out string code) is { } problem) { Set(Steps.Code, Line, problem); return; }
        var ct = cts.Token;
        Set(Steps.Proving, PairingCopy.Pairing(Mac));
        PairingClient.Outcome outcome;
        try { outcome = await door.CodeAsync(at, code, pin, ct); }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            Set(Steps.Code, PairingCopy.Showing(Mac), PairingCopy.NoAnswer(Mac));
            return;
        }
        catch (OperationCanceledException) { return; }
        if (ct.IsCancellationRequested) return;
        switch (outcome.Verdict)
        {
            case PairingExchange.Verdict.Paired:
                Paired(outcome, at, Mac);
                break;
            case PairingExchange.Verdict.Refused:
                Set(Steps.Code, PairingCopy.Showing(Mac), PairingCopy.HomeRefusal(outcome.Result!, Mac));
                break;
            default:
                Set(Steps.Code, PairingCopy.Showing(Mac), PairingCopy.ProofFailed(Mac));
                break;
        }
    }

    /// <summary>Add a Mac…'s Pair: <paramref name="where"/> a pasted link (the code is not needed)
    /// or an address, with <paramref name="typed"/> the code.</summary>
    public async Task SubmitAddAsync(string where, string typed)
    {
        if (!IsAddMac || Step is not Steps.Code) return;
        var ct = cts.Token;
        if (AddMacInput.IsLink(where))
        {
            if (PairLink.Parse(where, out var link, out _) != PairLink.Failure.None || link is null) { Set(Steps.Code, null, PairingCopy.NotALink); return; }
            if (link.Addresses.Count == 0) { Set(Steps.Code, null, PairingCopy.LinkNoAddress); return; }
            Mac = link.Name;
            Set(Steps.Proving, PairingCopy.Pairing(Mac));
            bool otherKey = false, notSill = false;
            foreach (var host in link.Addresses)
            {
                var at = new DoorAddress(host.Trim('[', ']'), link.Port);
                using var each = CancellationTokenSource.CreateLinkedTokenSource(ct);
                each.CancelAfter(link.Addresses.Count > 1 ? EachAddress : OneAddress);
                PairingClient.Outcome outcome;
                try { outcome = await door.LinkAsync(at, link, each.Token); }
                catch (SillTls.PinMismatchException) { otherKey = true; continue; }
                catch (Exception e) when (!ct.IsCancellationRequested) { notSill |= IsNotSill(e); continue; }
                catch (OperationCanceledException) { return; }
                Proved(outcome, at, link.Name);   // this Mac answered: its answer stands
                return;
            }
            if (ct.IsCancellationRequested) return;
            string first = new DoorAddress(link.Addresses[0].Trim('[', ']'), link.Port).ToString();
            Set(Steps.Code, null, otherKey ? PairingCopy.OtherKey(first) : notSill ? PairingCopy.NotSill(first) : PairingCopy.NothingAnswered(first));
            return;
        }

        if (AddMacInput.Address(where, out string h, out int p) is { } bad) { Set(Steps.Code, null, bad); return; }
        if (CodeEntry.OnSubmit(typed, out string code) is { } problem) { Set(Steps.Code, null, problem); return; }
        var typedAt = new DoorAddress(h, p);
        Mac = typedAt.ToString();
        Set(Steps.Proving, PairingCopy.Pairing(Mac));
        try
        {
            using var wait = CancellationTokenSource.CreateLinkedTokenSource(ct);
            wait.CancelAfter(OneAddress);
            var outcome = await door.CodeAsync(typedAt, code, null, wait.Token);
            Proved(outcome, typedAt, null);
        }
        catch (Exception e) when (!ct.IsCancellationRequested)
        {
            Set(Steps.Code, null, IsNotSill(e) ? PairingCopy.NotSill(Mac) : PairingCopy.NothingAnswered(Mac));
        }
        catch (OperationCanceledException) { }
    }

    // The typed and link paths' answer, in the remote path's words (PairingExchange.Words).
    private void Proved(PairingClient.Outcome outcome, DoorAddress at, string? linkName)
    {
        switch (outcome.Verdict)
        {
            case PairingExchange.Verdict.Paired:
                Paired(outcome, at, linkName ?? outcome.Result?.Name ?? "Mac");
                return;
            case PairingExchange.Verdict.Refused:
                Set(Steps.Code, null, PairingExchange.Words(outcome.Result!, SafeText.Label(outcome.Result!.Name ?? linkName ?? "The Mac")));
                return;
            default:
                Set(Steps.Code, null, PairingCopy.TypedProofFailed(at.ToString()));
                return;
        }
    }

    private static bool IsNotSill(Exception e) => e is AuthenticationException or InvalidDataException
        || (e is IOException && e.InnerException is not SocketException);

    private void Paired(PairingClient.Outcome outcome, DoorAddress at, string fallbackName)
    {
        var r = outcome.Result!;
        string name = SafeText.Label(r.Name ?? fallbackName);
        var mac = new SavedMac(Base64Url.Encode(outcome.MacFingerprint), r.MacId!, name.Length == 0 ? "Mac" : name,
                               r.RecognitionKey!, at.Host, at.Port, DateTimeOffset.UtcNow, bonjourName);
        store.Add(mac, Replaces);
        Saved = mac; Reached = at; Mac = mac.Name;
        askedKey = null;   // nothing to withdraw: the window closed with the pairing
        Set(Steps.Paired, PairingCopy.Paired(mac.Name));
    }

    /// <summary>The card's Cancel, Esc, or a click elsewhere: whatever is on its way stops, nothing
    /// is saved, and a code an ask put up on the Mac is withdrawn (kind 19 "cancel", fire and forget).</summary>
    public void Cancel()
    {
        if (Step is Steps.Paired or Steps.Ended) return;
        cts.Cancel();
        cts = new CancellationTokenSource();
        Withdraw();
        Set(Steps.Ended, null);
    }

    /// <summary>The withdrawal's task, for the tests.</summary>
    public Task? Withdrawal { get; private set; }

    private void Withdraw()
    {
        if (answered is not { } at || askedKey is not { } pin) return;
        askedKey = null;
        Withdrawal = Task.Run(async () =>
        {
            using var wait = new CancellationTokenSource(OneAddress);
            try { await door.CancelAskAsync(at, pin, wait.Token).ConfigureAwait(false); }
            catch (Exception) { }   // nothing follows from its answer (always "closed")
        });
    }
}
