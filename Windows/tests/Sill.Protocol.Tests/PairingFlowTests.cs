using System.Security.Cryptography;

namespace Sill.Protocol.Tests;

public class PairingFlowTests
{
    private const string Code = "729000986820";   // Damm-valid
    private static readonly byte[] MacKey = SHA256.HashData("the mac"u8), NewMacKey = SHA256.HashData("set up again"u8);
    private static readonly DoorAddress Wifi = new("192.168.1.5", 49880), Link6 = new("fe80::1%12", 49880);

    private sealed class MemoryStore : ISavedMacs
    {
        public List<SavedMac> Macs = [];
        public IReadOnlyList<SavedMac> Load() => Macs.ToList();
        public void Save(IReadOnlyList<SavedMac> macs) => Macs = macs.ToList();
    }

    private sealed class FakeDoor : IPairingDoor
    {
        public Func<DoorAddress, PairResult?> Ask = _ => new PairResult(false, Reason: PairResult.Shown);
        public Func<DoorAddress, string, byte[]?, PairingClient.Outcome> Code = (_, _, _) => Paired(MacKey);
        public Func<DoorAddress, PairLink, PairingClient.Outcome> Link = (_, l) => Paired(l.Fingerprint);
        public byte[] Presented = MacKey;
        public readonly List<string> Calls = [];

        public Task<(PairResult? Result, byte[] MacFingerprint)> AskAsync(DoorAddress at, CancellationToken ct)
        {
            Calls.Add($"ask {at}");
            return Task.FromResult((Ask(at), Presented));
        }

        public Task<PairingClient.Outcome> CodeAsync(DoorAddress at, string code, byte[]? pin, CancellationToken ct)
        {
            Calls.Add($"code {at} {code} pin={(pin is null ? "none" : Base64Url.Encode(pin)[..6])}");
            return Task.FromResult(Code(at, code, pin));
        }

        public Task<PairingClient.Outcome> LinkAsync(DoorAddress at, PairLink link, CancellationToken ct)
        {
            Calls.Add($"link {at}");
            return Task.FromResult(Link(at, link));
        }

        public Task CancelAskAsync(DoorAddress at, byte[] pin, CancellationToken ct)
        {
            Calls.Add($"cancel {at} pin={Base64Url.Encode(pin)[..6]}");
            return Task.CompletedTask;
        }
    }

    private static PairingClient.Outcome Paired(byte[] key, string name = "Mac mini") =>
        new(PairingExchange.Verdict.Paired,
            new PairResult(true, "proof", MacId.Make(key), name, Base64Url.Encode(new byte[32]), Method: "code"), key);

    private static PairingClient.Outcome Refused(string reason, int? left = null) =>
        new(PairingExchange.Verdict.Refused, new PairResult(false, Reason: reason, TriesLeft: left), MacKey);

    private static string Pin(byte[] key) => Base64Url.Encode(key)[..6];

    [Fact]
    public async Task AskShownThenTheCodePinnedToTheAskedKeyPairsAndSaves()
    {
        var door = new FakeDoor();
        var store = new MemoryStore();
        var flow = PairingFlow.Home(door, store, "Mac mini", [Wifi], bonjourName: "Mac mini");
        await flow.AskAsync();
        Assert.Equal(PairingFlow.Steps.Code, flow.Step);
        Assert.Equal("Mac mini is showing a code.", flow.Line);
        await flow.SubmitCodeAsync("7290 0098 6820");
        Assert.Equal(PairingFlow.Steps.Paired, flow.Step);
        Assert.Equal("Paired with Mac mini.", flow.Line);
        Assert.Equal([$"ask {Wifi}", $"code {Wifi} {Code} pin={Pin(MacKey)}"], door.Calls);
        var saved = Assert.Single(store.Macs);
        Assert.Equal((MacId.Make(MacKey), "Mac mini", "192.168.1.5", 49880, "Mac mini"), (saved.MacId, saved.Name, saved.Host, saved.Port, saved.BonjourName));
        Assert.Equal(MacKey, saved.Pin);
        Assert.Equal(Wifi, flow.Reached);
    }

