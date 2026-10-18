using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using Sill.Protocol;

namespace Sill.Protocol.Tests;

public class PictureTests
{
    // A 2×2 NV12 picture of one colour: four Y bytes (stride 2, two rows), then one U,V pair.
    private static byte[] Solid(byte y, byte u, byte v) => [y, y, y, y, u, v];

    [Theory]
    [InlineData(255, 128, 128, true, 255, 255, 255)]     // white, full range
    [InlineData(0, 128, 128, true, 0, 0, 0)]             // black, full range
    [InlineData(235, 128, 128, false, 255, 255, 255)]    // white, video range
    [InlineData(16, 128, 128, false, 0, 0, 0)]           // black, video range
    [InlineData(63, 102, 240, false, 255, 0, 0)]         // BT.709 red (video range: Y 63, Cb 102, Cr 240)
    [InlineData(173, 42, 26, false, 0, 255, 0)]          // BT.709 green
    [InlineData(32, 240, 118, false, 0, 0, 255)]         // BT.709 blue
    public void Nv12BecomesRgb(byte y, byte u, byte v, bool full, int r, int g, int b)
    {
        var rgb = Nv12.ToRgb(Solid(y, u, v), 2, 2, 2, 2, full);
        for (int i = 0; i < 4; i++)
        {
            Assert.InRange(rgb[i * 3], r - 2, r + 2);
            Assert.InRange(rgb[i * 3 + 1], g - 2, g + 2);
            Assert.InRange(rgb[i * 3 + 2], b - 2, b + 2);
        }
    }

    [Fact]
    public void AStrideAndAPaddedPlaneAreSkipped()
    {
        // 2×2 shown, stride 4, 4 rows stored: padding bytes (9) must never reach the picture.
        byte[] nv12 =
        [
            255, 255, 9, 9,
            0, 0, 9, 9,
            9, 9, 9, 9,
            9, 9, 9, 9,
            128, 128, 9, 9,   // UV row for picture rows 0–1
            9, 9, 9, 9,
        ];
        var rgb = Nv12.ToRgb(nv12, 2, 2, 4, 4, fullRange: true);
        Assert.Equal([255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0], rgb);
        Assert.Throws<ArgumentException>(() => Nv12.ToRgb(nv12[..^5], 2, 2, 4, 4, true));
    }

    [Fact]
    public void ThePngIsWellFormed()
    {
        byte[] rgb = [255, 0, 0, 0, 255, 0, 0, 0, 255, 10, 20, 30];   // 2×2
        byte[] png = Png.Encode(rgb, 2, 2);
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }, png[..8]);

        var chunks = new List<(string Type, byte[] Data)>();
        for (int at = 8; at < png.Length;)
        {
            int len = BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(at));
            string type = Encoding.ASCII.GetString(png, at + 4, 4);
            byte[] data = png.AsSpan(at + 8, len).ToArray();
            uint crc = BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(at + 8 + len));
            Assert.Equal(Png.Crc32(Png.Crc32(0xFFFFFFFF, png.AsSpan(at + 4, 4)), data) ^ 0xFFFFFFFF, crc);
            chunks.Add((type, data));
            at += 12 + len;
        }
        Assert.Equal(["IHDR", "IDAT", "IEND"], chunks.Select(c => c.Type));
        Assert.Equal(new byte[] { 0, 0, 0, 2, 0, 0, 0, 2, 8, 2, 0, 0, 0 }, chunks[0].Data);

        using var z = new ZLibStream(new MemoryStream(chunks[1].Data), CompressionMode.Decompress);
        using var raw = new MemoryStream();
        z.CopyTo(raw);
        Assert.Equal([0, .. rgb[..6], 0, .. rgb[6..]], raw.ToArray());
    }

    [Fact]
    public void TheCrcIsPngs()
    {
        // The CRC of an empty IEND chunk, as every PNG ends: AE 42 60 82.
        Assert.Equal(0xAE426082u, Png.Crc32(0xFFFFFFFF, "IEND"u8) ^ 0xFFFFFFFF);
    }
}

public class HevcSpsTests
{
    // Kind 0 from SillHost's software encoder (the synthetic Desktop, 1512×948), as the PC received it.
    private static readonly byte[] RealParameterSets = Convert.FromHexString("0403001740010c01ffff216000000300b0000003000003007b3c090022420101216000000300b0000003000003007ba002f4803b9f79cf924489bf9713600800084401c0252f053240");

    [Fact]
    public void TheRealSpsGivesTheCodedAndShownSize()
    {
        var ps = ParameterSets.Parse(RealParameterSets)!;
        var sps = HevcSps.Parse(ps.Sets[1])!;
        Assert.Equal((1512, 948), (sps.Width, sps.Height));                  // ffprobe's size for the same stream
        Assert.Equal(0, sps.CodedWidth % 8);
        Assert.Equal(0, sps.CodedHeight % 8);
        Assert.Equal((0, 0), (sps.Left, sps.Top));
    }

    [Fact]
    public void AnythingButAnSpsIsRefused()
    {
        var ps = ParameterSets.Parse(RealParameterSets)!;
        Assert.Null(HevcSps.Parse(ps.Sets[0]));          // the VPS
        Assert.Null(HevcSps.Parse(ps.Sets[1][..8]));     // an SPS cut short
        Assert.Null(HevcSps.Parse([]));
    }
}
