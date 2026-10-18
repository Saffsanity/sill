using System.Diagnostics;
using Sill.Media;
using Sill.Protocol;

/// <summary>Ticket 05: one keyframe through Windows' HEVC decoder, written as a PNG.</summary>
static class DecodeCommand
{
    public static int Run(Dictionary<string, string>? opts)
    {
        if (opts?.GetValueOrDefault("input") is not { } input || opts.GetValueOrDefault("out") is not { } output)
            return Spike.Usage("Sill.Spike decode --input <first-keyframe.h265> --out <frame.png> [--gpu 1 [--adapter N] [--compare 1]]");
        if (!OperatingSystem.IsWindows()) return Spike.Usage("decode uses Media Foundation: Windows only.");
        if (!File.Exists(input)) return Spike.Usage($"No file at {input}.");
        if (opts.ContainsKey("gpu"))
        {
            int? adapter = opts.GetValueOrDefault("adapter") is { } a && int.TryParse(a, out int n) ? n : null;
            return GpuToPng(File.ReadAllBytes(input), output, adapter, opts.ContainsKey("compare"));
        }
        return ToPng(File.ReadAllBytes(input), output);
    }

    // Ticket 07: the same keyframe decoded on the GPU (Direct3D 11), copied back and written as a
    // PNG; with --compare, against the software decoder's picture (PSNR and the largest difference).
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static int GpuToPng(byte[] annexB, string output, int? adapter, bool compare)
    {
        HevcSps? sps = AnnexB.Nals(annexB).Select(n => HevcSps.Parse(n)).FirstOrDefault(x => x is not null);
        if (sps is null) { Console.Error.WriteLine("Couldn’t decode: the input has no SPS this reader follows."); return 1; }
        byte[] gpuRgb; int width, height;
        try
        {
            using var gpu = new GpuDevice(adapter);
            var clock = Stopwatch.StartNew();
            using var decoder = new HevcDecoder(sps, Console.WriteLine, gpu);
            using var gpuPicture = decoder.PushGpu(annexB) ?? decoder.DrainGpu()
                ?? throw new InvalidDataException("The GPU decoder drained without a picture.");
            gpu.WaitForIdle();
            double ms = clock.Elapsed.TotalMilliseconds;
            var picture = gpu.ReadBack(gpuPicture);
            width = Math.Min(sps.Width, picture.Width - sps.Left); height = Math.Min(sps.Height, picture.Height - sps.Top);
            gpuRgb = Nv12.ToRgb(picture.Nv12, width, height, picture.Stride, picture.PlaneHeight, picture.FullRange, picture.Bt601, sps.Left, sps.Top);
            File.WriteAllBytes(output, Png.Encode(gpuRgb, width, height));
            Console.WriteLine($"Decoded {annexB.Length:N0} B on the GPU ({gpu.AdapterName}, {decoder.Name}) in {ms:0} ms (decoder made and frame done): "
                + $"texture {picture.Width}×{picture.Height}, slice {gpuPicture.ArraySlice}, row pitch {picture.Stride}, "
                + $"{(picture.FullRange ? "full" : "video")} range, BT.{(picture.Bt601 ? "601" : "709")}. Wrote {width}×{height} to {Path.GetFullPath(output)}.");
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"Couldn’t decode on the GPU: {e.Message}");
            return 1;
        }
        if (!compare) return 0;
        var (sw, _) = HevcDecoder.DecodeOne(annexB, sps);
        var swRgb = Nv12.ToRgb(sw.Nv12, width, height, sw.Stride, sw.PlaneHeight, sw.FullRange, sw.Bt601, sps.Left, sps.Top);
        double sum = 0; int worst = 0, differing = 0;
        for (int i = 0; i < swRgb.Length; i++)
        {
            int d = Math.Abs(swRgb[i] - gpuRgb[i]);
            sum += d * d; worst = Math.Max(worst, d);
            if (d > 0) differing++;
        }
        double mse = sum / swRgb.Length;
        Console.WriteLine($"Against the software decoder: {(mse == 0 ? "identical" : $"PSNR {10 * Math.Log10(255.0 * 255 / mse):0.0} dB")}, "
            + $"largest difference {worst}, {differing * 100.0 / swRgb.Length:0.00}% of samples differ.");
        return 0;
    }

    public static int ToPng(byte[] annexB, string output)
    {
        if (!OperatingSystem.IsWindows()) return Spike.Usage("Decoding uses Media Foundation: Windows only.");
        HevcSps? sps = AnnexB.Nals(annexB).Select(n => HevcSps.Parse(n)).FirstOrDefault(x => x is not null);
        if (sps is null) { Console.Error.WriteLine("Couldn’t decode: the input has no SPS this reader follows."); return 1; }
        Console.WriteLine($"SPS: coded {sps.CodedWidth}×{sps.CodedHeight}, shown {sps.Width}×{sps.Height}.");
        var clock = Stopwatch.StartNew();
        HevcDecoder.Picture picture; string decoder;
        try { (picture, decoder) = HevcDecoder.DecodeOne(annexB, sps, Console.WriteLine); }
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
        Console.WriteLine($"Decoded {annexB.Length:N0} B with {decoder} in {decodeMs:0} ms: {picture.Width}×{picture.Height} NV12, "
            + $"stride {picture.Stride}, {picture.PlaneHeight} rows stored, {(picture.FullRange ? "full" : "video")} range, "
            + $"BT.{(picture.Bt601 ? "601" : "709")}. Wrote {width}×{height} to {Path.GetFullPath(output)}.");
        return 0;
    }
}