    [Fact]
    public async Task TheAskTriesEachAddressInTurn()
    {
        var door = new FakeDoor { Ask = at => at == Wifi ? throw new IOException("refused") : new PairResult(false, Reason: PairResult.Shown) };
        var flow = PairingFlow.Home(door, new MemoryStore(), "Mac mini", [Wifi, Link6]);
        await flow.AskAsync();
        Assert.Equal(PairingFlow.Steps.Code, flow.Step);
        await flow.SubmitCodeAsync(Code);
        Assert.Equal($"code {Link6} {Code} pin={Pin(MacKey)}", door.Calls[^1]);   // where it answered
    }

    [Theory]
    [InlineData(PairResult.OpenOnMac, "Mac mini didn’t show a code. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click Mac mini again.")]
    [InlineData(PairResult.Locked, "Unlock Mac mini, then click it again.")]
    [InlineData(PairResult.Closed, "Mac mini didn’t show a code. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click Mac mini again.")]
    public async Task AsksThatShowNoCodeEndWithTheIpadsWords(string reason, string words)
    {
        var flow = PairingFlow.Home(new FakeDoor { Ask = _ => new PairResult(false, Reason: reason) }, new MemoryStore(), "Mac mini", [Wifi]);
        await flow.AskAsync();
        Assert.Equal((PairingFlow.Steps.Ended, words), (flow.Step, flow.Line));
    }

    [Fact]
    public async Task NothingAnsweringTheAskSaysSo()
    {
        var flow = PairingFlow.Home(new FakeDoor { Ask = _ => throw new IOException("gone") }, new MemoryStore(), "Mac mini", [Wifi, Link6]);
        await flow.AskAsync();
        Assert.Equal((PairingFlow.Steps.Ended, "Mac mini didn’t answer. Check that Sill is open on it, then click it again."), (flow.Step, flow.Line));
        var silent = PairingFlow.Home(new FakeDoor { Ask = _ => null }, new MemoryStore(), "Mac mini", [Wifi]);
        await silent.AskAsync();
        Assert.Equal(PairingFlow.Steps.Ended, silent.Step);
    }

    [Fact]
    public async Task AnUnknownRefusalShowsTheMacsOwnWords()
    {
        var flow = PairingFlow.Home(new FakeDoor { Ask = _ => new PairResult(false, Reason: "later", Message: "Not‮ now.") }, new MemoryStore(), "Mac mini", [Wifi]);
        await flow.AskAsync();
        Assert.Equal("Not now.", flow.Line);
    }

    [Fact]
    public async Task BusyIsAskedAgainOnceSilently()
    {
        int asks = 0;
        var waits = new List<TimeSpan>();
        var door = new FakeDoor { Ask = _ => ++asks == 1 ? new PairResult(false, Reason: PairResult.Busy, RetryAfter: 30) : new PairResult(false, Reason: PairResult.Shown) };
        var flow = PairingFlow.Home(door, new MemoryStore(), "Mac mini", [Wifi], delay: (t, _) => { waits.Add(t); return Task.CompletedTask; });
        await flow.AskAsync();
        Assert.Equal((PairingFlow.Steps.Code, 2), (flow.Step, asks));
        Assert.Equal([TimeSpan.FromSeconds(10)], waits);   // retryAfter clamped to 10 s

        var always = PairingFlow.Home(new FakeDoor { Ask = _ => new PairResult(false, Reason: PairResult.Busy) }, new MemoryStore(), "Mac mini", [Wifi],
            delay: (_, _) => Task.CompletedTask);
        await always.AskAsync();
        Assert.Equal(PairingFlow.Steps.Ended, always.Step);
        Assert.StartsWith("Mac mini didn’t show a code.", always.Line);
    }

