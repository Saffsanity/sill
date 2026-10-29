using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Authentication;

namespace Sill.Protocol;

/// <summary>
/// How this PC dials a saved Mac (iOSClient/RemoteDialPolicy.swift, docs/remote-access-plan.md
/// §7.5): the order of its addresses, what ended each attempt, and which failure the status line
/// words when every attempt failed. Pure but for <see cref="LocalIPv4"/>.
/// </summary>
public static class RemoteDialPolicy
{
    /// <summary>Attempts start this far apart, or at once when the one before fails.</summary>
    public static readonly TimeSpan Stagger = TimeSpan.FromSeconds(1);
    /// <summary>One attempt's connect (TCP and TLS) gives up after this (RemoteTLS.dialTimeout).</summary>
    public static readonly TimeSpan AttemptTimeout = TimeSpan.FromSeconds(10);
    /// <summary>The whole dial gives up after this.</summary>
    public static readonly TimeSpan WholeDial = TimeSpan.FromSeconds(20);

    /// <summary>One address to dial. <see cref="Row"/>: the Mac's row on this network (its home
    /// door, as the browser resolved it), not a saved address.</summary>
    public sealed record Candidate(string Host, int Port, string Kind, string Via, bool Row = false)
    {
        /// <summary>"host|port", how <see cref="SavedMac.LastWorked"/> names the address that won.</summary>
        public string Key => $"{Host}|{Port}";
        public bool IsName => IPv4.Parse(Host) is null && !Host.Contains(':');
        public bool IsIPv6 => Host.Contains(':');
        /// <summary>"100.101.102.103", or "[fd7a::1]:7460" with a port other than the usual one.</summary>
        public string Display => Port == AddMacInput.RemotePort ? Host : $"{(IsIPv6 ? $"[{Host}]" : Host)}:{Port}";
        public DoorAddress Door => new(Host, Port);
    }

    /// <summary>
    /// The saved addresses' dial order (<c>order</c> in RemoteDialPolicy.swift): the address that
    /// last worked; VPN names, VPN IPv4, VPN IPv6; LAN addresses in a subnet this PC shares; internet
    /// names, then internet addresses; the other LAN addresses (reached through a VPN into the home
    /// network). A loopback address goes before all of them (only a test host lists one). Duplicates
    /// (same host and port) are dialed once.
    /// </summary>
    public static IReadOnlyList<Candidate> Order(IEnumerable<MacAddress> addresses, int remotePort, string? lastWorked,
        IReadOnlyList<(byte[] Address, int Prefix)> localIPv4)
    {
        var all = addresses.Select(a => new Candidate(a.Host, a.Port ?? remotePort, a.Kind, a.Via)).ToList();
        bool Vpn(Candidate c) => c.Kind == MacAddress.Vpn || IsVpnAddress(c.Host);
        bool Shared(Candidate c) => IPv4.Parse(c.Host) is { } a && localIPv4.Any(l => IPv4.SameNetwork(a, l.Address, l.Prefix));
        static bool Loopback(Candidate c) => c.Host.StartsWith("127.") || c.Host == "::1";
        var vpns = all.Where(Vpn).ToList();
        var lans = all.Where(c => !Vpn(c) && c.Kind == MacAddress.Lan).ToList();
        var internet = all.Where(c => !Vpn(c) && c.Kind != MacAddress.Lan).ToList();
        var ordered = all.Where(Loopback).ToList();
        ordered.AddRange(vpns.Where(c => c.IsName));
        ordered.AddRange(vpns.Where(c => !c.IsName && !c.IsIPv6));
        ordered.AddRange(vpns.Where(c => c.IsIPv6));
        ordered.AddRange(lans.Where(c => Shared(c) && !Loopback(c)));
        ordered.AddRange(internet.Where(c => c.IsName));
        ordered.AddRange(internet.Where(c => !c.IsName));
        ordered.AddRange(lans.Where(c => !Shared(c) && !Loopback(c)));
        if (lastWorked is not null && ordered.FindIndex(c => c.Key == lastWorked) is var i and > 0)
        {
            var c = ordered[i];
            ordered.RemoveAt(i);
            ordered.Insert(0, c);
        }
        var seen = new HashSet<string>();
        return ordered.Where(c => seen.Add(c.Key.ToLowerInvariant())).ToList();
    }

