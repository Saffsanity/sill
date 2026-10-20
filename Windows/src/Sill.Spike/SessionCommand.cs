using System.Diagnostics;
using System.Text.Json;
using Sill.Protocol;

/// <summary>
/// Ticket 04: a session to the Mac saved by <c>pair</c>, as the iOS device opens one: TLS
/// pinned to the Mac's key, the hello first, the Desktop asked for once the Mac says nothing
/// streams, pings once a second, and every message read; the stream's parameter sets and frames
/// logged with their sizes and NAL units, anything else counted and skipped.
/// </summary>
static class SessionCommand
{
    public static async Task<int> RunAsync(Dictionary<string, string> opts, string dir, string name)
    {
        // The newest saved Mac (macs.json; a spike's mac.json is taken in on the way).
        var mac = SavedMacs.Newest(new SavedMacsFile(dir).Load());
        if (mac?.Pin is not { } pin) return Spike.Usage($"No paired Mac in {Path.Combine(dir, SavedMacsFile.FileName)}: run pair first.");
        if (!double.TryParse(opts.GetValueOrDefault("seconds") ?? "10", out double seconds) || seconds <= 0)
            return Spike.Usage("--seconds takes a number of seconds.");
        string host = mac.Host; int port = mac.Port;
        if (opts.GetValueOrDefault("host") is { } hostArg && !Spike.SplitHost(hostArg, out host, out port))
            return Spike.Usage("--host takes <address>:<port>.");
        string? saveDir = opts.GetValueOrDefault("save"), pngPath = opts.GetValueOrDefault("png");
        if (pngPath is not null && !OperatingSystem.IsWindows()) return Spike.Usage("--png decodes with Media Foundation: Windows only.");
        byte[]? firstKeyframe = null;
        bool decodeAll = opts.ContainsKey("decode") && OperatingSystem.IsWindows();
        var decodeTimes = new List<double>();
        int pictures = 0;
        bool keyed = false;   // nothing decodes before the first keyframe
        Sill.Media.HevcDecoder? decoder = null;
        // --gpu 1: decode on the GPU (Direct3D 11, DXVA) and time each frame until the GPU has
        // finished it; --adapter N picks DXGI's Nth adapter (0 drives the display).
        Sill.Media.GpuDevice? gpu = null;
        if (decodeAll && opts.ContainsKey("gpu") && OperatingSystem.IsWindows())
        {
            int? adapter = opts.GetValueOrDefault("adapter") is { } a && int.TryParse(a, out int n) ? n : null;
            gpu = new Sill.Media.GpuDevice(adapter);
            Console.WriteLine($"Decoding on the GPU: {gpu.AdapterName}.");
        }
        var cpuAtStart = System.Diagnostics.Process.GetCurrentProcess().TotalProcessorTime;

        using var identity = DeviceIdentity.LoadOrCreate(dir);
        Console.WriteLine($"Connecting to {mac.Name} at {host}:{port}, pinned to {mac.Fingerprint[..10]}…");
        using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(seconds + 10));
        var clock = Stopwatch.StartNew();
        double Now() => clock.Elapsed.TotalSeconds;

