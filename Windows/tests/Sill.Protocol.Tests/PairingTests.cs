using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Sill.Protocol;

namespace Sill.Protocol.Tests;

// The vectors are docs/remote-access-plan.md §3.4 and §3.6's (computed in Python, matched by the
// Swift side); the link's was made with Python the way PairLink.url escapes it.
public class PairingTests
{
    private static byte[] Hex(string s) => Convert.FromHexString(s);
    private static readonly byte[] FpMac = SHA256.HashData("mac"u8);
    private static readonly byte[] FpDevice = SHA256.HashData("device"u8);

    [Fact]
    public void TheVectorsFingerprintsAreTheirHashes()
    {
        Assert.Equal(Hex("348a629f5ceed032c3e8706ec47d9bfafb00fb4250b018dd965435ca50cb836e"), FpMac);
        Assert.Equal(Hex("263a4dbe41488fb87214b0032339dbb9f0c8da14c16dfcf13084bf3c2552eca5"), FpDevice);
    }

    [Fact]
    public void MacIdVector() =>
        Assert.Equal("A3C5HR4RBV67YR21", MacId.Make(SHA256.HashData("example"u8)));

    [Fact]
    public void MacIdIsWellFormed()
    {
        Assert.True(MacId.IsWellFormed(MacId.Make(FpMac)));
        Assert.False(MacId.IsWellFormed("A3C5HR4RBV67YR2I"));   // I is not Crockford
        Assert.False(MacId.IsWellFormed("A3C5HR4RBV67YR2"));
    }

    [Fact]
    public void SpkiMatchesDotNetsExport()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var q = key.ExportParameters(false).Q;
        byte[] point = [0x04, .. q.X!, .. q.Y!];
        Assert.Equal(key.ExportSubjectPublicKeyInfo(), Spki.Der(point));
        Assert.Equal(SHA256.HashData(key.ExportSubjectPublicKeyInfo()), Spki.Fingerprint(key));
    }

    [Fact]
    public void SpkiRefusesAnotherCurve()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP384);
        Assert.Null(Spki.Fingerprint(key));
    }

    [Theory]
    [InlineData("482913557208", PairingCode.Problem.None, "482913557208")]
    [InlineData("4829 1355 7208", PairingCode.Problem.None, "482913557208")]
    [InlineData("4829-1355 7208", PairingCode.Problem.None, "482913557208")]
    [InlineData("482913557209", PairingCode.Problem.Typo, "482913557209")]
    [InlineData("428913557208", PairingCode.Problem.Typo, "428913557208")]   // adjacent transposition
    [InlineData("48291355720", PairingCode.Problem.Length, "48291355720")]
    [InlineData("48291355720a", PairingCode.Problem.Length, "48291355720a")]
    [InlineData("٤٨٢٩١٣٥٥٧٢٠٨", PairingCode.Problem.Length, "٤٨٢٩١٣٥٥٧٢٠٨")]  // not ASCII digits
    public void ChecksTypedCodes(string input, PairingCode.Problem problem, string code)
    {
        Assert.Equal(problem, PairingCode.Check(input, out string kept));
        Assert.Equal(code, kept);
    }

    [Fact]
    public void TheExamplesCheckDigitIs8() =>
        Assert.Equal(8, PairingCode.CheckDigit("48291355720".Select(c => c - '0')));

    [Fact]
    public void DammCatchesEverySubstitutionAndAdjacentTransposition()
    {
        var random = new Random(20261018);
        for (int n = 0; n < 2000; n++)
        {
            var digits = Enumerable.Range(0, 11).Select(_ => random.Next(10)).ToList();
            digits.Add(PairingCode.CheckDigit(digits));
            Assert.Equal(0, PairingCode.CheckDigit(digits));
            for (int i = 0; i < 12; i++)
            {
                for (int d = 0; d < 10; d++)
                {
                    if (d == digits[i]) continue;
                    var typo = digits.ToList(); typo[i] = d;
                    Assert.NotEqual(0, PairingCode.CheckDigit(typo));
                }
                if (i < 11 && digits[i] != digits[i + 1])
                {
                    var swapped = digits.ToList(); (swapped[i], swapped[i + 1]) = (swapped[i + 1], swapped[i]);
                    Assert.NotEqual(0, PairingCode.CheckDigit(swapped));
                }
            }
        }
    }

    [Fact]
    public void Groups() => Assert.Equal("4829 1355 7208", PairingCode.Grouped("482913557208"));

    [Fact]
    public void CodeVectors()
    {
        byte[] key = PairingProof.CodeKey("482913557208", FpMac)!;
        Assert.Equal(Hex("e9baf879a1cc4ac8b21554df480b6c1621671319107c91e7cb05d154f649d31d"), key);
        Assert.Equal("dk7PZj4vHsAxj--1u9Vg7ehSn8a1tWc0RCG46YpFVO8", Base64Url.Encode(PairingProof.DeviceProof(key, FpDevice, FpMac)));
        Assert.Equal("6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk", Base64Url.Encode(PairingProof.MacProof(key, FpMac, FpDevice)));
    }

    [Fact]
    public void QrVectors()
    {
        byte[] key = Enumerable.Repeat((byte)0x22, 16).ToArray();
        Assert.Equal("AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo", Base64Url.Encode(PairingProof.DeviceProof(key, FpDevice, FpMac)));
        Assert.Equal("XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE", Base64Url.Encode(PairingProof.MacProof(key, FpMac, FpDevice)));
    }

    [Fact]
    public void SwappedFingerprintsChangeTheProofs()
    {
        byte[] key = PairingProof.CodeKey("482913557208", FpMac)!;
        Assert.NotEqual(PairingProof.DeviceProof(key, FpDevice, FpMac), PairingProof.DeviceProof(key, FpMac, FpDevice));
        Assert.NotEqual(PairingProof.DeviceProof(key, FpDevice, FpMac), PairingProof.MacProof(key, FpDevice, FpMac));
    }

    [Fact]
    public void CodeKeyRefusesNonCodes()
    {
        Assert.Null(PairingProof.CodeKey("48291355720", FpMac));
        Assert.Null(PairingProof.CodeKey("4829 1355 720", FpMac));
    }

    [Theory]
    [InlineData("", "")]
    [InlineData("AA", "\0")]
    [InlineData("_-8", "\xff\xef")]
    public void Base64UrlRoundTrips(string text, string latin1)
    {
        byte[] bytes = Encoding.Latin1.GetBytes(latin1);
        Assert.Equal(text, Base64Url.Encode(bytes));
        Assert.Equal(bytes, Base64Url.Decode(text));
    }

    [Theory]
    [InlineData("AA==")]      // padding
    [InlineData("+/8")]       // the standard alphabet
    [InlineData("A")]         // no encoding is 1 mod 4 long
    [InlineData("AB")]        // trailing bits set: not canonical
    [InlineData("AA AA")]
    public void Base64UrlRefusesNonCanonical(string text) => Assert.Null(Base64Url.Decode(text));
}