    /// <summary>
    /// Everything one dial of a saved Mac tries, in order: the Mac's row on this network first (its
    /// addresses as the browser resolved them; none when it isn't listed here), then the saved
    /// addresses in <see cref="Order"/>'s order. A saved address equal to a row's is dialed once, as
    /// the row's.
    /// </summary>
    public static IReadOnlyList<Candidate> Plan(IEnumerable<DoorAddress> row, SavedMac mac, IReadOnlyList<(byte[] Address, int Prefix)> localIPv4)
    {
        var list = row.Select(d => new Candidate(d.Host, d.Port, MacAddress.Lan, "", Row: true)).ToList();
        var seen = list.Select(c => c.Key.ToLowerInvariant()).ToHashSet();
        foreach (var c in Order(mac.AllAddresses, mac.RemotePort ?? AddMacInput.RemotePort, mac.LastWorked, localIPv4))
            if (seen.Add(c.Key.ToLowerInvariant())) list.Add(c);
        return list;
    }

    /// <summary>Tailscale's shapes: 100.64/10, fd7a:115c:a1e0::/48, a .ts.net name.</summary>
    public static bool IsVpnAddress(string host)
    {
        if (IPv4.Parse(host) is { } a) return a[0] == 100 && (a[1] & 0xC0) == 64;
        if (host.StartsWith("fd7a:115c:a1e0:", StringComparison.OrdinalIgnoreCase)) return true;
        return IsTailscaleName(host);
    }

    public static bool IsTailscaleName(string host)
    {
        string h = host.ToLowerInvariant();
        return h.EndsWith(".ts.net") || h.EndsWith(".ts.net.");
    }

    /// <summary>The kind of an address that came without one (typed, from a link, a pairing's):
    /// Tailscale's shapes "vpn", private and link-local ranges and loopback "lan", else "internet".</summary>
    public static string KindOfHost(string host)
    {
        if (IsVpnAddress(host)) return MacAddress.Vpn;
        if (IPv4.Parse(host) is { } a)
        {
            bool lan = a[0] == 10 || (a[0] == 172 && (a[1] & 0xF0) == 16) || (a[0] == 192 && a[1] == 168)
                || (a[0] == 169 && a[1] == 254) || a[0] == 127;
            return lan ? MacAddress.Lan : MacAddress.Internet;
        }
        string h = host.ToLowerInvariant();
        if (h.Contains(':'))
            return h.StartsWith("fc") || h.StartsWith("fd") || h.StartsWith("fe8") || h == "::1" ? MacAddress.Lan : MacAddress.Internet;
        return h.EndsWith(".local") || h == "localhost" ? MacAddress.Lan : MacAddress.Internet;
    }

    // ---- failures ----

    /// <summary>What ended one attempt (RemoteDialPolicy.swift's <c>End</c>, as .NET reports it).</summary>
    public enum End
    {
        /// <summary>Another key than the pin answered (iOS's -9808).</summary>
        WrongKey,
        /// <summary>The Mac closed the connection before or during TLS, or refused it.</summary>
        Refused,
        NameNotFound,
        /// <summary>The attempt's own connect timeout.</summary>
        Timeout,
        /// <summary>No route, the host down.</summary>
        Unreachable,
        /// <summary>A wrong protocol or ALPN, or a message no Sill sends.</summary>
        NotSill,
        Other,
    }

    /// <summary>Why a dial failed, most telling first in <see cref="Priority"/>.</summary>
    public enum Failure { WrongMac, Revoked, RemoteOff, Busy, Refused, VpnOff, NameNotFound, NotSill, NoAnswer }

