namespace Sill.Protocol.Tests;

public class DiscoveryTests
{
    private static readonly byte[] Rk = Enumerable.Repeat((byte)0x11, 32).ToArray();
    private static readonly byte[] OtherRk = Enumerable.Repeat((byte)0x77, 32).ToArray();

    private static FoundService Service(string name, params (string Key, string? Value)[] txt) =>
        new("_sill._tcp", name, "mac.local.", 49870, ["192.168.100.185", "fe80::1%12"],
            txt.ToDictionary(t => t.Key, t => t.Value), MacLink.WiFi);

    private static readonly KnownMac Saved = new("A3C5HR4RBV67YR21", "Mac mini", Rk, null);

    [Fact]
    public void TheTagVectorIsSwifts()
    {
        // Tests/checks/protocol: key 0x11×32, p a1a2a3a4a5a6.
        Assert.Equal("oaKjpKWmL4V47Ctm", RecognitionTag.Make(Rk, Convert.FromHexString("a1a2a3a4a5a6")));
        Assert.True(RecognitionTag.Matches("oaKjpKWmL4V47Ctm", Rk));
        Assert.False(RecognitionTag.Matches("oaKjpKWmL4V47Ctm", OtherRk));
    }

    [Fact]
    public void FreshTagsDifferAndMatch()
    {
        var tags = Enumerable.Range(0, 50).Select(_ => RecognitionTag.Make(Rk)).ToList();
        Assert.Equal(50, tags.Distinct().Count());
        Assert.All(tags, t => { Assert.Equal(16, t.Length); Assert.True(RecognitionTag.Matches(t, Rk)); });
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("oaKjpKWmL4V47Ct")]
    [InlineData("oaKjpKWmL4V47Ctn")]
    [InlineData("oaKjpKWmL4V47Ctm=")]
    public void MalformedTagsNeverMatch(string? tag) => Assert.False(RecognitionTag.Matches(tag, Rk));

    [Fact]
    public void TheDoorFromP()
    {
        Assert.Equal(HomeDoorTxt.Door.Plain, HomeDoorTxt.Read(new Dictionary<string, string?>()));
        Assert.Equal(HomeDoorTxt.Door.PairingRequired, HomeDoorTxt.Read(new Dictionary<string, string?> { ["p"] = "1" }));
        Assert.Equal(HomeDoorTxt.Door.Open, HomeDoorTxt.Read(new Dictionary<string, string?> { ["p"] = "0" }));
        Assert.Equal(HomeDoorTxt.Door.Open, HomeDoorTxt.Read(new Dictionary<string, string?> { ["P"] = "0" }));
        Assert.Equal(HomeDoorTxt.Door.PairingRequired, HomeDoorTxt.Read(new Dictionary<string, string?> { ["p"] = null }));
        Assert.Equal(HomeDoorTxt.Door.PairingRequired, HomeDoorTxt.Read(new Dictionary<string, string?> { ["p"] = "yes" }));
    }

    [Fact]
    public void ASavedMacIsKnownByItsTagNotItsName()
    {
        var row = ConnectRows.Row(Service("Some other name", ("p", "1"), ("r", RecognitionTag.Make(Rk))), [Saved]);
        Assert.Equal(MacRow.Kind.Paired, row.State);
        Assert.Equal("A3C5HR4RBV67YR21", row.MacId);
        Assert.True(row.TagNamed);
        Assert.Equal("Wi‑Fi", row.Word);
    }

