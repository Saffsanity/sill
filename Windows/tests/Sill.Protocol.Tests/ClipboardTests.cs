using System.Text;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 09: kind 32 as Clipboard.swift encodes it, and ClipboardPolicy.swift's device rules
/// with Windows' markers. The fixtures are Swift's JSONEncoder's output for the same values.</summary>
public class ClipboardTests
{
    private static string Text(byte[] b) => Encoding.UTF8.GetString(b);

    [Fact]
    public void EncodesAsSwiftDoes()
    {
        Assert.Equal("{}", Text(ClipboardPolicy.Subscribing));
        Assert.Equal("""{"stop":true}""", Text(ClipboardPolicy.Stopping));
        Assert.Equal("""{"text":"hi"}""", Text(ClipboardPolicy.Payload("hi")!));
        Assert.Equal("""{"text":"x","image":"AQID"}""", Text(ClipboardPolicy.Encode(new Clipboard("x", [1, 2, 3]))));
        // Swift writes "/" as "\/"; otherwise byte for byte, non-ASCII as UTF-8.
        const string swift = "{\"text\":\"Café ☕️ \\\"q\\\" a\\/b\\n\\t\\u0001\"}";
        Assert.Equal(swift.Replace("\\/", "/"), Text(ClipboardPolicy.Payload("Café ☕️ \"q\" a/b\n\t\u0001")!));
        var message = ClipboardPolicy.Message(ClipboardPolicy.Subscribing);
        Assert.Equal(32, message[0]);
        Assert.Equal(StreamHeader.Length + 2, message.Length);
    }

    [Fact]
    public void ReadsWhatSwiftWrites()
    {
        Assert.Equal("Café ☕️ \"q\" a/b\n\t\u0001", ClipboardPolicy.Decode("{\"text\":\"Café ☕️ \\\"q\\\" a\\/b\\n\\t\\u0001\"}"u8)!.Text);
        var c = ClipboardPolicy.Decode("""{"text":"a","stop":false,"extra":1}"""u8)!;
        Assert.Equal(new Clipboard("a", null, false), c);
        Assert.Equal([1, 2, 3], ClipboardPolicy.Decode("""{"image":"AQID"}"""u8)!.Image);
        Assert.Null(ClipboardPolicy.Decode("""{"text":3}"""u8));
        Assert.Null(ClipboardPolicy.Decode("not json"u8));
    }

    [Fact]
    public void KeepsToTheCaps()
    {
        Assert.Null(ClipboardPolicy.Payload(""));
        Assert.NotNull(ClipboardPolicy.Payload(new string('a', Clipboard.MaxTextBytes)));
        Assert.Null(ClipboardPolicy.Payload(new string('a', Clipboard.MaxTextBytes + 1)));
        // 2-byte characters: 131,072 of them are the cap.
        Assert.NotNull(ClipboardPolicy.Payload(new string('é', Clipboard.MaxTextBytes / 2)));
        Assert.Null(ClipboardPolicy.Payload(new string('é', Clipboard.MaxTextBytes / 2 + 1)));
        // Within the text cap, but six bytes a character as JSON: over 1 MiB, not sent.
        Assert.Null(ClipboardPolicy.Payload(new string('\u0001', 200_000)));
        Assert.NotNull(ClipboardPolicy.Payload(new string('\u0001', 170_000)));
    }

    [Fact]
    public void ReadsTheWindowListsClipboard()
    {
        var list = SessionMessages.Decode<WindowList>("""{"macName":"Mac","windows":[],"active":{"none":{}},"clipboard":1}"""u8)!;
        Assert.Equal(1, list.Clipboard);
        Assert.Null(SessionMessages.Decode<WindowList>("""{"macName":"Mac","windows":[],"active":{"none":{}}}"""u8)!.Clipboard);
        Assert.True(ClipboardPolicy.HostTakes(1));
        Assert.True(ClipboardPolicy.HostTakes(2));
        Assert.False(ClipboardPolicy.HostTakes(0));
        Assert.False(ClipboardPolicy.HostTakes(null));
    }

    [Theory]
    [InlineData(null, true, false, ClipboardPolicy.Subscription.None, false)]
    [InlineData(null, false, true, ClipboardPolicy.Subscription.None, false)]   // the Mac stopped saying it: it forgot
    [InlineData(1, true, false, ClipboardPolicy.Subscription.Subscribe, true)]
    [InlineData(1, true, true, ClipboardPolicy.Subscription.None, true)]
    [InlineData(1, false, true, ClipboardPolicy.Subscription.Stop, false)]
    [InlineData(1, false, false, ClipboardPolicy.Subscription.None, false)]
    [InlineData(2, true, false, ClipboardPolicy.Subscription.Subscribe, true)]
    public void SubscribesAndStops(int? host, bool on, bool subscribed, ClipboardPolicy.Subscription send, bool after)
    {
        Assert.Equal((send, after), ClipboardPolicy.DeviceSubscription(host, on, subscribed));
    }