        SessionClient session;
        try
        {
            var hello = new Hello("0.1", "spike", Hello.CurrentProtocol, $"{name} (Windows)");
            session = await SessionClient.ConnectAsync(host, port, identity, pin, hello, stop.Token);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"Couldn’t connect: {e.Message}");
            return 3;
        }

        await using var _ = session;
        Console.WriteLine($"[{Now():0.00}s] TLS 1.3 with sill/1, pinned; hello sent.");
        var stats = new Stats();
        using var ticker = new CancellationTokenSource();
        var pinging = PingAsync(session, stats, name, Now, ticker.Token);

        ParameterSets? parameterSets = null;
        bool asked = false;
        string? lastActive = null;
        try
        {
            using var run = CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
            run.CancelAfter(TimeSpan.FromSeconds(seconds));
            while (true)
            {
                (StreamHeader Header, byte[] Payload)? message;
                try { message = await session.ReadAsync(run.Token); }
                catch (OperationCanceledException) when (!stop.IsCancellationRequested) { break; }
                if (message is not { } m) { Console.WriteLine($"[{Now():0.00}s] The Mac closed the session."); break; }
                var (h, payload) = m;
                switch (h.Kind)
                {
                    case SessionKinds.WindowList:
                        var list = SessionMessages.Decode<WindowList>(payload);
                        if (list is null) { stats.Count("windowList (undecodable)"); break; }
                        stats.Count("windowList");
                        if (list.ActiveName != lastActive)
                        {
                            lastActive = list.ActiveName;
                            Console.WriteLine($"[{Now():0.00}s] Window list from {list.MacName}: {list.Windows.Count} windows, streaming {list.ActiveName}"
                                + $" (Sill {list.HostVersion ?? "CLI"}, protocol {list.Protocol?.ToString() ?? "?"}).");
                        }
                        // The device asks for the Desktop whenever the Mac reports nothing streaming.
                        if (list.ActiveName == "none" && !asked)
                        {
                            asked = true;
                            await session.SendAsync(SessionMessages.SelectDesktop(), stop.Token);
                            Console.WriteLine($"[{Now():0.00}s] Asked for the Desktop.");
                        }
                        break;
                    case SessionKinds.ParameterSets:
                        parameterSets = ParameterSets.Parse(payload);
                        if (parameterSets is null) { Console.WriteLine($"[{Now():0.00}s] Parameter sets: malformed ({payload.Length} B)."); break; }
                        stats.ParameterSets++;
                        if (decodeAll && OperatingSystem.IsWindows()
                            && parameterSets.Sets.Select(x => HevcSps.Parse(x)).FirstOrDefault(x => x is not null) is { } sps
                            && (decoder is null || decoder.Sps != sps))
                        {
                            decoder?.Dispose();
                            decoder = new Sill.Media.HevcDecoder(sps, gpu: gpu);
                            keyed = false;
                        }
                        Console.WriteLine($"[{Now():0.00}s] Parameter sets, {payload.Length} B: NAL length {parameterSets.NalUnitHeaderLength}, "
                            + string.Join(", ", parameterSets.Sets.Select(s => $"{AccessUnit.NalName(AccessUnit.NalType(s))} {s.Length} B")));
                        break;
                    case SessionKinds.Frame:
                        int nalLen = parameterSets?.NalUnitHeaderLength ?? 4;
                        var nals = AccessUnit.Nals(payload, nalLen);
                        stats.Frame(payload.Length, h.IsKeyframe, nals is null);
                        if (h.IsKeyframe || stats.Frames <= 3 || nals is null)
                        {
                            string units = nals is null ? "malformed (a length runs past the end)"
                                : string.Join(", ", nals.GroupBy(n => AccessUnit.NalName(AccessUnit.NalType(payload.AsSpan(n.Offset, n.Length))))
                                                        .Select(g => g.Count() == 1 ? g.Key : $"{g.Count()}× {g.Key}"));
                            Console.WriteLine($"[{Now():0.00}s] {(h.IsKeyframe ? "Keyframe" : "Frame")} {stats.Frames}: {payload.Length:N0} B, {units}"
                                + (parameterSets is null ? " (before any parameter sets)" : ""));
                        }
                        if (decoder is not null && nals is not null && parameterSets is not null && (keyed || h.IsKeyframe) && OperatingSystem.IsWindows())
                        {
                            keyed = true;
                            var t0 = Stopwatch.GetTimestamp();
                            var unit = AnnexB.Build(h.IsKeyframe ? parameterSets : null, payload, nals);
                            if (gpu is not null)
                            {
                                using var picture = decoder.PushGpu(unit);
                                gpu.WaitForIdle();
                                if (picture is not null) pictures++;
                            }
                            else if (decoder.Push(unit) is not null) pictures++;
                            decodeTimes.Add(Stopwatch.GetElapsedTime(t0).TotalMilliseconds);
                        }
                        if (firstKeyframe is null && h.IsKeyframe && parameterSets is not null && nals is not null)
                        {
                            firstKeyframe = AnnexB.Build(parameterSets, payload, nals);
                            if (saveDir is not null) Save(saveDir, parameterSets, payload, firstKeyframe);
                        }
                        break;
                    case SessionKinds.Pong:
                        stats.Pong(Now() - SessionMessages.PongTime(payload));
                        break;
                    case SessionKinds.Goodbye:
                        var bye = SessionMessages.Decode<Goodbye>(payload);
                        Console.WriteLine($"[{Now():0.00}s] Goodbye from the Mac: {bye?.Reason ?? "?"}"
                            + (bye?.Message is { } said ? $": {SafeText.Label(said, 300)}" : ""));
                        break;
                    default:
                        stats.Count(Kind(h.Kind));
                        break;
                }
            }
        }
        catch (Exception e) when (e is IOException or InvalidDataException or EndOfStreamException)
        {
            Console.WriteLine($"[{Now():0.00}s] The session ended: {e.Message}");
        }
        finally
        {
            ticker.Cancel();
            try { await pinging; } catch (OperationCanceledException) { }
        }

        Console.WriteLine();
        Console.WriteLine(stats.Summary(Now()));
        if (decodeTimes.Count > 0)
        {
            decodeTimes.Sort();
            Console.WriteLine($"Decoded {decodeTimes.Count} frames to {pictures} pictures: median {decodeTimes[decodeTimes.Count / 2]:0.0} ms, "
                + $"95th {decodeTimes[(int)(decodeTimes.Count * 0.95)]:0.0} ms, worst {decodeTimes[^1]:0.0} ms a frame"
                + $" ({(gpu is null ? "software" : "GPU: " + gpu.AdapterName)}).");
            double cpu = (System.Diagnostics.Process.GetCurrentProcess().TotalProcessorTime - cpuAtStart).TotalSeconds;
            Console.WriteLine($"CPU: {cpu:0.0} s in {Now():0.0} s, {cpu / Now() * 100:0}% of one core.");
        }
        if (OperatingSystem.IsWindows()) { decoder?.Dispose(); gpu?.Dispose(); }
        if (pngPath is not null && firstKeyframe is not null && OperatingSystem.IsWindows())
            return DecodeCommand.ToPng(firstKeyframe, pngPath);
        return stats.Keyframes > 0 ? 0 : 1;
    }

    private static string Kind(byte kind) => kind switch
    {
        3 => "thumbnail", 4 => "appIcon", 5 => "appList", 13 => "tick", 14 => "cursorShape", 16 => "hostSettings",
        18 => "macInfo", 24 => "macMenu", 26 => "macPointer", 32 => "clipboard", _ => $"kind {kind}",
    };

    // Once a second: a ping (its pong gives the round trip), the second's line, and ClientStats
    // (kind 12) so the Mac's log names this client. Frame age stays -1: the Mac's clock is not
    // this PC's, so a host timestamp's age means nothing here.
    private static async Task PingAsync(SessionClient session, Stats stats, string name, Func<double> now, CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        await session.SendAsync(SessionMessages.Ping(now()), ct);
        while (await timer.WaitForNextTickAsync(ct))
        {
            var second = stats.CloseSecond();
            Console.WriteLine($"[{now():0.00}s] {second.Frames} frames, {second.Bytes / 1024.0:N0} KB, {second.Keyframes} key"
                + (second.Rtt is { } rtt ? $", rtt {rtt * 1000:0} ms" : ""));
            var payload = JsonSerializer.SerializeToUtf8Bytes(new { fps = second.Frames, frameAgeMs = -1, rttMs = (int)((second.Rtt ?? -0.001) * 1000), device = $"{name} (Windows)" });
            await session.SendAsync(StreamHeader.Serialize(SessionKinds.ClientStats, 0, false, payload), ct);
            await session.SendAsync(SessionMessages.Ping(now()), ct);
        }
    }

    // What ticket 05 decodes: the kind 0 and kind 1 payloads as they came, and the same access
    // unit as an Annex B elementary stream (start codes, the parameter sets first), which any
    // HEVC tool reads (ffprobe, ffmpeg -i first-keyframe.h265 frame.png).
    private static void Save(string dir, ParameterSets ps, byte[] frame, byte[] annexB)
    {
        Directory.CreateDirectory(dir);
        File.WriteAllBytes(Path.Combine(dir, "parameter-sets.bin"), ps.Encode());
        File.WriteAllBytes(Path.Combine(dir, "first-keyframe.bin"), frame);
        File.WriteAllBytes(Path.Combine(dir, "first-keyframe.h265"), annexB);
        Console.WriteLine($"Saved the first keyframe to {Path.GetFullPath(dir)} (parameter-sets.bin, first-keyframe.bin, first-keyframe.h265).");
    }

    private sealed class Stats
    {
        private readonly Lock gate = new();
        private readonly Dictionary<string, int> other = [];
        private int secondFrames, secondKeys; private long secondBytes; private double? secondRtt;
        public int Frames, Keyframes, Malformed, ParameterSets; public long Bytes; public int Seconds;

        public void Frame(int bytes, bool key, bool malformed)
        {
            lock (gate)
            {
                Frames++; Bytes += bytes; secondFrames++; secondBytes += bytes;
                if (key) { Keyframes++; secondKeys++; }
                if (malformed) Malformed++;
            }
        }

        public void Pong(double rtt) { lock (gate) secondRtt = secondRtt is { } r ? Math.Max(r, rtt) : rtt; }
        public void Count(string kind) { lock (gate) other[kind] = other.GetValueOrDefault(kind) + 1; }

        public (int Frames, long Bytes, int Keyframes, double? Rtt) CloseSecond()
        {
            lock (gate)
            {
                var s = (secondFrames, secondBytes, secondKeys, secondRtt);
                secondFrames = secondKeys = 0; secondBytes = 0; secondRtt = null; Seconds++;
                return s;
            }
        }

        public string Summary(double elapsed)
        {
            lock (gate)
                return $"In {elapsed:0.0} s: {ParameterSets} parameter sets, {Frames} frames ({Keyframes} keyframes, {Malformed} malformed), "
                     + $"{Bytes / 1024.0:N0} KB, {Frames / Math.Max(elapsed, 0.001):0.0} fps.\n"
                     + $"Other messages: {(other.Count == 0 ? "none" : string.Join(", ", other.OrderBy(o => o.Key).Select(o => $"{o.Key} {o.Value}")))}.";
        }
    }
}