    [Fact]
    public void AnotherTagUnderTheSavedNameIsNotPaired()
    {
        // A Mac set up again, or a look-alike that took the name: its tag names no saved Mac.
        var row = ConnectRows.Row(Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(OtherRk))), [Saved]);
        Assert.Equal(MacRow.Kind.NotPaired, row.State);
        Assert.Equal("Not paired", row.Word);
        Assert.Null(row.MacId);
    }

    [Fact]
    public void ARowWithNoTagAtAllTakesTheSavedNameAlone()
    {
        var row = ConnectRows.Row(Service("Mac mini", ("p", "1")), [Saved]);
        Assert.Equal(MacRow.Kind.Paired, row.State);
        Assert.False(row.TagNamed);
        Assert.Equal(MacRow.Kind.NotPaired, ConnectRows.Row(Service("MacBook Pro", ("p", "1")), [Saved]).State);
        // The Bonjour name it was reached under counts over the Mac's own name.
        Assert.Equal(MacRow.Kind.Paired,
            ConnectRows.Row(Service("Mac mini (2)", ("p", "1")), [Saved with { BonjourName = "Mac mini (2)" }]).State);
    }

    [Fact]
    public void ASavedRecordWithoutAKeyIsNeverMatchedByTag()
    {
        var row = ConnectRows.Row(Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(Rk))), [Saved with { RecognitionKey = null }]);
        Assert.Equal(MacRow.Kind.NotPaired, row.State);
    }

    [Fact]
    public void AnOpenDoorUnsavedReadsNotPaired()
    {
        var row = ConnectRows.Row(Service("Studio", ("p", "0"), ("r", RecognitionTag.Make(OtherRk))), [Saved]);
        Assert.Equal(MacRow.Kind.OpenDoor, row.State);
        Assert.Equal("Not paired", row.Word);
    }

    [Fact]
    public void NoPIsUpdateSillEvenForTheSavedMac()
    {
        var row = ConnectRows.Row(Service("Mac mini", ("r", RecognitionTag.Make(Rk))), [Saved]);
        Assert.Equal(MacRow.Kind.UpdateSill, row.State);
        Assert.Equal("Update Sill", row.Word);
        Assert.Equal("Mac mini runs an older Sill. Update Sill on the Mac to connect.", ConnectRows.UpdateSillStatus("Mac mini"));
    }

    [Fact]
    public void ThePairedMacsWordFollowsTheLink()
    {
        var tagged = Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(Rk)));
        Assert.Equal("Wired", ConnectRows.Row(tagged with { Link = MacLink.Wired }, [Saved]).Word);
        Assert.Null(ConnectRows.Row(tagged with { Link = null }, [Saved]).Word);
    }

    [Fact]
    public void PairedRowsComeFirstThenByName()
    {
        var rows = ConnectRows.Build([
            Service("zeta", ("p", "1")),
            Service("Alpha", ("p", "1")),
            Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(Rk))),
        ], [Saved]);
        Assert.Equal(["Mac mini", "Alpha", "zeta"], rows.Select(r => r.Name));
    }

    [Fact]
    public void DialTargetsPutIPv6InBrackets()
    {
        var row = ConnectRows.Row(Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(Rk))), [Saved]);
        Assert.Equal(["192.168.100.185:49870", "[fe80::1%12]:49870"], row.DialTargets());
        Assert.Equal(["mac.local:49870"], (row with { Service = row.Service with { Addresses = [] } }).DialTargets());
    }

    [Theory]
    [InlineData("Mac mini._sill._tcp.local", "Mac mini")]
    [InlineData("Mac mini._sill._tcp.local.", "Mac mini")]
    [InlineData(@"Mac\.mini._sill._tcp.local", "Mac.mini")]
    [InlineData(@"Jericho\226\128\153s Mac mini._sill._tcp.local", "Jericho’s Mac mini")]
    [InlineData(@"back\\slash._sill._tcp.local", @"back\slash")]
    [InlineData("Sill test 123._silltest._tcp.local", null)]
    public void InstanceNames(string full, string? expected) => Assert.Equal(expected, DnsSdName.Instance(full, "_sill._tcp"));

    [Fact]
    public void InstanceNamesOfAnotherType() =>
        Assert.Equal("Sill test 123", DnsSdName.Instance("Sill test 123._silltest._tcp.local", "_silltest._tcp"));

    [Fact]
    public void ASavedMacWithANewKeyPairsAgainFromItsRows()
    {
        // By its tag, or (no tag) by its name: "Not paired", and the pairing replaces the record.
        var marked = Saved with { NewKey = true };
        var tagged = ConnectRows.Row(Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(Rk))), [marked]);
        Assert.Equal((MacRow.Kind.NotPaired, "Not paired", Saved.MacId), (tagged.State, tagged.Word, tagged.Replaces));
        var byName = ConnectRows.Row(Service("Mac mini", ("p", "1")), [marked]);
        Assert.Equal((MacRow.Kind.NotPaired, Saved.MacId), (byName.State, byName.Replaces));
        Assert.Null(ConnectRows.Row(Service("Mac mini", ("p", "1"), ("r", RecognitionTag.Make(Rk))), [Saved]).Replaces);
        Assert.Null(ConnectRows.Row(Service("Studio", ("p", "1")), [marked]).Replaces);
    }
}
