using Sill.Media;
using Sill.Protocol;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 07: the GPU path's letterbox, and its decode against the software decoder's.</summary>
public class GpuDecodeTests
{
    [Theory]
    [InlineData(3840, 2160, 1280, 720, 0, 0, 1280, 720)]     // the same shape: edge to edge
    [InlineData(3840, 2160, 1000, 1000, 0, 219, 1000, 562)]  // wider than the window: bars above and below
    [InlineData(1512, 948, 1600, 800, 162, 0, 1275, 800)]    // taller: bars at the sides
    [InlineData(100, 100, 1, 1, 0, 0, 1, 1)]                 // never smaller than a pixel
    public void LetterboxKeepsTheShapeAndCentres(int pw, int ph, int aw, int ah, int x, int y, int w, int h) =>
        Assert.Equal((x, y, w, h), Letterbox.Fit(pw, ph, aw, ah));

    /// <summary>The test pattern's keyframe (ticket 04's, 1512×948) decodes on the GPU to exactly the
    /// software decoder's NV12. Returns early on a Windows with no GPU video decode or no HEVC Video
    /// Extensions (a CI runner): there is nothing to compare there.</summary>
    [WindowsFact]
    public void GpuDecodeMatchesSoftware()
    {
        if (!OperatingSystem.IsWindows()) return;
        byte[] annexB = File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Fixtures", "test-pattern-keyframe.h265"));
        var sps = AnnexB.Nals(annexB).Select(n => HevcSps.Parse(n)).First(x => x is not null)!;
        HevcDecoder.Picture software;
        try { software = HevcDecoder.DecodeOne(annexB, sps).Picture; }
        // No HEVC decoder here, or no Media Foundation at all (a Windows Server runner without its
        // Media Foundation feature: MFStartup fails, or mfplat.dll is missing).
        catch (Exception e) when (e is InvalidOperationException or System.Runtime.InteropServices.COMException
                                  or DllNotFoundException) { return; }

        GpuDevice gpu;
        try { gpu = new GpuDevice(); }
        catch (System.Runtime.InteropServices.COMException) { return; }   // no Direct3D 11 hardware
        using (gpu)
        {
            HevcDecoder decoder;
            try { decoder = new HevcDecoder(sps, gpu: gpu); }
            catch (Exception e) when (e is NotSupportedException or System.Runtime.InteropServices.COMException) { return; }
            using (decoder)
            {
                using var picture = decoder.PushGpu(annexB) ?? decoder.DrainGpu();
                Assert.NotNull(picture);
                var back = gpu.ReadBack(picture);
                Assert.Equal((software.FullRange, software.Bt601), (back.FullRange, back.Bt601));
                // Compare the shown part, plane by plane: strides and padding may differ.
                for (int row = 0; row < sps.Height; row++)
                    Assert.True(software.Nv12.AsSpan(row * software.Stride, sps.Width)
                        .SequenceEqual(back.Nv12.AsSpan(row * back.Stride, sps.Width)), $"Y row {row} differs");
                int swUv = software.Stride * software.PlaneHeight, gpuUv = back.Stride * back.PlaneHeight;
                for (int row = 0; row < sps.Height / 2; row++)
                    Assert.True(software.Nv12.AsSpan(swUv + row * software.Stride, sps.Width)
                        .SequenceEqual(back.Nv12.AsSpan(gpuUv + row * back.Stride, sps.Width)), $"UV row {row} differs");
            }
        }
    }
}