    /// <summary>Wrong Mac first (acting on anything else would be wrong), then the Mac's own
    /// answers, then what this PC can fix, then silence.</summary>
    public static readonly Failure[] Priority =
        [Failure.WrongMac, Failure.Revoked, Failure.RemoteOff, Failure.Busy, Failure.Refused, Failure.VpnOff, Failure.NameNotFound, Failure.NotSill, Failure.NoAnswer];

    public static Failure? Worst(IEnumerable<Failure> failures)
    {
        var set = failures.ToHashSet();
        return Priority.Where(set.Contains).Cast<Failure?>().FirstOrDefault();
    }

    /// <summary>One attempt's end as .NET threw it.</summary>
    public static End EndOf(Exception e)
    {
        for (var x = e; x is not null; x = x.InnerException)
            switch (x)
            {
                case SillTls.PinMismatchException: return End.WrongKey;
                case OperationCanceledException or TimeoutException: return End.Timeout;
                case SocketException s:
                    return s.SocketErrorCode switch
                    {
                        SocketError.ConnectionRefused or SocketError.ConnectionReset or SocketError.ConnectionAborted or SocketError.Shutdown => End.Refused,
                        SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain => End.NameNotFound,
                        SocketError.TimedOut => End.Timeout,
                        SocketError.NetworkUnreachable or SocketError.HostUnreachable or SocketError.NetworkDown or SocketError.HostDown
                            or SocketError.AddressNotAvailable => End.Unreachable,
                        _ => End.Other,
                    };
            }
        // A TLS handshake the Mac cut short is a close (its limits, a source it holds off); one that
        // finished in something other than TLS 1.3 with sill/1, or bytes no Sill sends, isn't Sill.
        return e switch
        {
            AuthenticationException { InnerException: IOException } => End.Refused,
            AuthenticationException or InvalidDataException => End.NotSill,
            IOException => End.Refused,
            _ => End.Other,
        };
    }

    /// <summary>One attempt's end as a failure (<c>classify</c>); null for one that doesn't count:
    /// another key at a LAN address is a stranger at that number, not a wrong Mac. Windows doesn't
    /// say whether a path went through a tunnel, so a silent VPN address is "didn't answer".</summary>
    public static Failure? Classify(End end, Candidate candidate) => end switch
    {
        End.WrongKey => candidate.Kind == MacAddress.Lan && !IsVpnAddress(candidate.Host) ? null : Failure.WrongMac,
        End.Refused => Failure.Refused,
        End.NameNotFound => IsTailscaleName(candidate.Host) ? Failure.VpnOff : Failure.NameNotFound,
        End.NotSill => Failure.NotSill,
        _ => Failure.NoAnswer,
    };

    /// <summary>A goodbye that ended a session before its first window list, as a dial's failure.</summary>
    public static Failure Classify(string goodbyeReason) => goodbyeReason switch
    {
        GoodbyePolicy.Removed => Failure.Revoked,
        GoodbyePolicy.RemoteOff => Failure.RemoteOff,
        GoodbyePolicy.Busy => Failure.Busy,
        _ => Failure.Refused,
    };

