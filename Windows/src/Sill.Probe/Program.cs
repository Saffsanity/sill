// Ticket 02's probe (Windows/PROGRESS.md): what the spike needs from this Windows PC.
//
//   dotnet run --project Windows/src/Sill.Probe [-- --host <mac-address>:<port>]
//
// 1. The OS: version, build and display version.
// 2. TLS 1.3 with ALPN, both ends holding self-signed P-256 keys as Sill's doors do, over
//    loopback inside this process (SChannel as client and as server).
// 3. Media Foundation's HEVC decoders: how many, and how many in hardware. None means
//    HEVC Video Extensions is missing.
// 4. With --host: a TLS 1.3 handshake to a Mac's door (`SillHost --pairing`), offering
//    `sill-pair/1`; it prints what was negotiated and the Mac's SPKI SHA-256, then closes
//    without sending anything.
//
// The report is printed and written to probe-report.txt in the current directory.

using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

var report = new StringBuilder();
void Line(string s) { Console.WriteLine(s); report.AppendLine(s); }

string? host = null;
for (int i = 0; i < args.Length; i++)
    if (args[i] == "--host" && i + 1 < args.Length) host = args[++i];

Line($"Sill Windows probe, {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
Line("");
Line("== OS");
Line($"OS: {RuntimeInformation.OSDescription}");
Line($"Version: {Environment.OSVersion.Version}");
Line($"Architecture: {RuntimeInformation.OSArchitecture}");
Line($".NET: {RuntimeInformation.FrameworkDescription}");
if (OperatingSystem.IsWindows())
{
    using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
    Line($"Product: {key?.GetValue("ProductName")}, {key?.GetValue("DisplayVersion")}, build {key?.GetValue("CurrentBuild")}.{key?.GetValue("UBR")}");
    // ProductName still says "Windows 10" on Windows 11: build 22000 or later is 11.
    Line($"Windows 11 by build: {Environment.OSVersion.Version.Build >= 22000}");
}
else
{
    Line("Not Windows: the TLS result below is this OS's, and the decoder check is skipped.");
}

Line("");
Line("== TLS 1.3 with ALPN over loopback (both ends P-256, mutual)");
try { await LoopbackTls(Line); }
catch (Exception e) { Line($"FAIL: {Describe(e)}"); }

Line("");
Line("== Media Foundation HEVC decoders");
if (OperatingSystem.IsWindows())
{
    try { HevcDecoders(Line); }
    catch (Exception e) { Line($"FAIL: {Describe(e)}"); }
}
else Line("Skipped (not Windows).");

if (host != null)
{
    Line("");
    Line($"== TLS 1.3 handshake to the Mac at {host}");
    try { await MacHandshake(host, Line); }
    catch (Exception e) { Line($"FAIL: {Describe(e)}"); }
}

File.WriteAllText("probe-report.txt", report.ToString());
Console.WriteLine();
Console.WriteLine($"Written to {Path.GetFullPath("probe-report.txt")}");
return 0;

static string Describe(Exception e) =>
    e.InnerException == null ? $"{e.GetType().Name}: {e.Message}"
        : $"{e.GetType().Name}: {e.Message} ({Describe(e.InnerException)})";

// A self-signed P-256 certificate, as Sill's identities are. SChannel cannot use a key that
// exists only in memory, so it goes through a PKCS #12 round trip first.
static X509Certificate2 SelfSigned(string name)
{
    using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    var request = new CertificateRequest($"CN={name}", key, HashAlgorithmName.SHA256);
    using var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(1));
    return X509CertificateLoader.LoadPkcs12(cert.Export(X509ContentType.Pkcs12), null);
}

// SHA-256 of the DER SubjectPublicKeyInfo, Sill's pin (RemoteIdentity.swift).
static string SpkiSha256(X509Certificate cert)
{
    using var c = new X509Certificate2(cert);
    byte[] spki = c.PublicKey.ExportSubjectPublicKeyInfo();
    return Convert.ToHexString(SHA256.HashData(spki)).ToLowerInvariant();
}

static async Task LoopbackTls(Action<string> line)
{
    using var serverCert = SelfSigned("sill-probe-mac");
    using var clientCert = SelfSigned("sill-probe-device");
    var listener = new TcpListener(IPAddress.Loopback, 0);
    listener.Start();
    int port = ((IPEndPoint)listener.LocalEndpoint).Port;
    string? clientSawServer = null, serverSawClient = null;

    var serverTask = Task.Run(async () =>
    {
        using var tcp = await listener.AcceptTcpClientAsync();
        using var ssl = new SslStream(tcp.GetStream());
        await ssl.AuthenticateAsServerAsync(new SslServerAuthenticationOptions
        {
            ServerCertificate = serverCert,
            ClientCertificateRequired = true,
            EnabledSslProtocols = SslProtocols.Tls13,
            ApplicationProtocols = [new SslApplicationProtocol("sill/1"), new SslApplicationProtocol("sill-pair/1")],
            RemoteCertificateValidationCallback = (_, cert, _, _) =>
            {
                serverSawClient = cert == null ? null : SpkiSha256(cert);
                return cert != null;
            },
        });
    });

    using (var tcp = new TcpClient())
    {
        await tcp.ConnectAsync(IPAddress.Loopback, port);
        using var ssl = new SslStream(tcp.GetStream());
        await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
        {
            TargetHost = "sill",
            ClientCertificates = [clientCert],
            EnabledSslProtocols = SslProtocols.Tls13,
            ApplicationProtocols = [new SslApplicationProtocol("sill-pair/1")],
            RemoteCertificateValidationCallback = (_, cert, _, _) =>
            {
                clientSawServer = cert == null ? null : SpkiSha256(cert);
                return cert != null;
            },
        });
        line($"Protocol: {ssl.SslProtocol}, ALPN: {ssl.NegotiatedApplicationProtocol}, cipher: {ssl.NegotiatedCipherSuite}");
        line($"Client saw the server's key: {clientSawServer == SpkiSha256(serverCert)}");
        bool ok = ssl.SslProtocol == SslProtocols.Tls13 && ssl.NegotiatedApplicationProtocol.ToString() == "sill-pair/1";
        await serverTask;
        line($"Server saw the client's key: {serverSawClient == SpkiSha256(clientCert)}");
        line(ok ? "PASS" : "FAIL: not TLS 1.3 with sill-pair/1");
    }
    listener.Stop();
}

