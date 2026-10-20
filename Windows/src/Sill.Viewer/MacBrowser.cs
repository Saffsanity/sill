using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The Macs on this network, through Windows' own DNS-SD (dnsapi.dll's <c>DnsServiceBrowse</c> and
/// <c>DnsServiceResolve</c>, Windows 10 1809 and later; no Bonjour install): a continuous browse of
/// one service type, each instance resolved to its host, port, addresses and TXT entries, the link
/// from the interface the answer came in on. An instance that says goodbye (its PTR record with a
/// TTL of 0) leaves the list. <see cref="Changed"/> fires on a thread of the system's with the
/// whole list. One browser per service type.
/// </summary>
sealed class MacBrowser : IDisposable
{
    /// <summary>The whole list each time it changes, on a thread of the system's.</summary>
    public event Action<IReadOnlyList<FoundService>>? Changed;
    /// <summary>A line for viewer.log.</summary>
    public event Action<string>? Log;

    public string ServiceType { get; }
    private readonly Lock gate = new();
    private readonly Dictionary<string, FoundService> found = new(StringComparer.OrdinalIgnoreCase);   // by full instance name
    private readonly HashSet<string> resolving = new(StringComparer.OrdinalIgnoreCase);
    private readonly IntPtr queryName, cancel;
    private GCHandle self;
    private volatile bool disposed;

    public MacBrowser(string serviceType)
    {
        ServiceType = serviceType;
        self = GCHandle.Alloc(this);
        queryName = Marshal.StringToHGlobalUni(serviceType + ".local");
        cancel = Marshal.AllocHGlobal(IntPtr.Size);
        Marshal.WriteIntPtr(cancel, IntPtr.Zero);
    }

    /// <summary>Starts browsing; throws when Windows has no DNS-SD (before 1809) or refuses.</summary>
    public void Start()
    {
        var request = new BrowseRequest
        {
            Version = 1,   // DNS_QUERY_REQUEST_VERSION1: the callback gets each answer's records
            InterfaceIndex = 0,
            QueryName = queryName,
            Callback = Marshal.GetFunctionPointerForDelegate(BrowseDone),
            Context = GCHandle.ToIntPtr(self),
        };
        int status;
        try { status = DnsServiceBrowse(ref request, cancel); }
        catch (EntryPointNotFoundException) { throw new PlatformNotSupportedException("Windows has no DNS-SD before Windows 10 1809."); }
        if (status != DnsRequestPending) throw new InvalidOperationException($"DnsServiceBrowse failed ({status}).");
        Log?.Invoke($"Browse: looking for {ServiceType}.");
    }

    public IReadOnlyList<FoundService> Current { get { lock (gate) return [.. found.Values]; } }

    // ---- browsing ----

    private static readonly BrowseCallback BrowseDone = OnBrowse;
    private static readonly ResolveCallback ResolveDone = OnResolve;

    private static void OnBrowse(uint status, IntPtr context, IntPtr records)
    {
        if (GCHandle.FromIntPtr(context).Target is not MacBrowser b) return;
        try
        {
            if (status != 0) { b.Log?.Invoke($"Browse: {b.ServiceType} answered status {status}."); return; }
            for (var r = records; r != IntPtr.Zero;)
            {
                var record = Marshal.PtrToStructure<RecordHeader>(r);
                if (record.Type == TypePtr && record.Data0 != IntPtr.Zero && Marshal.PtrToStringUni(record.Data0) is { } instance)
                    b.Answer(instance, record.Ttl);
                r = record.Next;
            }
        }
        catch (Exception e) { b.Log?.Invoke($"Browse: {e.Message}"); }
        finally { if (records != IntPtr.Zero) DnsRecordListFree(records, 1 /* DnsFreeRecordList */); }
    }

    private void Answer(string instance, uint ttl)
    {
        if (disposed) return;
        if (ttl == 0)
        {
            bool gone;
            lock (gate) gone = found.Remove(instance);
            Log?.Invoke($"Browse: {instance} said goodbye{(gone ? "" : " (not listed)")}.");
            if (gone) Changed?.Invoke(Current);
            return;
        }
        // A new instance, or one announcing itself again (a relaunch: a new port, a new tag): resolve it.
        lock (gate) if (!resolving.Add(instance)) return;
        Resolve(instance);
    }

    private void Resolve(string instance)
    {
        var op = new ResolveOp(this, instance);
        var request = new ResolveRequest
        {
            Version = 1,
            InterfaceIndex = 0,
            QueryName = op.Name,
            Callback = Marshal.GetFunctionPointerForDelegate(ResolveDone),
            Context = GCHandle.ToIntPtr(op.Handle),
        };
        int status = DnsServiceResolve(ref request, op.Cancel);
        if (status != DnsRequestPending)
        {
            Log?.Invoke($"Browse: couldn’t resolve {instance} ({status}).");
            op.Free();
            lock (gate) resolving.Remove(instance);
        }
    }