    [Fact]
    public void WritesTheMacsTextButNotItsEcho()
    {
        var hi = """{"text":"hi"}"""u8.ToArray();
        Assert.Equal("hi", ClipboardPolicy.DeviceWrites(hi, true, 1, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites(hi, false, 1, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites(hi, true, null, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites("""{"text":""}"""u8, true, 1, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites("""{"image":"AQID"}"""u8, true, 1, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites("{"u8, true, 1, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites(ClipboardPolicy.Encode(new Clipboard(new string('a', Clipboard.MaxTextBytes + 1))), true, 1, null, 5));
        Assert.Null(ClipboardPolicy.DeviceWrites(hi, true, 1, new("hi", 5), 5));     // what this PC sent, still on its clipboard
        Assert.Equal("hi", ClipboardPolicy.DeviceWrites(hi, true, 1, new("hi", 4), 5));   // copied again since
        Assert.Equal("hi", ClipboardPolicy.DeviceWrites(hi, true, 1, new("ho", 5), 5));
    }

    [Fact]
    public void NeverReadsAMarkedCopy()
    {
        int reads = 0;
        string Read() { reads++; return "secret"; }
        Assert.Equal(ClipboardPolicy.Skip.Marked, ClipboardPolicy.PcDecides(7, null, true, null, null, Read).Why);
        Assert.Equal(ClipboardPolicy.Skip.Marked, ClipboardPolicy.PcDecides(7, null, false, 0, null, Read).Why);
        Assert.Equal(ClipboardPolicy.Skip.Marked, ClipboardPolicy.PcDecides(7, null, false, null, 0, Read).Why);
        Assert.Equal(ClipboardPolicy.Skip.Own, ClipboardPolicy.PcDecides(7, 7, false, null, null, Read).Why);
        Assert.Equal(0, reads);
        var (send, why) = ClipboardPolicy.PcDecides(8, 7, false, 1, 1, Read);
        Assert.Null(why);
        Assert.Equal("""{"text":"secret"}""", Text(send!));
        Assert.Equal(1, reads);
        Assert.Equal(ClipboardPolicy.Skip.NoText, ClipboardPolicy.PcDecides(8, null, false, null, null, () => null).Why);
        Assert.Equal(ClipboardPolicy.Skip.Empty, ClipboardPolicy.PcDecides(8, null, false, null, null, () => "").Why);
        Assert.Equal(ClipboardPolicy.Skip.TooLong, ClipboardPolicy.PcDecides(8, null, false, null, null, () => new string('a', 300_000)).Why);
        // The same copy again (put, then flushed) within the window; later, or other text, goes.
        var sent = new ClipboardPolicy.Sent("secret", 8, 10);
        Assert.Equal(ClipboardPolicy.Skip.Repeat, ClipboardPolicy.PcDecides(9, null, false, null, null, Read, sent, 10.01).Why);
        Assert.Null(ClipboardPolicy.PcDecides(9, null, false, null, null, Read, sent, 11).Why);
        Assert.Null(ClipboardPolicy.PcDecides(9, null, false, null, null, () => "other", sent, 10.01).Why);
    }

    [Fact]
    public void TheOutboxKeepsToTheRateAndSendsTheNewest()
    {
        var box = new ClipboardOutbox();
        byte[] T(string s) => ClipboardPolicy.Payload(s)!;
        Assert.NotNull(box.Offer(ClipboardPolicy.Subscribing, false, 0));
        Assert.NotNull(box.Offer(T("a"), true, 0.1));
        Assert.NotNull(box.Offer(T("b"), true, 0.2));
        Assert.NotNull(box.Offer(T("c"), true, 0.3));
        Assert.Null(box.Offer(T("d"), true, 0.4));        // a fifth in the window waits
        Assert.Null(box.Offer(T("e"), true, 0.5));        // and is replaced by the newest
        Assert.Null(box.Offer(ClipboardPolicy.Subscribing, false, 0.6));   // a subscription never replaces a held text
        Assert.Equal(ClipboardOutbox.Window, box.NextAt);
        Assert.Null(box.Due(1.2));
        Assert.Equal("""{"text":"e"}""", Text(box.Due(1.25)!));
        Assert.Null(box.NextAt);
        Assert.Null(box.Due(1.26));
        // A stop drops what is held.
        Assert.Null(box.Offer(T("f"), true, 1.3));
        box.Stop();
        Assert.Null(box.NextAt);
        // A window's worth later, four go at once again.
        for (int i = 0; i < 4; i++) Assert.NotNull(box.Offer(T("g" + i), true, 10 + i * 0.01));
        Assert.Null(box.Offer(T("h"), true, 10.05));
        box.Reset();
        Assert.NotNull(box.Offer(T("i"), true, 10.06));
    }

    [Fact]
    public void TheOutboxNeverLetsMoreThanFourThroughInAnyWindow()
    {
        var box = new ClipboardOutbox();
        var rng = new Random(9);
        var times = new List<double>();
        double now = 0;
        for (int i = 0; i < 5000; i++)
        {
            now += rng.NextDouble() * 0.3;
            if (box.Due(now) is not null) times.Add(now);
            if (rng.Next(3) > 0 && box.Offer(ClipboardPolicy.Payload("x" + i)!, true, now) is not null) times.Add(now);
        }
        for (int i = ClipboardPolicy.PerSecond; i < times.Count; i++)
            Assert.True(times[i] - times[i - ClipboardPolicy.PerSecond] >= ClipboardOutbox.Window - 1e-9);
    }

    [Fact]
    public void ThePlacementKeepsTheSwitchOnByDefault()
    {
        Assert.True(System.Text.Json.JsonSerializer.Deserialize<WindowPlacement>("""{"x":1,"y":2,"width":3,"height":4,"maximized":false,"fullScreen":false}""")!.ShareClipboard);
        var off = new WindowPlacement(1, 2, 3, 4, false, false, false, ShareClipboard: false);
        Assert.False(System.Text.Json.JsonSerializer.Deserialize<WindowPlacement>(System.Text.Json.JsonSerializer.Serialize(off))!.ShareClipboard);
    }
}
