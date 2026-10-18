using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Sill.Protocol;

namespace Sill.Protocol.Tests;

// The session's messages against the Swift encodings (StreamMessage.swift, Switcher.swift,
// Compatibility.swift, Remote.swift), and the session over TLS against a stand-in Mac.
public class SessionTests
{
    // ParameterSets.encoded() of a 4-byte NAL length and three sets, written out by hand.
    private static readonly byte[] PsFixture =
    [
        4, 3,
        0, 3, 0x40, 0x01, 0x0C,         // VPS (type 32: 0x40 >> 1)
        0, 2, 0x42, 0x01,               // SPS (33)
        0, 4, 0x44, 0x01, 0xC1, 0x72,   // PPS (34)
    ];

    [Fact]
    public void ParameterSetsParseTheSwiftLayout()
    {
        var ps = ParameterSets.Parse(PsFixture)!;
        Assert.Equal(4, ps.NalUnitHeaderLength);
        Assert.Equal(["VPS", "SPS", "PPS"], ps.Sets.Select(s => AccessUnit.NalName(AccessUnit.NalType(s))));
        Assert.Equal([3, 2, 4], ps.Sets.Select(s => s.Length));
        Assert.Equal(PsFixture, ps.Encode());
    }

    [Fact]
    public void ParameterSetsThatEndShortAreRefused()
    {
        Assert.Null(ParameterSets.Parse(PsFixture[..^1]));
        Assert.Null(ParameterSets.Parse([4]));
        Assert.Null(ParameterSets.Parse([4, 1, 0]));
        Assert.Empty(ParameterSets.Parse([4, 0])!.Sets);
    }

    [Fact]
    public void AnAccessUnitSplitsIntoItsNalUnits()
    {
        byte[] au = [0, 0, 0, 2, 0x26, 0x01, 0, 0, 0, 3, 0x02, 0x01, 0xAA];   // IDR_W_RADL, TRAIL_R
        var nals = AccessUnit.Nals(au, 4)!;
        Assert.Equal([(4, 2), (10, 3)], nals);
        Assert.Equal(["IDR_W_RADL", "TRAIL_R"], nals.Select(n => AccessUnit.NalName(AccessUnit.NalType(au.AsSpan(n.Offset, n.Length)))));
        Assert.Null(AccessUnit.Nals(au[..^1], 4));          // the last length runs past the end
        Assert.Null(AccessUnit.Nals([0, 0, 0], 4));         // a prefix cut short
        Assert.Null(AccessUnit.Nals(au, 0));
        Assert.Empty(AccessUnit.Nals([], 4)!);
        Assert.Equal([(2, 1)], AccessUnit.Nals([0, 1, 0x02], 2)!);
    }

    [Fact]
    public void TheHelloIsSwiftsJson()
    {
        var m = SessionMessages.Hello(new Hello("0.1", "spike", 1, "MSI (Windows)"));
        var h = StreamHeader.Parse(m);
        Assert.Equal(SessionKinds.Hello, h.Kind);
        using var doc = JsonDocument.Parse(m.AsMemory(StreamHeader.Length));
        Assert.Equal(["appVersion", "build", "protocol", "device"], doc.RootElement.EnumerateObject().Select(p => p.Name));
        Assert.Equal(1, doc.RootElement.GetProperty("protocol").GetInt32());
        // Nil fields are left out, as Swift leaves out nil optionals.
        var bare = SessionMessages.Hello(new Hello(null, null, null, "PC"));
        Assert.Equal("""{"device":"PC"}""", Encoding.UTF8.GetString(bare, StreamHeader.Length, bare.Length - StreamHeader.Length));
    }

    [Fact]
    public void TheDesktopPickIsSwiftsStreamSource()
    {
        var m = SessionMessages.SelectDesktop();
        Assert.Equal(SessionKinds.SelectSource, m[0]);
        Assert.Equal("""{"desktop":{}}""", Encoding.UTF8.GetString(m, StreamHeader.Length, m.Length - StreamHeader.Length));
    }

    [Fact]
    public void AWindowListNamesWhatStreams()
    {
        string Active(string json) => SessionMessages.Decode<WindowList>(Encoding.UTF8.GetBytes(json))!.ActiveName;
        Assert.Equal("none", Active("""{"macName":"Mac","windows":[],"active":{"none":{}}}"""));
        Assert.Equal("desktop", Active("""{"macName":"Mac","windows":[{"id":1,"title":"T","appName":"A","bundleID":"b","width":1,"height":1}],"active":{"desktop":{}},"launchID":"x"}"""));
        Assert.Equal("window 4012", Active("""{"macName":"Mac","windows":[],"active":{"window":{"_0":4012}}}"""));
        Assert.Null(SessionMessages.Decode<WindowList>("not json"u8));
    }