    private static void OnResolve(uint status, IntPtr context, IntPtr instance)
    {
        var handle = GCHandle.FromIntPtr(context);
        if (handle.Target is not ResolveOp op) return;
        var b = op.Browser;
        try
        {
            lock (b.gate) b.resolving.Remove(op.Instance);
            if (b.disposed) return;
            if (status != 0 || instance == IntPtr.Zero) { b.Log?.Invoke($"Browse: resolving {op.Instance} answered status {status}."); return; }
            var service = b.Read(Marshal.PtrToStructure<ServiceInstance>(instance), op.Instance);
            if (service is null) return;
            bool changed;
            lock (b.gate)
            {
                changed = !b.found.TryGetValue(op.Instance, out var old) || !Same(old, service);
                b.found[op.Instance] = service;
            }
            if (changed)
            {
                b.Log?.Invoke($"Browse: {service.Name} ({service.ServiceType}) at {service.Host} port {service.Port}, "
                    + $"{string.Join(", ", service.Addresses)}, {service.Link?.ToString() ?? "no link word"}, "
                    + $"TXT {string.Join(" ", service.Txt.Select(t => t.Value is null ? t.Key : $"{t.Key}={t.Value}"))}.");
                b.Changed?.Invoke(b.Current);
            }
        }
        catch (Exception e) { b.Log?.Invoke($"Browse: resolving {op.Instance}: {e.Message}"); }
        finally
        {
            if (instance != IntPtr.Zero) DnsServiceFreeInstance(instance);
            op.Free();
        }
    }

    private static bool Same(FoundService a, FoundService b) =>
        a.Host == b.Host && a.Port == b.Port && a.Link == b.Link && a.Addresses.SequenceEqual(b.Addresses)
        && a.Txt.Count == b.Txt.Count && a.Txt.All(t => b.Txt.TryGetValue(t.Key, out var v) && v == t.Value);

    private FoundService? Read(ServiceInstance s, string fullName)
    {
        string name = DnsSdName.Instance(fullName, ServiceType) ?? fullName;
        string host = s.HostName == IntPtr.Zero ? "" : Marshal.PtrToStringUni(s.HostName) ?? "";
        var addresses = new List<string>();
        if (s.Ip4 != IntPtr.Zero)
        {
            var v4 = new IPAddress((uint)Marshal.ReadInt32(s.Ip4));   // network order, as IPAddress(long) takes it
            if (!v4.Equals(IPAddress.Any)) addresses.Add(v4.ToString());
        }
        if (s.Ip6 != IntPtr.Zero)
        {
            var bytes = new byte[16];
            Marshal.Copy(s.Ip6, bytes, 0, 16);
            var v6 = new IPAddress(bytes);
            if (!v6.Equals(IPAddress.IPv6Any))
            {
                if (v6.IsIPv6LinkLocal) v6.ScopeId = s.InterfaceIndex;
                addresses.Add(v6.ToString());
            }
        }
        var txt = new Dictionary<string, string?>(StringComparer.Ordinal);
        for (int i = 0; i < s.PropertyCount; i++)
        {
            var k = Marshal.ReadIntPtr(s.Keys, i * IntPtr.Size);
            var v = s.Values == IntPtr.Zero ? IntPtr.Zero : Marshal.ReadIntPtr(s.Values, i * IntPtr.Size);
            if (k == IntPtr.Zero || Marshal.PtrToStringUni(k) is not { Length: > 0 } key) continue;
            txt.TryAdd(key, v == IntPtr.Zero ? null : Marshal.PtrToStringUni(v));
        }
        return new FoundService(ServiceType, name, host, s.Port, addresses, txt, LinkOf(s.InterfaceIndex, addresses));
    }