public class PairLinkTests
{
    private const string Link =
        "sill://pair?v=1&m=6J5657TWXV835GZ8&k=NIpin1zu0DLD6HBuxH2b-vsA-0JQsBjdllQ1ylDLg24&s=IiIiIiIiIiIiIiIiIiIiIg" +
        "&n=Tom%20%26%20Jerry%E2%80%99s%20Mac&p=7455&a=mac.tail1234.ts.net&a=%5Bfd7a:115c:a1e0::1%5D:7455";

    private static PairLink.Failure Parse(string s, out PairLink? link) => PairLink.Parse(s, out link, out _);

    [Fact]
    public void ParsesALink()
    {
        Assert.Equal(PairLink.Failure.None, Parse("  " + Link + "\n", out var link));
        Assert.Equal("6J5657TWXV835GZ8", link!.MacId);
        Assert.Equal(SHA256.HashData("mac"u8), link.Fingerprint);
        Assert.Equal(Enumerable.Repeat((byte)0x22, 16), link.Secret);
        Assert.Equal("Tom & Jerry’s Mac", link.Name);
        Assert.Equal(7455, link.Port);
        Assert.Equal(["mac.tail1234.ts.net", "[fd7a:115c:a1e0::1]:7455"], link.Addresses);
    }

    [Theory]
    [InlineData("https://pair?v=1", PairLink.Failure.NotALink)]
    [InlineData("sill://pairing?v=1", PairLink.Failure.NotALink)]
    [InlineData("v=2", PairLink.Failure.Version)]
    [InlineData("v=1&v=1", PairLink.Failure.Version)]
    [InlineData("m=6J5657TWXV835GZ9", PairLink.Failure.MacIdMismatch)]
    [InlineData("m=6J5657TWXV835GZ", PairLink.Failure.Field)]
    [InlineData("s=IiIiIiIiIiIiIiIiIiIi", PairLink.Failure.Field)]
    [InlineData("p=0", PairLink.Failure.Field)]
    [InlineData("p=65536", PairLink.Failure.Field)]
    [InlineData("p=+7455", PairLink.Failure.Field)]
    [InlineData("a=", PairLink.Failure.Address)]
    public void RefusesBadLinks(string change, PairLink.Failure expected)
    {
        string link = change.StartsWith("https") || change.StartsWith("sill://pairing") ? change : Replace(Link, change);
        Assert.Equal(expected, Parse(link, out _));
    }