    [Fact]
    public async Task AnOkToAnAskIsNeverTaken()
    {
        var door = new FakeDoor { Ask = _ => new PairResult(true, MacId: MacId.Make(MacKey), RecognitionKey: Base64Url.Encode(new byte[32]), Method: "cable") };
        var store = new MemoryStore();
        var flow = PairingFlow.Home(door, store, "Mac mini", [Wifi]);
        await flow.AskAsync();
        Assert.Equal(PairingFlow.Steps.Ended, flow.Step);
        Assert.Empty(store.Macs);
    }

    [Fact]
    public async Task TyposNeverReachTheMac()
    {
        var door = new FakeDoor();
        var flow = PairingFlow.Home(door, new MemoryStore(), "Mac mini", [Wifi]);
        await flow.AskAsync();
        await flow.SubmitCodeAsync("7290 0098 6821");
        Assert.Equal((PairingFlow.Steps.Code, PairingCopy.CodeTypo), (flow.Step, flow.Problem));
        await flow.SubmitCodeAsync("7290 0098");
        Assert.Equal(PairingCopy.CodeLength, flow.Problem);
        Assert.DoesNotContain(door.Calls, c => c.StartsWith("code"));
    }

    [Theory]
    [InlineData(PairResult.WrongCode, 4, "That code didn’t work. Check the code on your Mac. 4 tries left.")]
    [InlineData(PairResult.WrongCode, 1, "That code didn’t work. Check the code on your Mac. 1 try left.")]
    [InlineData(PairResult.Expired, null, "That code expired. Click Mac mini for a new one.")]
    [InlineData(PairResult.Stopped, null, "Mac mini stopped pairing after too many wrong codes. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click Mac mini again.")]
    [InlineData(PairResult.Closed, null, "That code no longer works. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click Mac mini again.")]
    [InlineData(PairResult.Busy, null, "That code no longer works. On the Mac, choose Pair iPhone or iPad… in the Sill menu, then click Mac mini again.")]
    public async Task ARefusedCodeKeepsTheCardWithItsWords(string reason, int? left, string words)
    {
        var store = new MemoryStore();
        var flow = PairingFlow.Home(new FakeDoor { Code = (_, _, _) => Refused(reason, left) }, store, "Mac mini", [Wifi]);
        await flow.AskAsync();
        await flow.SubmitCodeAsync(Code);
        Assert.Equal((PairingFlow.Steps.Code, words), (flow.Step, flow.Problem));
        Assert.Empty(store.Macs);
    }

    [Fact]
    public async Task AWrongCodeCanBeTypedAgain()
    {
        int tries = 0;
        var flow = PairingFlow.Home(new FakeDoor { Code = (_, _, _) => ++tries == 1 ? Refused(PairResult.WrongCode, 4) : Paired(MacKey) },
            new MemoryStore(), "Mac mini", [Wifi]);
        await flow.AskAsync();
        await flow.SubmitCodeAsync(Code);
        await flow.SubmitCodeAsync(Code);
        Assert.Equal(PairingFlow.Steps.Paired, flow.Step);
    }

    [Fact]
    public async Task AnUnprovenYesSavesNothing()
    {
        var store = new MemoryStore();
        var flow = PairingFlow.Home(new FakeDoor { Code = (_, _, _) => new(PairingExchange.Verdict.NoProof, new PairResult(true), MacKey) },
            store, "Mac mini", [Wifi]);
        await flow.AskAsync();
        await flow.SubmitCodeAsync(Code);
        Assert.Equal(PairingCopy.ProofFailed("Mac mini"), flow.Problem);
        Assert.Empty(store.Macs);
    }

    [Fact]
    public async Task CancelWithdrawsTheCodeTheAskPutUp()
    {
        var door = new FakeDoor();
        var flow = PairingFlow.Home(door, new MemoryStore(), "Mac mini", [Wifi]);
        await flow.AskAsync();
        flow.Cancel();
        await flow.Withdrawal!;
        Assert.Equal((PairingFlow.Steps.Ended, (string?)null), (flow.Step, flow.Line));
        Assert.Equal($"cancel {Wifi} pin={Pin(MacKey)}", door.Calls[^1]);
        // Nothing more after: a second Cancel, a late Pair.
        flow.Cancel();
        await flow.SubmitCodeAsync(Code);
        Assert.Equal(2, door.Calls.Count);
    }

