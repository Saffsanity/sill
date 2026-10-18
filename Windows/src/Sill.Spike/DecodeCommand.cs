using System.Diagnostics;
using Sill.Protocol;

/// <summary>Ticket 05: one keyframe through Windows' HEVC decoder, written as a PNG.</summary>
static class DecodeCommand
{
    public static int Run(Dictionary<string, string>? opts)
    {
        if (opts?.GetValueOrDefault("input") is not { } input || opts.GetValueOrDefault("out") is not { } output)
            return Spike.Usage("Sill.Spike decode --input <first-keyframe.h265> --out <frame.png>");
        if (!OperatingSystem.IsWindows()) return Spike.Usage("decode uses Media Foundation: Windows only.");
        if (!File.Exists(input)) return Spike.Usage($"No file at {input}.");
        return ToPng(File.ReadAllBytes(input), output);
    }

    /// <summary>Annex B: each parameter set, then each of the access unit's NAL units, after a
    /// four-byte start code: what Media Foundation's HEVC decoder (and ffmpeg) read.</summary>
    public static byte[] AnnexB(ParameterSets ps, byte[] frame, List<(int Offset, int Length)> nals)
    {
        using var s = new MemoryStream();
        byte[] startCode = [0, 0, 0, 1];
        foreach (var set in ps.Sets) { s.Write(startCode); s.Write(set); }
        foreach (var (offset, length) in nals) { s.Write(startCode); s.Write(frame, offset, length); }
        return s.ToArray();
    }

    public static int ToPng(byte[] annexB, string output)
    {
        if (!OperatingSystem.IsWindows()) return Spike.Usage("Decoding uses Media Foundation: Windows only.");
        HevcSps? sps = AnnexBNals(annexB).Select(n => HevcSps.Parse(n)).FirstOrDefault(x => x is not null);
        if (sps is null) { Console.Error.WriteLine("Couldn’t decode: the input has no SPS this reader follows."); return 1; }
        Console.WriteLine($"SPS: coded {sps.CodedWidth}×{sps.CodedHeight}, shown {sps.Width}×{sps.Height}.");
        var clock = Stopwatch.StartNew();
        HevcDecoder.Picture picture;
        try { picture = HevcDecoder.Decode(annexB, sps, Console.WriteLine); }
        catch (Exception e)
        {
            Console.Error.WriteLine($"Couldn’t decode: {e.Message}");
            return 1;
        }
        double decodeMs = clock.Elapsed.TotalMilliseconds;
        // The SPS's conformance window crops what the decoder stores to what the Mac showed.
        int width = Math.Min(sps.Width, picture.Width - sps.Left), height = Math.Min(sps.Height, picture.Height - sps.Top);
        var rgb = Nv12.ToRgb(picture.Nv12, width, height, picture.Stride, picture.PlaneHeight, picture.FullRange, picture.Bt601, sps.Left, sps.Top);
        File.WriteAllBytes(output, Png.Encode(rgb, width, height));
        Console.WriteLine($"Decoded {annexB.Length:N0} B with {picture.Decoder} in {decodeMs:0} ms: {picture.Width}×{picture.Height} NV12, "
            + $"stride {picture.Stride}, {picture.PlaneHeight} rows stored, {(picture.FullRange ? "full" : "video")} range, "
            + $"BT.{(picture.Bt601 ? "601" : "709")}. Wrote {width}×{height} to {Path.GetFullPath(output)}.");
        return 0;
    }

    /// <summary>The NAL units of an Annex B stream (split at each 00 00 01, a 00 before it dropped).</summary>
    public static IEnumerable<byte[]> AnnexBNals(byte[] s)
    {
        var starts = new List<int>();
        for (int i = 0; i + 2 < s.Length; i++)
            if (s[i] == 0 && s[i + 1] == 0 && s[i + 2] == 1) { starts.Add(i + 3); i += 2; }
        for (int k = 0; k < starts.Count; k++)
        {
            int end = k + 1 < starts.Count ? starts[k + 1] - 3 : s.Length;
            while (end > starts[k] && s[end - 1] == 0) end--;
            yield return s[starts[k]..end];
        }
    }
}
