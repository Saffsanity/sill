using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;
using static Sill.Protocol.RemoteDialPolicy;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 10c: kind 18, the saved addresses, the dial order, happy eyeballs, the reconnect.</summary>
public class AwayTests
{
    private static readonly ECDsa MacKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private static readonly ECDsa OtherKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private static byte[] Fp(ECDsa key) => Spki.Fingerprint(key)!;

    private static MacInfo Info(ECDsa key, double issuedAt = 100, bool remoteAccess = true, params MacAddress[] addresses) =>
        new(1, MacId.Make(Fp(key)), "Mac mini", issuedAt, remoteAccess, 7460, false,
            addresses.Length > 0 ? addresses : [new("mac-mini.tail1234.ts.net", null, "vpn", "Tailscale"), new("100.101.102.103", null, "vpn", "Tailscale")]);

    private static SavedMac Saved(ECDsa key) =>
        new(Base64Url.Encode(Fp(key)), MacId.Make(Fp(key)), "Mac mini", Base64Url.Encode(new byte[32]), "192.168.1.5", 49870, DateTimeOffset.UnixEpoch);

    // ---- kind 18 ----

    [Fact]
    public void ASwiftSignedKind18Verifies()
    {
        // Made by CryptoKit as SignedMacInfo.signing does: the exact info bytes, X9.63 key, DER signature.
        var signed = JsonSerializer.Deserialize<SignedMacInfo>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "macinfo-swift.json")))!;
        var (info, fp) = signed.Verified()!.Value;
        Assert.Equal("9PGP8G2C37TCGCVG", info.MacId);
        Assert.Equal(MacId.Make(fp), info.MacId);
        Assert.Equal((1792500000.5, 7455, true), (info.IssuedAt, info.RemotePort, info.RemoteAccess));
        Assert.Equal(["mac-mini.tail1234.ts.net", "100.101.102.103", "192.168.1.5"], info.Addresses.Select(a => a.Host));
        Assert.Null(info.Addresses[0].Port);
        Assert.Equal("Wi‑Fi", info.Addresses[2].Via);
    }

    [Fact]
    public void ABadSignatureAnotherKeyOrGarbageIsRefused()
    {
        var good = SignedMacInfo.Signing(Info(MacKey), MacKey);
        Assert.NotNull(good.Verified());
        // The info changed after signing.
        var bytes = Convert.FromBase64String(good.Info);
        bytes[^3] ^= 1;
        Assert.Null((good with { Info = Convert.ToBase64String(bytes) }).Verified());
        // Signed by another key, which names it: the Mac ID is the first key's.
        Assert.Null(SignedMacInfo.Signing(Info(MacKey), OtherKey).Verified());
        // The other key's own info, signature and key: verifies, but as the other Mac.
        Assert.Equal(MacId.Make(Fp(OtherKey)), SignedMacInfo.Signing(Info(OtherKey), OtherKey).Verified()!.Value.Info.MacId);
        // A signature from another key over the same bytes, with this key claimed.
        var forged = good with { Sig = SignedMacInfo.Signing(Info(MacKey), OtherKey).Sig };
        Assert.Null(forged.Verified());
        Assert.Null((good with { Key = Convert.ToBase64String(new byte[65]) }).Verified());
        Assert.Null((good with { Key = Convert.ToBase64String(new byte[33]) }).Verified());
        Assert.Null((good with { Sig = "not base64!" }).Verified());
        Assert.Null((good with { Info = Convert.ToBase64String("not json"u8) }).Verified());
    }

    [Fact]
    public void TakingKeepsTheNewestFromThePinnedKeyAlone()
    {
        var mac = Saved(MacKey);
        IReadOnlyList<SavedMac> list = [mac];
        var signed = SignedMacInfo.Signing(Info(MacKey, 100), MacKey);
        var taken = SavedMacs.Taking(signed, mac.MacId, Fp(MacKey), list, allowLoopback: false)!;
        Assert.Equal(["mac-mini.tail1234.ts.net", "100.101.102.103"], taken[0].Addresses!.Select(a => a.Host));
        Assert.Equal((7460, 100.0), (taken[0].RemotePort, taken[0].InfoIssuedAt));
        // The same again, or an older one: nothing changes.
        Assert.Null(SavedMacs.Taking(signed, mac.MacId, Fp(MacKey), taken, false));
        Assert.Null(SavedMacs.Taking(SignedMacInfo.Signing(Info(MacKey, 99), MacKey), mac.MacId, Fp(MacKey), taken, false));
        // A Mac's kind 18 replayed on another Mac's connection names nothing.
        Assert.Null(SavedMacs.Taking(SignedMacInfo.Signing(Info(MacKey, 200), MacKey), mac.MacId, Fp(OtherKey), taken, false));
        // Another Mac's own kind 18 on its own connection, for this Mac's record: not this pin.
        Assert.Null(SavedMacs.Taking(SignedMacInfo.Signing(Info(OtherKey, 200), OtherKey), mac.MacId, Fp(OtherKey), taken, false));
        // A Mac not saved.
        Assert.Null(SavedMacs.Taking(SignedMacInfo.Signing(Info(OtherKey, 200), OtherKey), MacId.Make(Fp(OtherKey)), Fp(OtherKey), taken, false));
    }

    [Fact]
    public void AnEmptyOrRemoteOffKind18KeepsTheSavedAddresses()
    {
        var mac = Saved(MacKey) with { Addresses = [new("100.101.102.103", null, "vpn", "Tailscale")], InfoIssuedAt = 10, RemotePort = 7455 };
        var off = SavedMacs.Refreshed(mac, Info(MacKey, 20, remoteAccess: false) with { Name = "Studio", RemotePort = 7470 }, Fp(MacKey), false)!;
        Assert.Equal(["100.101.102.103"], off.Addresses!.Select(a => a.Host));
        Assert.Equal(("Studio", 7470, 20.0), (off.Name, off.RemotePort, off.InfoIssuedAt));
        var empty = SavedMacs.Refreshed(mac, Info(MacKey, 30) with { Addresses = [] }, Fp(MacKey), false)!;
        Assert.Equal(["100.101.102.103"], empty.Addresses!.Select(a => a.Host));
        // Only addresses that work elsewhere: no link-local, zone or loopback (but in a test).
        var mixed = Info(MacKey, 40, true, new("fe80::1", null, "lan", "Wi‑Fi"), new("192.168.1.5%en0", null, "lan", ""),
            new("169.254.3.4", null, "lan", ""), new("127.0.0.1", null, "lan", "This Mac"), new("10.0.0.2", null, "lan", "Wi‑Fi"));
        Assert.Equal(["10.0.0.2"], SavedMacs.Refreshed(mac, mixed, Fp(MacKey), false)!.Addresses!.Select(a => a.Host));
        Assert.Equal(["127.0.0.1", "10.0.0.2"], SavedMacs.Refreshed(mac, mixed, Fp(MacKey), true)!.Addresses!.Select(a => a.Host));
        // An empty name keeps the saved one.
        Assert.Equal("Mac mini", SavedMacs.Refreshed(mac, Info(MacKey, 50) with { Name = "‮" }, Fp(MacKey), false)!.Name);
    }

    [Fact]
    public void AnOldRecordLoadsAndTheNewFieldsRoundTrip()
    {
        string dir = Path.Combine(Path.GetTempPath(), "sill-away-" + Guid.NewGuid().ToString("N"));
        try
        {
            var mac = Saved(MacKey);
            Directory.CreateDirectory(dir);
            // As 10b wrote it.
            File.WriteAllText(Path.Combine(dir, "macs.json"),
                $$"""{"Macs":[{"Fingerprint":"{{mac.Fingerprint}}","MacId":"{{mac.MacId}}","Name":"Mac mini","RecognitionKey":"{{mac.RecognitionKey}}","Host":"192.168.1.5","Port":49870,"PairedAt":"2026-10-19T10:00:00+00:00"}]}""");
            ISavedMacs store = new SavedMacsFile(dir);
            var old = Assert.Single(store.Load());
            Assert.Null(old.Addresses);
            Assert.Equal(["192.168.1.5"], old.AllAddresses.Select(a => a.Host));
            Assert.True(store.TakeMacInfo(SignedMacInfo.Signing(Info(MacKey, 5), MacKey), mac.MacId, Fp(MacKey), false));
            store.Connected(mac.MacId, "100.101.102.103|7460");
            var again = Assert.Single(new SavedMacsFile(dir).Load());
            Assert.Equal(["mac-mini.tail1234.ts.net", "100.101.102.103", "192.168.1.5"], again.AllAddresses.Select(a => a.Host));
            Assert.Equal(("100.101.102.103|7460", 7460), (again.LastWorked, again.RemotePort));
            Assert.NotNull(again.LastConnectedAt);
            Assert.DoesNotContain("\"port\"", File.ReadAllText(Path.Combine(dir, "macs.json")));   // nulls left out
            store.Connected(mac.MacId, null);   // a row's address: the last worked stays
            Assert.Equal("100.101.102.103|7460", new SavedMacsFile(dir).Load()[0].LastWorked);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true); }
    }

    // ---- the dial order ----

    private static readonly IReadOnlyList<(byte[] Address, int Prefix)> Home = [([192, 168, 1, 20], 24)];

    [Fact]
    public void TheOrderIsTheIPadsAndLastWorkedLeads()
    {
        MacAddress[] addresses =
        [
            new("203.0.113.7", null, "internet", "Router"),
            new("10.0.0.9", null, "lan", "Wi‑Fi"),
            new("fd7a:115c:a1e0::5", null, "vpn", "Tailscale"),
            new("192.168.1.5", null, "lan", "Wi‑Fi"),
            new("100.101.102.103", null, "vpn", "Tailscale"),
            new("mac.example.net", 7470, "internet", "Address name"),
            new("mac-mini.tail1234.ts.net", null, "vpn", "Tailscale"),
            new("127.0.0.1", null, "lan", "This Mac"),
            new("100.101.102.103", null, "vpn", "Tailscale"),
        ];
        Assert.Equal(["127.0.0.1|7455", "mac-mini.tail1234.ts.net|7455", "100.101.102.103|7455", "fd7a:115c:a1e0::5|7455",
                      "192.168.1.5|7455", "mac.example.net|7470", "203.0.113.7|7455", "10.0.0.9|7455"],
            Order(addresses, 7455, null, Home).Select(c => c.Key));
        Assert.Equal("203.0.113.7|7455", Order(addresses, 7455, "203.0.113.7|7455", Home)[0].Key);
        // A Tailscale address saved as LAN is a VPN address all the same.
        Assert.Equal("100.64.0.1|7455", Order([new("192.168.9.9", null, "lan", ""), new("100.64.0.1", null, "lan", "")], 7455, null, Home)[0].Key);
    }

    [Fact]
    public void ThePlanDialsTheRowFirstThenTheSavedAddresses()
    {
        var mac = Saved(MacKey) with
        {
            Addresses = [new("100.101.102.103", null, "vpn", "Tailscale"), new("192.168.1.5", null, "lan", "Wi‑Fi")],
            RemotePort = 7455, LastWorked = "192.168.1.5|7455",
        };
        var plan = Plan([new DoorAddress("192.168.1.5", 50001), new DoorAddress("fe80::1%12", 50001)], mac, Home);
        Assert.Equal(["192.168.1.5|50001", "fe80::1%12|50001", "192.168.1.5|7455", "100.101.102.103|7455", "192.168.1.5|49870"],
            plan.Select(c => c.Key));
        Assert.Equal([true, true, false, false, false], plan.Select(c => c.Row));
        // Away: no row.
        Assert.Equal("192.168.1.5|7455", Plan([], mac, Home)[0].Key);
        // A record from before kind 18: the address the pairing reached.
        Assert.Equal(["192.168.1.5|49870"], Plan([], Saved(MacKey), Home).Select(c => c.Key));
    }

    [Fact]
    public void KindsOfHosts()
    {
        Assert.Equal("vpn", KindOfHost("100.100.1.1"));
        Assert.Equal("internet", KindOfHost("100.128.0.1"));
        Assert.Equal("vpn", KindOfHost("Mac.Tail1234.TS.NET"));
        Assert.Equal("lan", KindOfHost("172.20.0.1"));
        Assert.Equal("internet", KindOfHost("172.32.0.1"));
        Assert.Equal("lan", KindOfHost("mac.local"));
        Assert.Equal("lan", KindOfHost("fd00::1"));
        Assert.Equal("internet", KindOfHost("2001:db8::1"));
        Assert.Equal("internet", KindOfHost("mac.example.net"));
        Assert.Null(IPv4.Parse("1.2.3"));
        Assert.Null(IPv4.Parse("1.2.3.256"));
        Assert.Null(IPv4.Parse("1.2.3.+4"));
        Assert.True(IPv4.SameNetwork([10, 1, 2, 3], [10, 1, 9, 9], 16));
        Assert.False(IPv4.SameNetwork([10, 1, 2, 3], [10, 2, 9, 9], 16));
        Assert.True(IPv4.SameNetwork([192, 168, 1, 130], [192, 168, 1, 129], 25));
        Assert.False(IPv4.SameNetwork([192, 168, 1, 130], [192, 168, 1, 1], 25));
    }

    // ---- failures and their words ----

    private static readonly Candidate Ts = new("mac-mini.tail1234.ts.net", 7455, "vpn", "Tailscale");
    private static readonly Candidate Lan = new("192.168.1.5", 7455, "lan", "Wi‑Fi");
    private static readonly Candidate Wan = new("203.0.113.7", 7455, "internet", "Router");

    [Fact]
    public void EndsAndFailures()
    {
        Assert.Equal(End.WrongKey, EndOf(new SillTls.PinMismatchException(new byte[32], new byte[32])));
        Assert.Equal(End.Refused, EndOf(new SocketException((int)SocketError.ConnectionRefused)));
        Assert.Equal(End.NameNotFound, EndOf(new IOException("x", new SocketException((int)SocketError.HostNotFound))));
        Assert.Equal(End.Unreachable, EndOf(new SocketException((int)SocketError.HostUnreachable)));
        Assert.Equal(End.Timeout, EndOf(new OperationCanceledException()));
        Assert.Equal(End.NotSill, EndOf(new System.Security.Authentication.AuthenticationException("ALPN")));
        Assert.Equal(End.Refused, EndOf(new IOException("EOF during the handshake")));

        // Another key at a LAN address is a stranger there; at Tailscale's, the wrong Mac.
        Assert.Null(Classify(End.WrongKey, Lan));
        Assert.Equal(Failure.WrongMac, Classify(End.WrongKey, Ts));
        Assert.Equal(Failure.VpnOff, Classify(End.NameNotFound, Ts));
        Assert.Equal(Failure.NameNotFound, Classify(End.NameNotFound, Wan with { Host = "mac.example.net" }));
        Assert.Equal(Failure.NoAnswer, Classify(End.Timeout, Ts));
        Assert.Equal(Failure.Revoked, Classify(GoodbyePolicy.Removed));
        Assert.Equal(Failure.Refused, Classify("internetOff"));
        Assert.Equal(Failure.WrongMac, Worst([Failure.NoAnswer, Failure.WrongMac, Failure.Refused]));
        Assert.Equal(Failure.Refused, Worst([Failure.NoAnswer, Failure.Refused, Failure.NotSill]));
        Assert.Null(Worst([]));
    }

    [Fact]
    public void TheWordsAreTheIPadsWithClick()
    {
        Assert.Equal("Tailscale looks off on this PC. Turn it on, then click Mac mini.",
            RemoteCopy.DialFailure(Failure.VpnOff, "Mac mini", Ts, "Tailscale"));
        Assert.Equal("This PC can’t look up mac-mini.tail1234.ts.net. Is Tailscale on?",
            RemoteCopy.DialFailure(Failure.NameNotFound, "Mac mini", Ts, null));
        Assert.Equal("Mac mini didn’t answer. It may be asleep, or Tailscale may be off on the Mac.",
            RemoteCopy.DialFailure(Failure.NoAnswer, "Mac mini", Ts, "Tailscale"));
        Assert.Equal("Mac mini didn’t answer at 203.0.113.7. If your home’s internet address changed, connect at home once to update it, or add an address name on the Mac.",
            RemoteCopy.DialFailure(Failure.NoAnswer, "Mac mini", Wan, null));
        Assert.Equal("Mac mini didn’t answer. It may be asleep.", RemoteCopy.DialFailure(Failure.NoAnswer, "Mac mini", Lan, null));
        Assert.Equal("This isn’t the Mac mini this PC paired with. If Sill was set up again on it, forget it here and pair again.",
            RemoteCopy.DialFailure(Failure.WrongMac, "Mac mini", Ts, null));
        Assert.Equal("Something answered at [fd7a::1]:7460, but it isn’t Sill. Your home’s internet address may have changed.",
            RemoteCopy.DialFailure(Failure.NotSill, "Mac mini", new Candidate("fd7a::1", 7460, "vpn", ""), null));
        Assert.Equal("Tailscale", RemoteCopy.VpnName(Saved(MacKey) with { Addresses = [new("100.101.102.103", null, "vpn", "VPN (utun4)")] }));
        Assert.Equal("Home WireGuard", RemoteCopy.VpnLabel(new Candidate("10.8.0.6", 7455, "vpn", "Home WireGuard")));
        Assert.Null(RemoteCopy.VpnName(Saved(MacKey)));
    }

    // ---- happy eyeballs ----

    private sealed class Conn(string at) { public string At = at; public bool Discarded; }

    private static Task<HappyEyeballs.Result<Conn>> Race(IReadOnlyList<Candidate> cands, Func<Candidate, CancellationToken, Task<Conn>> connect,
        List<Conn>? discarded = null, double stagger = 0.15, double whole = 5) =>
        HappyEyeballs.RaceAsync(cands, connect, c => { c.Discarded = true; discarded?.Add(c); return Task.CompletedTask; },
            TimeSpan.FromSeconds(stagger), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(whole), CancellationToken.None);

    private static Candidate C(string host) => new(host, 7455, "vpn", "");

    [Fact]
    public async Task TheFirstToConnectWinsAndTheOthersAreCancelled()
    {
        var started = new List<(string, double)>();
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var cancelled = new List<string>();
        // a never answers, b answers 50 ms after it starts, c would answer later.
        var r = await Race([C("a"), C("b"), C("c")], async (c, ct) =>
        {
            lock (started) started.Add((c.Host, clock.Elapsed.TotalSeconds));
            try { await Task.Delay(c.Host switch { "a" => 10_000, "b" => 50, _ => 1_000 }, ct); }
            catch (OperationCanceledException) { lock (cancelled) cancelled.Add(c.Host); throw; }
            return new Conn(c.Host);
        });
        Assert.Equal("b", r.Winner!.At);
        Assert.Equal("b", r.Won!.Host);
        Assert.Equal(["a", "b"], started.Select(s => s.Item1));
        Assert.InRange(started[1].Item2, 0.12, 1.0);   // a stagger after the first
        await Task.Delay(100);
        Assert.Contains("a", cancelled);
    }

    [Fact]
    public async Task AFailureStartsTheNextAtOnceAndAllFailingReportsEach()
    {
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var started = new List<double>();
        var r = await Race([C("a"), C("b"), C("c")], (c, ct) =>
        {
            lock (started) started.Add(clock.Elapsed.TotalSeconds);
            return Task.FromException<Conn>(new SocketException((int)SocketError.ConnectionRefused));
        }, stagger: 2);
        Assert.Null(r.Winner);
        Assert.Equal(["a", "b", "c"], r.Failures.Select(f => f.Candidate.Host));
        Assert.True(started[^1] < 1, "each next one started at once");
        Assert.Empty((await Race([], (_, _) => Task.FromResult(new Conn("x")))).Failures);
    }

    [Fact]
    public async Task OneThatConnectsAfterTheWinnerIsDiscarded()
    {
        var discarded = new List<Conn>();
        // b ignores its cancellation and connects anyway, after a has won.
        var r = await Race([C("a"), C("b")], async (c, _) =>
        {
            await Task.Delay(c.Host == "a" ? 300 : 350);
            return new Conn(c.Host);
        }, discarded, stagger: 0.05);
        Assert.Equal("a", r.Winner!.At);
        await Task.Delay(300);
        Assert.Equal("b", Assert.Single(discarded).At);
        Assert.False(r.Winner.Discarded);
    }

    [Fact]
    public async Task TheWholeDialTimesOut()
    {
        var r = await Race([C("a"), C("b")], async (_, ct) => { await Task.Delay(10_000, ct); return new Conn("x"); }, stagger: 0.05, whole: 0.3);
        Assert.Null(r.Winner);
        Assert.Equal(2, r.Failures.Count);
        Assert.All(r.Failures, f => Assert.Equal(End.Timeout, EndOf(f.Error)));
    }

    // ---- the reconnect ----

    [Fact]
    public void TheBackOffIsTheIPads()
    {
        Assert.Equal((true, (double?)null), ReconnectPolicy.Redial(0, null, 0));
        Assert.Equal((false, (double?)105), ReconnectPolicy.Redial(1, 100, 101));
        Assert.True(ReconnectPolicy.Redial(1, 100, 105).Dial);
        Assert.Equal(110, ReconnectPolicy.Redial(2, 100, 100).RecheckAt);
        Assert.Equal(120, ReconnectPolicy.Redial(3, 100, 100).RecheckAt);
        Assert.Equal(130, ReconnectPolicy.Redial(4, 100, 100).RecheckAt);
        Assert.Equal(130, ReconnectPolicy.Redial(11, 100, 100).RecheckAt);
        Assert.Equal((false, (double?)null), ReconnectPolicy.Redial(12, 100, 1000));
        // Twelve dials at the rule's times: 0, 5, 15, 35, then 30 s apart.
        double t = 0, last = 0;
        var at = new List<double>();
        for (int failed = 0; failed < 20; failed++)
        {
            var (dial, recheck) = ReconnectPolicy.Redial(failed, failed == 0 ? null : last, t);
            if (!dial) { if (recheck is null) break; t = recheck.Value; failed--; continue; }
            at.Add(t); last = t;
        }
        Assert.Equal([0, 5, 15, 35, 65, 95, 125, 155, 185, 215, 245, 275], at);

        Assert.Equal("Reconnecting to Mac mini…", ReconnectPolicy.Line("Mac mini", 2));
        Assert.Equal("Mac mini isn’t answering. It may be asleep. Sill keeps trying, or click it to try now.", ReconnectPolicy.Line("Mac mini", 3));
        Assert.Equal("Stopped trying to reach Mac mini. Click it to try again.", ReconnectPolicy.Line("Mac mini", 12));
    }

    [Fact]
    public void GoodbyesSayWhetherToReconnect()
    {
        Assert.True(GoodbyePolicy.For(null, "Mac mini").Reconnect);
        Assert.Equal("Mac mini disconnected. Sill will reconnect when it can reach it.", GoodbyePolicy.For(null, "Mac mini").Text);
        Assert.True(GoodbyePolicy.For(new Goodbye("quit"), "Mac mini").Reconnect);
        Assert.Equal("Mac mini removed this PC. To use it again, pair it again.", GoodbyePolicy.For(new Goodbye("removed"), "Mac mini").Text);
        Assert.False(GoodbyePolicy.For(new Goodbye("removed"), "Mac mini").Reconnect);
        Assert.False(GoodbyePolicy.For(new Goodbye("pairingRequired"), "Mac mini").Reconnect);
        var update = GoodbyePolicy.For(new Goodbye("update", "Update Sill on your PC to keep using Mac mini.", "1.2", false), "Mac mini");
        Assert.Equal(("Update Sill on your PC to keep using Mac mini.", false, true), (update.Text, update.Reconnect, update.IsNotice));
        Assert.Equal("Update Sill on this PC to keep using Mac mini. It needs version 1.2 or later.",
            GoodbyePolicy.For(new Goodbye("update", null, "1.2"), "Mac mini").Text);
        // A reason this build doesn't know: the Mac's words, a reconnect only when it asks.
        Assert.False(GoodbyePolicy.For(new Goodbye("later"), "Mac mini").Reconnect);
        Assert.Equal("Mac mini closed the connection. Click it to try again.", GoodbyePolicy.For(new Goodbye("later"), "Mac mini").Text);
        Assert.True(GoodbyePolicy.For(new Goodbye("later", "Back soon.", null, true), "Mac mini").Reconnect);
        Assert.Equal("Back soon.", GoodbyePolicy.For(new Goodbye("later", "Back\nsoon.", null, true), "Mac mini").Text);
    }

    [Fact]
    public void RemoteRowsWaitForTheNetworkAndSkipTheListed()
    {
        var a = Saved(MacKey);
        var b = Saved(OtherKey) with { Name = "Studio", PairedAt = DateTimeOffset.UnixEpoch.AddDays(1) };
        var c = Saved(ECDsa.Create(ECCurve.NamedCurves.nistP256)) with { Name = "Old", NewKey = true };
        var listed = new MacRow(new FoundService("_sill._tcp", "Mac mini", "mac.local.", 49870, [], new Dictionary<string, string?>(), MacLink.WiFi),
            MacRow.Kind.Paired, a.MacId, true);
        Assert.Empty(RemoteRows.Build([a, b, c], [listed], 2.9));
        var rows = RemoteRows.Build([b, a, c], [listed], 3);
        var row = Assert.Single(rows);
        Assert.Equal((MacRow.Kind.Remote, b.MacId, "Studio", "Remote", "remote:" + b.MacId), (row.State, row.MacId, row.Name, row.Word, row.Key));
        Assert.Empty(row.DialTargets());
        Assert.Equal([a.MacId, b.MacId], RemoteRows.Build([b, a], [], 10).Select(r => r.MacId));
    }
}