    [Fact]
    public void APingComesBackAsItsTime()
    {
        var m = SessionMessages.Ping(12.5);
        Assert.Equal((SessionKinds.Ping, 8u), (m[0], StreamHeader.Parse(m).PayloadLength));
        Assert.Equal(12.5, SessionMessages.PongTime(m.AsSpan(StreamHeader.Length)));
        Assert.True(double.IsNaN(SessionMessages.PongTime([1, 2])));
    }

    [Fact]
    public void AGoodbyeDecodes()
    {
        var bye = SessionMessages.Decode<Goodbye>("""{"reason":"update","message":"Update Sill.","reconnect":false}"""u8)!;
        Assert.Equal(("update", "Update Sill.", false), (bye.Reason, bye.Message, bye.Reconnect));
    }

    [Fact]
    public void TheCapsAreTheSwiftOnes()
    {
        Assert.Equal(32 << 20, SessionKinds.MaxPayload(SessionKinds.Frame));
        Assert.Equal(4 << 20, SessionKinds.MaxPayload(SessionKinds.WindowList));
        Assert.Equal(4 << 20, SessionKinds.MaxPayload(200));
    }

    // A stand-in Mac's session door: TLS 1.3 with sill/1, then whatever the test sends.
    private static async Task<(int Port, Task<byte[]?> FirstMessage)> StandInMac(DeviceIdentity mac, Func<SslStream, Task> then)
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var served = Task.Run(async () =>
        {
            try
            {
                using var tcp = await listener.AcceptTcpClientAsync();
                await using var ssl = new SslStream(tcp.GetStream());
                await ssl.AuthenticateAsServerAsync(new SslServerAuthenticationOptions
                {
                    ServerCertificate = mac.Certificate, ClientCertificateRequired = true,
                    EnabledSslProtocols = SslProtocols.Tls13,
                    ApplicationProtocols = [new SslApplicationProtocol(SillTls.Session), new SslApplicationProtocol(SillTls.Pairing)],
                    RemoteCertificateValidationCallback = (_, cert, _, _) => cert is not null,
                });
                var first = await MessageStream.ReadAsync(ssl, StreamHeader.MaxClientPayload);
                await then(ssl);
                return first is { } f ? StreamHeader.Serialize(f.Header.Kind, 0, false, f.Payload) : null;
            }
            catch (IOException) { return null; }
            catch (AuthenticationException) { return null; }
            finally { listener.Stop(); }
        });
        await Task.Yield();
        return (((IPEndPoint)listener.LocalEndpoint).Port, served);
    }

    [WindowsFact]
    public async Task TheSessionSaysHelloFirstAndReadsEveryKind()
    {
        using var mac = DeviceIdentity.CreateEphemeral();
        using var device = DeviceIdentity.CreateEphemeral();
        byte[] frame = [0, 0, 0, 2, 0x26, 0x01];
        var (port, first) = await StandInMac(mac, async ssl =>
        {
            await ssl.WriteAsync(StreamHeader.Serialize(SessionKinds.ParameterSets, 1.0, false, PsFixture));
            await ssl.WriteAsync(StreamHeader.Serialize(200, 0, false, "unknown"u8));      // a later kind: skipped by the caller
            await ssl.WriteAsync(StreamHeader.Serialize(SessionKinds.Frame, 1.5, true, frame));
        });
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        await using var session = await SessionClient.ConnectAsync("127.0.0.1", port, device, mac.Fingerprint,
            new Hello("0.1", "test", 1, "PC"), cts.Token);
        var got = new List<(byte, bool, int)>();
        while (await session.ReadAsync(cts.Token) is { } m) got.Add((m.Header.Kind, m.Header.IsKeyframe, m.Payload.Length));
        Assert.Equal([(SessionKinds.ParameterSets, false, PsFixture.Length), ((byte)200, false, 7), (SessionKinds.Frame, true, frame.Length)], got);
        Assert.Equal(SessionKinds.Hello, (await first)![0]);
    }

    [WindowsFact]
    public async Task TheSessionRefusesAnotherKey()
    {
        using var mac = DeviceIdentity.CreateEphemeral();
        using var device = DeviceIdentity.CreateEphemeral();
        var (port, first) = await StandInMac(mac, _ => Task.CompletedTask);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        await Assert.ThrowsAsync<SillTls.PinMismatchException>(() =>
            SessionClient.ConnectAsync("127.0.0.1", port, device, SHA256.HashData("another mac"u8), new Hello(null, null, 1, "PC"), cts.Token));
        Assert.Null(await first);
    }
}