    // Replaces the first of each key=value in the link (or adds it), keeping the rest.
    private static string Replace(string link, string change)
    {
        string result = link;
        foreach (string kv in change.Split('&').Distinct())
        {
            string key = kv[..kv.IndexOf('=')];
            int count = change.Split('&').Count(c => c.StartsWith(key + "="));
            var parts = result[(result.IndexOf('?') + 1)..].Split('&').ToList();
            int at = parts.FindIndex(p => p.StartsWith(key + "="));
            if (at >= 0) parts[at] = kv; else parts.Add(kv);
            for (int i = 1; i < count; i++) parts.Add(kv);
            result = "sill://pair?" + string.Join('&', parts);
        }
        return result;
    }

    [Fact]
    public void KeepsFiveAddressesAndIgnoresUnknownParameters()
    {
        string link = Link + "&x=1" + string.Concat(Enumerable.Range(1, 6).Select(i => $"&a=10.0.0.{i}"));
        Assert.Equal(PairLink.Failure.None, Parse(link, out var parsed));
        Assert.Equal(5, parsed!.Addresses.Count);
    }

    [Fact]
    public void ANamelessLinkNamesTheMacMac()
    {
        Assert.Equal(PairLink.Failure.None, Parse(Link.Replace("&n=Tom%20%26%20Jerry%E2%80%99s%20Mac", "&n=%E2%80%AE%0A"), out var link));
        Assert.Equal("Mac", link!.Name);
    }
}

public class PairingExchangeTests
{
    private static readonly byte[] FpMac = SHA256.HashData("mac"u8);
    private static readonly byte[] FpDevice = SHA256.HashData("device"u8);
    private static readonly string Recognition = Base64Url.Encode(new byte[32]);

    [Fact]
    public void TheRequestIsTheJsonSwiftWrites()
    {
        var x = PairingExchange.ForCode("482913557208", FpMac, FpDevice);
        byte[] message = x.RequestMessage("Jericho’s PC", null);
        var header = StreamHeader.Parse(message);
        Assert.Equal(Kinds.PairRequest, header.Kind);
        Assert.Equal((uint)(message.Length - StreamHeader.Length), header.PayloadLength);
        using var json = JsonDocument.Parse(message.AsMemory(StreamHeader.Length));
        var root = json.RootElement;
        Assert.Equal(1, root.GetProperty("v").GetInt32());
        Assert.Equal("code", root.GetProperty("method").GetString());
        Assert.Equal("dk7PZj4vHsAxj--1u9Vg7ehSn8a1tWc0RCG46YpFVO8", root.GetProperty("proof").GetString());
        Assert.Equal("Jericho’s PC", root.GetProperty("name").GetString());
        Assert.False(root.TryGetProperty("model", out _));   // nil is left out, as Swift does
        Assert.False(root.TryGetProperty("cable", out _));
    }

    private static byte[] Result(object o) => JsonSerializer.SerializeToUtf8Bytes(o);

    [Fact]
    public void APairingWithTheMacsProofIsTaken()
    {
        var x = PairingExchange.ForCode("482913557208", FpMac, FpDevice);
        var verdict = x.Judge(Result(new { ok = true, proof = "6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk",
            macID = MacId.Make(FpMac), name = "Mac mini", recognitionKey = Recognition }), out var r);
        Assert.Equal(PairingExchange.Verdict.Paired, verdict);
        Assert.Equal("Mac mini", r!.Name);
    }