static async Task MacHandshake(string hostPort, Action<string> line)
{
    int colon = hostPort.LastIndexOf(':');
    if (colon <= 0) throw new ArgumentException("--host takes address:port");
    string address = hostPort[..colon].Trim('[', ']');
    int port = int.Parse(hostPort[(colon + 1)..]);
    using var clientCert = SelfSigned("sill-probe-device");
    using var tcp = new TcpClient();
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
    await tcp.ConnectAsync(address, port, cts.Token);
    using var ssl = new SslStream(tcp.GetStream());
    string? macKey = null;
    await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
    {
        TargetHost = "sill",
        ClientCertificates = [clientCert],
        EnabledSslProtocols = SslProtocols.Tls13,
        ApplicationProtocols = [new SslApplicationProtocol("sill-pair/1")],
        // Sill trusts by pinned key, never by name or chain: record the key, accept it.
        RemoteCertificateValidationCallback = (_, cert, _, _) =>
        {
            macKey = cert == null ? null : SpkiSha256(cert);
            return cert != null;
        },
    }, cts.Token);
    line($"Protocol: {ssl.SslProtocol}, ALPN: {ssl.NegotiatedApplicationProtocol}, cipher: {ssl.NegotiatedCipherSuite}");
    line($"Mac's SPKI SHA-256: {macKey}");
    line(ssl.SslProtocol == SslProtocols.Tls13 && ssl.NegotiatedApplicationProtocol.ToString() == "sill-pair/1"
        ? "PASS" : "FAIL: not TLS 1.3 with sill-pair/1");
}

static void HevcDecoders(Action<string> line)
{
    Mf.Check(Mf.MFStartup(Mf.Version, 0), "MFStartup");
    try
    {
        int all = Mf.CountDecoders(Mf.EnumAll | Mf.EnumSortAndFilter);
        int hardware = Mf.CountDecoders(Mf.EnumHardware | Mf.EnumSortAndFilter);
        line($"HEVC decoders: {all}, in hardware: {hardware}");
        line(all > 0 ? "PASS" : "FAIL: no HEVC decoder; install HEVC Video Extensions from the Microsoft Store");
    }
    finally { Mf.MFShutdown(); }
}

static class Mf
{
    public const uint Version = 0x00020070;          // MF_VERSION
    public const uint EnumHardware = 0x04;           // MFT_ENUM_FLAG_HARDWARE
    public const uint EnumAll = 0x3F;                // MFT_ENUM_FLAG_ALL
    public const uint EnumSortAndFilter = 0x40;      // MFT_ENUM_FLAG_SORTANDFILTER

    static readonly Guid VideoDecoderCategory = new("d6c02d4b-6833-45b4-971a-05a4b04bab91");
    static readonly Guid MediaTypeVideo = new("73646976-0000-0010-8000-00aa00389b71");
    static readonly Guid VideoFormatHevc = new("43564548-0000-0010-8000-00aa00389b71");

    [StructLayout(LayoutKind.Sequential)]
    struct RegisterTypeInfo { public Guid Major; public Guid Sub; }

    [DllImport("mfplat.dll")] public static extern int MFStartup(uint version, uint flags);
    [DllImport("mfplat.dll")] public static extern int MFShutdown();
    [DllImport("mfplat.dll")]
    static extern int MFTEnumEx(Guid category, uint flags, ref RegisterTypeInfo input, IntPtr output,
        out IntPtr activates, out uint count);

    public static int CountDecoders(uint flags)
    {
        var input = new RegisterTypeInfo { Major = MediaTypeVideo, Sub = VideoFormatHevc };
        Check(MFTEnumEx(VideoDecoderCategory, flags, ref input, IntPtr.Zero, out IntPtr array, out uint count), "MFTEnumEx");
        for (int i = 0; i < count; i++)
            Marshal.Release(Marshal.ReadIntPtr(array, i * IntPtr.Size));
        Marshal.FreeCoTaskMem(array);
        return (int)count;
    }

    public static void Check(int hr, string what)
    {
        if (hr < 0) throw new COMException($"{what} failed", hr);
    }
}