// The switcher's messages (Switcher.swift, Gesture.swift), as the iOS device sends and reads them.
public class SwitcherTests
{
    private static string Json(byte[] m) => Encoding.UTF8.GetString(m, StreamHeader.Length, m.Length - StreamHeader.Length);

    [Fact]
    public void AWindowListReadsItsWindows()
    {
        var list = SessionMessages.Decode<WindowList>("""
            {"macName":"Mac","windows":[{"id":42,"title":"Doc","appName":"TextEdit","bundleID":"com.apple.TextEdit","width":800,"height":600}],
             "active":{"window":{"_0":42}},"gestures":1}
            """u8)!;
        Assert.Equal((42u, "Doc", "TextEdit", "com.apple.TextEdit", 800, 600),
            (list.Windows[0].Id, list.Windows[0].Title, list.Windows[0].AppName, list.Windows[0].BundleId, list.Windows[0].Width, list.Windows[0].Height));
        Assert.Equal(42u, list.ActiveWindowId);
        Assert.Equal(1, list.Gestures);
        Assert.Null(SessionMessages.Decode<WindowList>("""{"macName":"Mac","windows":[],"active":{"desktop":{}}}"""u8)!.ActiveWindowId);
    }

    [Fact]
    public void TheSwitchersMessagesAreSwiftsShape()
    {
        Assert.Equal((SessionKinds.SelectSource, """{"window":{"_0":42}}"""), (SessionMessages.SelectWindow(42)[0], Json(SessionMessages.SelectWindow(42))));
        Assert.Equal((SessionKinds.LaunchApp, """{"bundleID":"com.apple.TextEdit"}"""), (SessionMessages.LaunchApp("com.apple.TextEdit")[0], Json(SessionMessages.LaunchApp("com.apple.TextEdit"))));
        Assert.Equal((SessionKinds.WindowCommand, """{"id":42,"action":"minimize"}"""), (SessionMessages.WindowCommand(42, "minimize")[0], Json(SessionMessages.WindowCommand(42, "minimize"))));
        Assert.Equal((SessionKinds.Gesture, """{"gesture":"swipeUp","fingers":3}"""), (SessionMessages.Gesture(Gestures.MissionControl)[0], Json(SessionMessages.Gesture(Gestures.MissionControl))));
    }

    [Fact]
    public void ImageBlobsSplitTheirKey()
    {
        var thumb = ImageBlobs.Thumbnail([1, 2, 3, 4, 0xFF, 0xD8])!.Value;
        Assert.Equal(0x01020304u, thumb.WindowId);
        Assert.Equal(new byte[] { 0xFF, 0xD8 }, thumb.Jpeg);
        Assert.Null(ImageBlobs.Thumbnail([1, 2, 3, 4]));
        var icon = ImageBlobs.Icon([0, 3, (byte)'a', (byte)'.', (byte)'b', 0x89, 0x50])!.Value;
        Assert.Equal("a.b", icon.BundleId);
        Assert.Equal(new byte[] { 0x89, 0x50 }, icon.Png);
        Assert.Null(ImageBlobs.Icon([0, 3, (byte)'a', (byte)'.', (byte)'b']));
    }

    [Fact]
    public void AnAppListDecodes()
    {
        var apps = SessionMessages.Decode<List<AppInfo>>("""[{"name":"TextEdit","bundleID":"com.apple.TextEdit"}]"""u8)!;
        Assert.Equal(("TextEdit", "com.apple.TextEdit"), (apps[0].Name, apps[0].BundleId));
    }
}

public class CursorBlobTests
{
    [Fact]
    public void ReadsSwiftsCursorShapeBlob()
    {
        // CursorShapeBlob.encode(hotspot: (4, 5), size: (17, 23), png): four Float32 big endian, then the PNG.
        byte[] blob = [0x40, 0x80, 0, 0, 0x40, 0xA0, 0, 0, 0x41, 0x88, 0, 0, 0x41, 0xB8, 0, 0, 0x89, 0x50, 0x4E, 0x47];
        var c = ImageBlobs.Cursor(blob)!.Value;
        Assert.Equal((4f, 5f, 17f, 23f), (c.HotX, c.HotY, c.Width, c.Height));
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47 }, c.Png);
    }

    [Fact]
    public void RefusesShortOrNonsenseBlobs()
    {
        Assert.Null(ImageBlobs.Cursor(new byte[16]));
        Assert.Null(ImageBlobs.Cursor(new byte[20]));   // a zero size
        byte[] nan = [0x7F, 0xC0, 0, 0, 0, 0, 0, 0, 0x41, 0x88, 0, 0, 0x41, 0xB8, 0, 0, 1];
        Assert.Null(ImageBlobs.Cursor(nan));
    }
}