    /// <summary>This PC's IPv4 networks (address and prefix length), for <see cref="Order"/>.</summary>
    public static IReadOnlyList<(byte[] Address, int Prefix)> LocalIPv4()
    {
        var list = new List<(byte[], int)>();
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up) continue;
                foreach (var u in nic.GetIPProperties().UnicastAddresses)
                    if (u.Address.AddressFamily == AddressFamily.InterNetwork && u.PrefixLength is > 0 and <= 32)
                        list.Add((u.Address.GetAddressBytes(), u.PrefixLength));
            }
        }
        catch (NetworkInformationException) { }
        return list;
    }

    public static class IPv4
    {
        /// <summary>Four decimal octets, nothing else.</summary>
        public static byte[]? Parse(string s)
        {
            var parts = s.Split('.');
            if (parts.Length != 4) return null;
            var bytes = new byte[4];
            for (int i = 0; i < 4; i++)
            {
                var p = parts[i];
                if (p.Length is 0 or > 3 || !p.All(char.IsAsciiDigit) || !byte.TryParse(p, out bytes[i])) return null;
            }
            return bytes;
        }

        public static bool SameNetwork(byte[] a, byte[] b, int prefix)
        {
            if (a.Length != 4 || b.Length != 4 || prefix is < 1 or > 32) return false;
            int bits = prefix;
            for (int i = 0; i < 4; i++)
            {
                int n = Math.Clamp(bits, 0, 8);
                byte mask = n == 0 ? (byte)0 : unchecked((byte)(0xFF << (8 - n)));
                if ((a[i] & mask) != (b[i] & mask)) return false;
                bits -= 8;
            }
            return true;
        }
    }
}

/// <summary>The status line's words for a dial that failed (StreamClient+Remote.swift's
/// <c>RemoteCopy.dialFailure</c>), with "click" for "tap" and "this PC" for "this iPad".</summary>
public static class RemoteCopy
{
    public static string DialFailure(RemoteDialPolicy.Failure failure, string mac, RemoteDialPolicy.Candidate? candidate, string? vpnName)
    {
        const string device = PairingCopy.Device;
        string at = candidate?.Display ?? "its address";
        switch (failure)
        {
            case RemoteDialPolicy.Failure.WrongMac:
                return $"This isn’t the {mac} this {device} paired with. If Sill was set up again on it, forget it here and pair again.";
            case RemoteDialPolicy.Failure.Revoked:
                return $"{mac} no longer accepts this {device}. Pair it again from Sill’s Settings on the Mac.";
            case RemoteDialPolicy.Failure.RemoteOff:
                return $"{mac} turned off Remote Access.";
            case RemoteDialPolicy.Failure.Busy:
                return $"{mac} is already serving 8 devices.";
            case RemoteDialPolicy.Failure.Refused:
                return $"{mac} answered, but Sill isn’t accepting remote connections there. Check that Sill is open and Remote Access is on. If you changed its port, connect at home once.";
            case RemoteDialPolicy.Failure.VpnOff:
                string? name = candidate is null ? null : VpnLabel(candidate);
                return $"{name ?? "Your VPN"} looks off on this {device}. Turn it on, then click {mac}.";
            case RemoteDialPolicy.Failure.NameNotFound:
                string host = candidate?.Host ?? "its name";
                return RemoteDialPolicy.IsTailscaleName(host) ? $"This {device} can’t look up {host}. Is Tailscale on?" : $"This {device} can’t look up {host}.";
            case RemoteDialPolicy.Failure.NotSill:
                return $"Something answered at {at}, but it isn’t Sill. Your home’s internet address may have changed.";
            default:
                if (candidate is { Kind: MacAddress.Internet, IsName: false })
                    return $"{mac} didn’t answer at {at}. If your home’s internet address changed, connect at home once to update it, or add an address name on the Mac.";
                return vpnName is not null ? $"{mac} didn’t answer. It may be asleep, or {vpnName} may be off on the Mac." : $"{mac} didn’t answer. It may be asleep.";
        }
    }

    /// <summary>A VPN address's service name when it carries one ("Tailscale", "Home WireGuard").</summary>
    public static string? VpnLabel(RemoteDialPolicy.Candidate c)
    {
        if (!(c.Kind == MacAddress.Vpn || RemoteDialPolicy.IsVpnAddress(c.Host))) return null;
        if (c.Via.Length > 0 && !c.Via.StartsWith("VPN (") && c.Via is not ("Router" or "Address name" or "IPv6" or "This Mac")) return c.Via;
        return RemoteDialPolicy.IsVpnAddress(c.Host) ? "Tailscale" : null;
    }

