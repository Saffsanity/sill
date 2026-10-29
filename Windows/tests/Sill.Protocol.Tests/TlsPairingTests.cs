using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Sill.Protocol;

namespace Sill.Protocol.Tests;

/// <summary>SChannel does TLS 1.3; .NET on macOS does not, so these run only on Windows.</summary>
public sealed class WindowsFactAttribute : FactAttribute
{
    public WindowsFactAttribute()
    {
        if (!OperatingSystem.IsWindows()) Skip = "TLS 1.3 needs SChannel: Windows only.";
    }
}

// The pairing client against a stand-in Mac on loopback: the Mac's side of Remote.swift's
// exchange (its key pinned by the device, one kind 19 in, one kind 20 out), written from the
// plan's rules, not from the client's code.
public class TlsPairingTests
{
    private const string Code = "729000986820";   // Damm-valid

    private sealed class FakeMac : IAsyncDisposable
    {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);
        private readonly Task<byte[]?> served;
        public DeviceIdentity Key { get; } = DeviceIdentity.CreateEphemeral();
        public byte[] Secret { get; } = RandomNumberGenerator.GetBytes(16);
        public int Port => ((IPEndPoint)listener.LocalEndpoint).Port;
        public byte[]? DeviceSeen { get; private set; }

        /// <param name="answer">The kind 20 to send, given the request and the key both sides
        /// should hold; null sends the honest answer.</param>
        public FakeMac(string code, Func<PairRequest, byte[], PairResult>? answer = null)
        {
            listener.Start();
            served = Task.Run(async () =>
            {
                using var tcp = await listener.AcceptTcpClientAsync();
                await using var ssl = new SslStream(tcp.GetStream());
                try
                {
                    await ssl.AuthenticateAsServerAsync(new SslServerAuthenticationOptions
                    {
                        ServerCertificate = Key.Certificate,
                        ClientCertificateRequired = true,
                        EnabledSslProtocols = SslProtocols.Tls13,
                        ApplicationProtocols = [new SslApplicationProtocol(SillTls.Session), new SslApplicationProtocol(SillTls.Pairing)],
                        RemoteCertificateValidationCallback = (_, cert, _, _) =>
                        {
                            DeviceSeen = cert is null ? null : SillTls.Fingerprint(cert);
                            return DeviceSeen is not null;
                        },
                    });
                }
                catch (AuthenticationException) { return null; }
                catch (IOException) { return null; }
                (StreamHeader Header, byte[] Payload)? m;
                try { m = await MessageStream.ReadAsync(ssl, StreamHeader.MaxPairingPayload); }
                catch (IOException) { return null; }   // the device refused this Mac's key after the handshake
                if (m is null) return null;
                var req = JsonSerializer.Deserialize<PairRequest>(m.Value.Payload)!;
                byte[] key = req.Method == PairRequest.Code ? PairingProof.CodeKey(code, Key.Fingerprint)! : Secret;
                var result = answer?.Invoke(req, key) ?? Honest(req, key);
                await ssl.WriteAsync(StreamHeader.Serialize(Kinds.PairResult, 0, false,
                    JsonSerializer.SerializeToUtf8Bytes(result, new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull })));
                return m.Value.Payload;
            });
        }

        private PairResult Honest(PairRequest req, byte[] key)
        {
            byte[] want = PairingProof.DeviceProof(key, DeviceSeen!, Key.Fingerprint);
            if (!CryptographicOperations.FixedTimeEquals(Base64Url.Decode(req.Proof), want))
                return new PairResult(false, Reason: PairResult.WrongCode, TriesLeft: 4);
            return new PairResult(true, Base64Url.Encode(PairingProof.MacProof(key, Key.Fingerprint, DeviceSeen!)),
                MacId.Make(Key.Fingerprint), "Test Mac", Base64Url.Encode(RandomNumberGenerator.GetBytes(32)), Method: req.Method);
        }

        public PairLink Link(byte[]? fingerprint = null)
        {
            byte[] fp = fingerprint ?? Key.Fingerprint;
            return new PairLink(MacId.Make(fp), fp, Secret, "Test Mac", Port, ["127.0.0.1"]);
        }

        /// <summary>The kind 19's payload, or null if none arrived.</summary>
        public Task<byte[]?> Served => served;

        public async ValueTask DisposeAsync()
        {
            listener.Stop();
            try { await served.WaitAsync(TimeSpan.FromSeconds(5)); } catch { }
            Key.Dispose();
        }
    }

    private static CancellationToken Soon => new CancellationTokenSource(TimeSpan.FromSeconds(30)).Token;

    [WindowsFact]
    public async Task TheTypedCodePairs()
    {
        await using var mac = new FakeMac(Code);
        using var device = DeviceIdentity.CreateEphemeral();
        var outcome = await PairingClient.PairWithCodeAsync("127.0.0.1", mac.Port, Code, device, "PC", "Windows", Soon);
        Assert.True(outcome.Paired);
        Assert.Equal(mac.Key.Fingerprint, outcome.MacFingerprint);
        Assert.Equal(device.Fingerprint, mac.DeviceSeen);
        var sent = JsonSerializer.Deserialize<PairRequest>((await mac.Served)!)!;
        Assert.Equal(("code", 1, "PC", "Windows"), (sent.Method, sent.V, sent.Name, sent.Model));
    }

    [WindowsFact]
    public async Task AWrongCodeIsRefusedWithTheTriesLeft()
    {
        await using var mac = new FakeMac(Code);
        using var device = DeviceIdentity.CreateEphemeral();
        var outcome = await PairingClient.PairWithCodeAsync("127.0.0.1", mac.Port, "123456789018", device, "PC", null, Soon);
        Assert.Equal(PairingExchange.Verdict.Refused, outcome.Verdict);
        Assert.Equal(PairResult.WrongCode, outcome.Result!.Reason);
        Assert.Contains("4 tries left", PairingExchange.Words(outcome.Result, "Test Mac"));
    }

    [WindowsFact]
    public async Task TheLinkPairsPinnedToItsKey()
    {
        await using var mac = new FakeMac(Code);
        using var device = DeviceIdentity.CreateEphemeral();
        var outcome = await PairingClient.PairWithLinkAsync("127.0.0.1", mac.Port, mac.Link(), device, "PC", null, Soon);
        Assert.True(outcome.Paired);
        Assert.Equal("qr", JsonSerializer.Deserialize<PairRequest>((await mac.Served)!)!.Method);
    }

    [WindowsFact]
    public async Task ALinkToAnotherKeySendsNothing()
    {
        await using var mac = new FakeMac(Code);
        using var device = DeviceIdentity.CreateEphemeral();
        var other = SHA256.HashData("another mac"u8);
        await Assert.ThrowsAsync<SillTls.PinMismatchException>(() =>
            PairingClient.PairWithLinkAsync("127.0.0.1", mac.Port, mac.Link(other), device, "PC", null, Soon));
        Assert.Null(await mac.Served);
        // Unlike iOS, whose verify block runs before its certificate goes out, SChannel sends the
        // device's certificate in TLS 1.3's last flight and only then lets .NET judge the Mac's
        // key: a Mac the link does not name learns the device's public key, and nothing else.
        Assert.Equal(device.Fingerprint, mac.DeviceSeen);
    }

    [WindowsFact]
    public async Task AYesWithoutTheMacsProofIsNotPaired()
    {
        // The right shape, the key of nothing: a Mac that never knew the code.
        await using var mac = new FakeMac(Code, (req, _) =>
            new PairResult(true, Base64Url.Encode(RandomNumberGenerator.GetBytes(32)), "0000000000000000", "Liar",
                           Base64Url.Encode(new byte[32])));
        using var device = DeviceIdentity.CreateEphemeral();
        var outcome = await PairingClient.PairWithCodeAsync("127.0.0.1", mac.Port, Code, device, "PC", null, Soon);
        Assert.Equal(PairingExchange.Verdict.NoProof, outcome.Verdict);
    }

    [WindowsFact]
    public async Task TheAskAndItsCancelCarryNoProof()
    {
        using var device = DeviceIdentity.CreateEphemeral();
        await using (var mac = new FakeMac(Code, (_, _) => new PairResult(false, Reason: PairResult.Shown)))
        {
            var (answer, key) = await PairingClient.AskAsync("127.0.0.1", mac.Port, device, "PC", "Windows", Soon);
            Assert.Equal(PairResult.Shown, answer!.Reason);
            Assert.Equal(mac.Key.Fingerprint, key);
            var sent = JsonSerializer.Deserialize<PairRequest>((await mac.Served)!)!;
            Assert.Equal(("ask", ""), (sent.Method, sent.Proof));
        }
        await using (var mac = new FakeMac(Code, (_, _) => new PairResult(false, Reason: PairResult.Closed)))
        {
            var (answer, _) = await PairingClient.CancelAskAsync("127.0.0.1", mac.Port, device, mac.Key.Fingerprint, "PC", "Windows", Soon);
            Assert.Equal(PairResult.Closed, answer!.Reason);
            Assert.Equal(("cancel", ""), JsonSerializer.Deserialize<PairRequest>((await mac.Served)!)! is var r ? (r.Method, r.Proof) : default);
        }
    }

    [Fact]
    public void TheDeviceIdentityKeepsItsKeyAcrossLoads()
    {
        string dir = Path.Combine(Path.GetTempPath(), "sill-identity-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var first = DeviceIdentity.LoadOrCreate(dir);
            using var again = DeviceIdentity.LoadOrCreate(dir);
            Assert.Equal(first.Fingerprint, again.Fingerprint);
            Assert.True(first.Certificate.HasPrivateKey);
            using var key = first.Certificate.GetECDsaPublicKey()!;
            Assert.Equal(Spki.Fingerprint(key), first.Fingerprint);
        }
        finally { Directory.Delete(dir, recursive: true); }
    }
}