    [Fact]
    public async Task ACancelBeforeAnyCodeWithdrawsNothing()
    {
        var door = new FakeDoor { Ask = _ => new PairResult(false, Reason: PairResult.Locked) };
        var flow = PairingFlow.Home(door, new MemoryStore(), "Mac mini", [Wifi]);
        flow.Cancel();
        Assert.Null(flow.Withdrawal);
        var paired = PairingFlow.Home(new FakeDoor(), new MemoryStore(), "Mac mini", [Wifi]);
        await paired.AskAsync();
        await paired.SubmitCodeAsync(Code);
        paired.Cancel();
        Assert.Null(paired.Withdrawal);   // the pairing closed the window
    }

    [Fact]
    public async Task ARowOfAMacSetUpAgainReplacesItsOldRecord()
    {
        var store = new MemoryStore();
        var old = new SavedMac(Base64Url.Encode(MacKey), MacId.Make(MacKey), "Mac mini", Base64Url.Encode(new byte[32]), "10.0.0.2", 49000,
                               DateTimeOffset.UnixEpoch, NewKey: true);
        store.Macs.Add(old);
        var door = new FakeDoor { Presented = NewMacKey, Code = (_, _, _) => Paired(NewMacKey) };
        var flow = PairingFlow.Home(door, store, "Mac mini", [Wifi], replaces: old.MacId);
        await flow.AskAsync();
        await flow.SubmitCodeAsync(Code);
        var only = Assert.Single(store.Macs);
        Assert.Equal(MacId.Make(NewMacKey), only.MacId);
        Assert.Null(only.NewKey);
        Assert.Contains($"pin={Pin(NewMacKey)}", door.Calls[^1]);
    }

    [Fact]
    public async Task AddAMacByLinkIsPinnedToItsKeyAtItsOwnAddresses()
    {
        var link = new PairLink(MacId.Make(MacKey), MacKey, new byte[16], "Studio", 7455, ["100.101.102.103", "studio.tail.ts.net"]);
        string url = $"sill://pair?v=1&m={link.MacId}&k={Base64Url.Encode(MacKey)}&s={Base64Url.Encode(new byte[16])}&n=Studio&p=7455&a=100.101.102.103&a=studio.tail.ts.net";
        var door = new FakeDoor
        {
            Link = (at, l) => at.Host == "100.101.102.103" ? throw new IOException("unreachable") : Paired(l.Fingerprint, "Studio"),
        };
        var store = new MemoryStore();
        var flow = PairingFlow.AddMac(door, store);
        Assert.Equal(PairingFlow.Steps.Code, flow.Step);
        await flow.SubmitAddAsync(url, "");
        Assert.Equal(PairingFlow.Steps.Paired, flow.Step);
        Assert.Equal(["link 100.101.102.103:7455", "link studio.tail.ts.net:7455"], door.Calls);
        Assert.Equal(("Studio", "studio.tail.ts.net", 7455), (store.Macs[0].Name, store.Macs[0].Host, store.Macs[0].Port));
    }

    [Fact]
    public async Task ALinkWhoseAddressHoldsAnotherKeySaysSo()
    {
        string url = $"sill://pair?v=1&m={MacId.Make(MacKey)}&k={Base64Url.Encode(MacKey)}&s={Base64Url.Encode(new byte[16])}&n=Studio&p=7455&a=10.0.0.9";
        var door = new FakeDoor { Link = (_, _) => throw new SillTls.PinMismatchException(NewMacKey, MacKey) };
        var flow = PairingFlow.AddMac(door, new MemoryStore());
        await flow.SubmitAddAsync(url, "");
        Assert.Equal((PairingFlow.Steps.Code, "The Mac at 10.0.0.9:7455 isn’t the one this link is from."), (flow.Step, flow.Problem));
        await flow.SubmitAddAsync("sill://pair?v=2", "");
        Assert.Equal(PairingCopy.NotALink, flow.Problem);
    }