    /// <summary>The VPN a saved Mac is reached through, for "…or Tailscale may be off on the Mac".</summary>
    public static string? VpnName(SavedMac mac) =>
        mac.AllAddresses.Select(a => VpnLabel(new RemoteDialPolicy.Candidate(a.Host, a.Port ?? AddMacInput.RemotePort, a.Kind, a.Via)))
            .FirstOrDefault(n => n is not null);
}

/// <summary>
/// One dial of a Mac at several addresses, happy eyeballs (RemoteConnector.swift): attempts start
/// <see cref="RemoteDialPolicy.Stagger"/> apart, or at once when the one before fails; each gives
/// up after its own timeout, the whole dial after another; the first to connect wins and the others
/// are cancelled (one that connects anyway is handed to <c>discard</c>), so the Mac serves one
/// session. Pure but for the clock: the connection is the caller's function.
/// </summary>
public static class HappyEyeballs
{
    public sealed record Result<T>(T? Winner, RemoteDialPolicy.Candidate? Won, IReadOnlyList<(RemoteDialPolicy.Candidate Candidate, Exception Error)> Failures)
        where T : class;

    public static async Task<Result<T>> RaceAsync<T>(IReadOnlyList<RemoteDialPolicy.Candidate> candidates,
        Func<RemoteDialPolicy.Candidate, CancellationToken, Task<T>> connect, Func<T, Task> discard,
        TimeSpan stagger, TimeSpan attemptTimeout, TimeSpan wholeDial, CancellationToken ct) where T : class
    {
        using var whole = CancellationTokenSource.CreateLinkedTokenSource(ct);
        whole.CancelAfter(wholeDial);
        var running = new List<(Task<T> Task, RemoteDialPolicy.Candidate Candidate, CancellationTokenSource Cts)>();
        var failures = new List<(RemoteDialPolicy.Candidate, Exception)>();
        int next = 0;
        Task? staggered = null;

        void StartNext()
        {
            var c = candidates[next++];
            var cts = CancellationTokenSource.CreateLinkedTokenSource(whole.Token);
            cts.CancelAfter(attemptTimeout);
            Task<T> task;
            try { task = connect(c, cts.Token); }
            catch (Exception e) { task = Task.FromException<T>(e); }
            running.Add((task, c, cts));
            staggered = next < candidates.Count ? Task.Delay(stagger, whole.Token) : null;
        }

        try
        {
            if (candidates.Count > 0) StartNext();
            while (running.Count > 0)
            {
                var waits = running.Select(r => (Task)r.Task).ToList();
                if (staggered is not null) waits.Add(staggered);
                var done = await Task.WhenAny(waits).ConfigureAwait(false);
                if (done == staggered)
                {
                    staggered = null;
                    if (!whole.IsCancellationRequested && next < candidates.Count) StartNext();
                    continue;
                }
                int i = running.FindIndex(r => r.Task == done);
                var (task, candidate, cts) = running[i];
                running.RemoveAt(i);
                cts.Dispose();
                if (task.IsCompletedSuccessfully)
                {
                    foreach (var other in running) { other.Cts.Cancel(); _ = DiscardLate(other.Task, other.Cts, discard); }
                    running.Clear();
                    return new Result<T>(task.Result, candidate, failures);
                }
                failures.Add((candidate, task.Exception?.InnerException ?? new OperationCanceledException()));
                // The one before failed: the next starts at once, not a second later.
                if (!whole.IsCancellationRequested && next < candidates.Count) StartNext();
            }
            ct.ThrowIfCancellationRequested();
            return new Result<T>(null, null, failures);
        }
        finally
        {
            foreach (var r in running) { r.Cts.Cancel(); _ = DiscardLate(r.Task, r.Cts, discard); }
        }
    }

    private static async Task DiscardLate<T>(Task<T> task, CancellationTokenSource cts, Func<T, Task> discard)
    {
        try { var late = await task.ConfigureAwait(false); await discard(late).ConfigureAwait(false); }
        catch (Exception) { }
        finally { cts.Dispose(); }
    }
}