    [Fact]
    public void TheLinkPathUsesTheSecret()
    {
        PairLink.Parse("sill://pair?v=1&m=6J5657TWXV835GZ8&k=NIpin1zu0DLD6HBuxH2b-vsA-0JQsBjdllQ1ylDLg24&s=IiIiIiIiIiIiIiIiIiIiIg&p=7455",
                       out var link, out _);
        var x = PairingExchange.ForLink(link!, FpDevice);
        Assert.Equal("AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo", x.Request("PC", "x64").Proof);
        Assert.Equal("qr", x.Method);
        Assert.Equal(PairingExchange.Verdict.Paired, x.Judge(Result(new { ok = true,
            proof = "XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE", macID = MacId.Make(FpMac), recognitionKey = Recognition }), out _));
    }

    [Theory]
    [InlineData("XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE", true, 32)]   // the QR path's proof_M: another key
    [InlineData("6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk", false, 32)]  // the Mac ID of another key
    [InlineData("6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk", true, 16)]   // a short recognition key
    public void AnOkWithoutTheMacsProofIsNot(string proof, bool rightMacId, int recognitionLength)
    {
        var x = PairingExchange.ForCode("482913557208", FpMac, FpDevice);
        var verdict = x.Judge(Result(new { ok = true, proof, macID = rightMacId ? MacId.Make(FpMac) : MacId.Make(FpDevice),
            recognitionKey = Base64Url.Encode(new byte[recognitionLength]) }), out _);
        Assert.Equal(PairingExchange.Verdict.NoProof, verdict);
    }

    [Fact]
    public void AWrongCodeIsRefusedWithItsTries()
    {
        var x = PairingExchange.ForCode("482913557208", FpMac, FpDevice);
        Assert.Equal(PairingExchange.Verdict.Refused, x.Judge("""{"ok":false,"reason":"code","triesLeft":4}"""u8, out var r));
        Assert.Equal("That code didn’t work. Check the code on your Mac. 4 tries left.", PairingExchange.Words(r!, "Mac mini"));
    }

    [Fact]
    public void AnUnknownReasonShowsTheMacsWords()
    {
        var x = PairingExchange.ForCode("482913557208", FpMac, FpDevice);
        x.Judge("""{"ok":false,"reason":"later","message":"Update\nSill on this PC."}"""u8, out var r);
        Assert.Equal("Update Sill on this PC.", PairingExchange.Words(r!, "Mac mini"));
        x.Judge("""{"ok":false,"reason":"closed","message":"ignored"}"""u8, out r);
        Assert.Equal("Mac mini isn’t pairing right now. On your Mac, choose Pair iPhone or iPad… first.", PairingExchange.Words(r!, "Mac mini"));
    }

    [Fact]
    public void GarbageIsMalformed()
    {
        var x = PairingExchange.ForCode("482913557208", FpMac, FpDevice);
        Assert.Equal(PairingExchange.Verdict.Malformed, x.Judge("not json"u8, out _));
    }

    [Fact]
    public async Task ReadsWholeMessagesAndRefusesOversize()
    {
        byte[] one = StreamHeader.Serialize(20, 0, false, "{}"u8);
        var stream = new MemoryStream([.. one, .. one]);
        var m = await MessageStream.ReadAsync(stream, 4096);
        Assert.Equal((byte)20, m!.Value.Header.Kind);
        Assert.Equal("{}"u8.ToArray(), m.Value.Payload);
        Assert.NotNull(await MessageStream.ReadAsync(stream, 4096));
        Assert.Null(await MessageStream.ReadAsync(stream, 4096));
        await Assert.ThrowsAsync<InvalidDataException>(() => MessageStream.ReadAsync(new MemoryStream(one), 1));
        await Assert.ThrowsAsync<EndOfStreamException>(() => MessageStream.ReadAsync(new MemoryStream(one[..5]), 4096));
    }
}

public class SafeTextTests
{
    [Theory]
    [InlineData("  Mac\n\tmini  ", "Mac mini")]
    [InlineData("i‮Pad", "iPad")]
    [InlineData("a​b", "ab")]
    [InlineData(" 　", "")]
    public void Cleans(string input, string expected) => Assert.Equal(expected, SafeText.Label(input));

    // A letter keeps its combining mark at the limit. A joiner (U+200D) is a format character and
    // goes, as in Swift, so a family emoji becomes its people.
    [Fact]
    public void KeepsWholeCharactersAtTheLimit()
    {
        Assert.Equal("abe\u0301", SafeText.Label("abe\u0301cd", 3));
        Assert.Equal("ab\U0001F469", SafeText.Label("ab\U0001F469\u200D\U0001F469cd", 3));
    }
}