    [Fact]
    public async Task AddAMacByAddressAndCodeTakesAnyKey()
    {
        var door = new FakeDoor { Code = (_, _, pin) => pin is null ? Paired(MacKey, "Studio") : throw new InvalidOperationException() };
        var store = new MemoryStore();
        var flow = PairingFlow.AddMac(door, store);
        await flow.SubmitAddAsync("studio.tail.ts.net", "7290 0098 6820");
        Assert.Equal(PairingFlow.Steps.Paired, flow.Step);
        Assert.Equal($"code studio.tail.ts.net:7455 {Code} pin=none", door.Calls[0]);
        Assert.Equal("Studio", store.Macs[0].Name);
    }

    [Fact]
    public async Task AddAMacRefusalsUseTheRemoteWords()
    {
        var flow = PairingFlow.AddMac(new FakeDoor { Code = (_, _, _) => Refused(PairResult.WrongCode, 3) }, new MemoryStore());
        await flow.SubmitAddAsync("10.0.0.9:47455", Code);
        Assert.Equal("That code didn’t work. Check the code on your Mac. 3 tries left.", flow.Problem);
        var gone = PairingFlow.AddMac(new FakeDoor { Code = (_, _, _) => throw new IOException("x", new System.Net.Sockets.SocketException(10061)) }, new MemoryStore());
        await gone.SubmitAddAsync("10.0.0.9", Code);
        Assert.Equal("Nothing answered at 10.0.0.9:7455. Check the address, and that Sill is open on your Mac.", gone.Problem);
        var bad = PairingFlow.AddMac(new FakeDoor(), new MemoryStore());
        await bad.SubmitAddAsync("fe80::1%12", Code);
        Assert.Equal(PairingCopy.Zone, bad.Problem);
    }

    [Theory]
    [InlineData("72900", "7290 0")]
    [InlineData("7290-0098-6820-55", "7290 0098 6820")]
    [InlineData("ab 72 9x0", "7290")]
    [InlineData("", "")]
    public void TheCodeFieldGroupsDigits(string typed, string shown) => Assert.Equal(shown, CodeEntry.Grouped(typed));

    [Fact]
    public void TheCheckDigitIsJudgedOnceAllTwelveAreTyped()
    {
        Assert.Null(CodeEntry.WhileTyping("7290 0098 682"));
        Assert.Null(CodeEntry.WhileTyping("7290 0098 6820"));
        Assert.Equal(PairingCopy.CodeTypo, CodeEntry.WhileTyping("7290 0098 6821"));
        Assert.True(CodeEntry.Ready("7290 0098 6820"));
        Assert.False(CodeEntry.Ready("7290 0098 6821"));
    }

    [Theory]
    [InlineData("100.101.102.103", "100.101.102.103", 7455)]
    [InlineData(" mac.example.net:47455 ", "mac.example.net", 47455)]
    [InlineData("[fd7a:115c:a1e0::1]:7455", "fd7a:115c:a1e0::1", 7455)]
    [InlineData("fd7a:115c:a1e0::1", "fd7a:115c:a1e0::1", 7455)]
    [InlineData("127.0.0.1:47455", "127.0.0.1", 47455)]
    public void AddressesParse(string text, string host, int port)
    {
        Assert.Null(AddMacInput.Address(text, out string h, out int p));
        Assert.Equal((host, port), (h, p));
    }

    [Theory]
    [InlineData("")]
    [InlineData("mac example")]
    [InlineData("mac:0")]
    [InlineData("mac:70000")]
    [InlineData("http://mac")]
    [InlineData("[zz::1]:7455")]
    [InlineData("user@mac")]
    public void NonAddressesDont(string text) => Assert.Equal(PairingCopy.Address, AddMacInput.Address(text, out _, out _));
}