    /// <summary>Wired or Wi‑Fi: the interface the answer came in on, else the one whose subnet holds
    /// the Mac's IPv4 address. A virtual or tunnel interface says nothing.</summary>
    internal static MacLink? LinkOf(uint index, IReadOnlyList<string> addresses)
    {
        NetworkInterface[] all;
        try { all = NetworkInterface.GetAllNetworkInterfaces(); } catch (NetworkInformationException) { return null; }
        NetworkInterface? match = null;
        if (index != 0)
            match = all.FirstOrDefault(ni => IndexOf(ni, NetworkInterfaceComponent.IPv4) == index || IndexOf(ni, NetworkInterfaceComponent.IPv6) == index);
        if (match is null && addresses.Select(a => IPAddress.TryParse(a, out var ip) ? ip : null)
                .FirstOrDefault(ip => ip?.AddressFamily == AddressFamily.InterNetwork) is { } v4)
            match = all.FirstOrDefault(ni => ni.OperationalStatus == OperationalStatus.Up && ni.GetIPProperties().UnicastAddresses
                .Any(u => u.Address.AddressFamily == AddressFamily.InterNetwork && SameSubnet(u.Address, v4, u.IPv4Mask)));
        if (match is null || match.Description.Contains("Virtual", StringComparison.OrdinalIgnoreCase)) return null;
        return match.NetworkInterfaceType switch
        {
            NetworkInterfaceType.Wireless80211 => MacLink.WiFi,
            NetworkInterfaceType.Ethernet or NetworkInterfaceType.GigabitEthernet or NetworkInterfaceType.FastEthernetT
                or NetworkInterfaceType.FastEthernetFx or NetworkInterfaceType.Ethernet3Megabit => MacLink.Wired,
            _ => null,
        };
    }

    private static int? IndexOf(NetworkInterface ni, NetworkInterfaceComponent family)
    {
        try
        {
            if (!ni.Supports(family)) return null;
            var p = ni.GetIPProperties();
            return family == NetworkInterfaceComponent.IPv4 ? p.GetIPv4Properties()?.Index : p.GetIPv6Properties()?.Index;
        }
        catch (NetworkInformationException) { return null; }
    }

    private static bool SameSubnet(IPAddress a, IPAddress b, IPAddress? mask)
    {
        if (mask is null) return false;
        var x = a.GetAddressBytes(); var y = b.GetAddressBytes(); var m = mask.GetAddressBytes();
        for (int i = 0; i < 4; i++) if ((x[i] & m[i]) != (y[i] & m[i])) return false;
        return true;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        try { DnsServiceBrowseCancel(cancel); } catch (EntryPointNotFoundException) { }
        // The query name, the cancel handle and this object's handle stay: a callback already under
        // way may still read them (a few bytes, once per browser).
    }

    /// <summary>One resolve's own memory, kept until its callback has run.</summary>
    private sealed class ResolveOp
    {
        public readonly MacBrowser Browser;
        public readonly string Instance;
        public readonly IntPtr Name, Cancel;
        public GCHandle Handle;

        public ResolveOp(MacBrowser browser, string instance)
        {
            Browser = browser; Instance = instance;
            Name = Marshal.StringToHGlobalUni(instance);
            Cancel = Marshal.AllocHGlobal(IntPtr.Size);
            Marshal.WriteIntPtr(Cancel, IntPtr.Zero);
            Handle = GCHandle.Alloc(this);
        }

        public void Free()
        {
            if (!Handle.IsAllocated) return;
            Handle.Free();
            Marshal.FreeHGlobal(Name);
            Marshal.FreeHGlobal(Cancel);
        }
    }

    // ---- dnsapi.dll (windns.h) ----

    private const int DnsRequestPending = 9506;   // DNS_REQUEST_PENDING
    private const ushort TypePtr = 12;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void BrowseCallback(uint status, IntPtr context, IntPtr records);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void ResolveCallback(uint status, IntPtr context, IntPtr instance);

    [StructLayout(LayoutKind.Sequential)]
    private struct BrowseRequest { public uint Version, InterfaceIndex; public IntPtr QueryName, Callback, Context; }

    [StructLayout(LayoutKind.Sequential)]
    private struct ResolveRequest { public uint Version, InterfaceIndex; public IntPtr QueryName, Callback, Context; }

    /// <summary>DNS_RECORDW up to the first pointer of its data (a PTR's <c>pNameHost</c>).</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct RecordHeader
    {
        public IntPtr Next, Name;
        public ushort Type, DataLength;
        public uint Flags, Ttl, Reserved;
        public IntPtr Data0;
    }

    /// <summary>DNS_SERVICE_INSTANCE.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct ServiceInstance
    {
        public IntPtr InstanceName, HostName, Ip4, Ip6;
        public ushort Port, Priority, Weight;
        public uint PropertyCount;
        public IntPtr Keys, Values;
        public uint InterfaceIndex;
    }

    [DllImport("dnsapi.dll")] private static extern int DnsServiceBrowse(ref BrowseRequest request, IntPtr cancel);
    [DllImport("dnsapi.dll")] private static extern int DnsServiceBrowseCancel(IntPtr cancel);
    [DllImport("dnsapi.dll")] private static extern int DnsServiceResolve(ref ResolveRequest request, IntPtr cancel);
    [DllImport("dnsapi.dll")] private static extern void DnsServiceFreeInstance(IntPtr instance);
    [DllImport("dnsapi.dll")] private static extern void DnsRecordListFree(IntPtr records, int freeType);
}
