using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace Sill.Protocol;

/// <summary>
/// A decoded frame's NV12 (a Y plane, then interleaved U and V at half size, both <c>stride</c>
/// bytes a row) as 8-bit RGB. Portable, so it is tested on any OS; the decoder that yields NV12
/// is Windows' (Sill.Spike's <c>HevcDecoder</c>).
/// </summary>
public static class Nv12
{
    /// <summary>RGB, 3 bytes a pixel, <paramref name="width"/> × <paramref name="height"/>.
    /// <paramref name="planeHeight"/> is the Y plane's rows in the buffer (a decoder may pad it
    /// past the picture: 948 shown, 960 stored). BT.709 unless <paramref name="bt601"/>; full range
    /// (0–255) or video range (Y 16–235, chroma 16–240). <paramref name="left"/> and
    /// <paramref name="top"/> (even) crop the stored picture, as an SPS's conformance window does.</summary>
    public static byte[] ToRgb(ReadOnlySpan<byte> nv12, int width, int height, int stride, int planeHeight, bool fullRange,
        bool bt601 = false, int left = 0, int top = 0)
    {
        if (width <= 0 || height <= 0 || left < 0 || top < 0 || (left | top) % 2 != 0
            || stride < left + width || planeHeight < top + height)
            throw new ArgumentException("A picture is at least 1×1 and fits its stride and plane.");
        long need = (long)stride * planeHeight + (long)stride * ((top + height + 1) / 2);
        if (nv12.Length < need) throw new ArgumentException($"NV12 of {width}×{height} needs {need} bytes; got {nv12.Length}.");

        // Y'CbCr → R'G'B' (ITU-R BT.709 / BT.601 coefficients).
        double kr = bt601 ? 0.299 : 0.2126, kb = bt601 ? 0.114 : 0.0722, kg = 1 - kr - kb;
        double rv = 2 * (1 - kr), bu = 2 * (1 - kb), gu = -bu * kb / kg, gv = -rv * kr / kg;
        double yScale = fullRange ? 1 : 255.0 / 219, cScale = fullRange ? 1 : 255.0 / 224, yOffset = fullRange ? 0 : 16;

        var rgb = new byte[width * height * 3];
        int uvBase = stride * planeHeight;
        for (int y = 0; y < height; y++)
        {
            int sy = top + y, yRow = sy * stride + left, uvRow = uvBase + (sy / 2) * stride + left, o = y * width * 3;
            for (int x = 0; x < width; x++)
            {
                double l = (nv12[yRow + x] - yOffset) * yScale;
                int c = uvRow + (x & ~1);
                double u = (nv12[c] - 128) * cScale, v = (nv12[c + 1] - 128) * cScale;
                rgb[o++] = Clamp(l + rv * v);
                rgb[o++] = Clamp(l + gu * u + gv * v);
                rgb[o++] = Clamp(l + bu * u);
            }
        }
        return rgb;
    }

    private static byte Clamp(double v) => v <= 0 ? (byte)0 : v >= 255 ? (byte)255 : (byte)Math.Round(v);
}

/// <summary>A minimal PNG writer: 8-bit RGB, one IDAT, no filtering (each row's filter byte 0).
/// The BCL has no PNG encoder outside System.Drawing, which the spike leaves out.</summary>
public static class Png
{
    public static byte[] Encode(ReadOnlySpan<byte> rgb, int width, int height)
    {
        if (rgb.Length != width * height * 3) throw new ArgumentException("RGB is 3 bytes a pixel.");
        using var png = new MemoryStream();
        png.Write([0x89, (byte)'P', (byte)'N', (byte)'G', 0x0D, 0x0A, 0x1A, 0x0A]);

        var ihdr = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(ihdr, width);
        BinaryPrimitives.WriteInt32BigEndian(ihdr.AsSpan(4), height);
        ihdr[8] = 8;    // bit depth
        ihdr[9] = 2;    // colour type: RGB
        Chunk(png, "IHDR", ihdr);

        using (var raw = new MemoryStream())
        {
            using (var z = new ZLibStream(raw, CompressionLevel.Optimal, leaveOpen: true))
                for (int y = 0; y < height; y++) { z.WriteByte(0); z.Write(rgb.Slice(y * width * 3, width * 3)); }
            Chunk(png, "IDAT", raw.ToArray());
        }
        Chunk(png, "IEND", []);
        return png.ToArray();
    }

    private static void Chunk(Stream s, string type, ReadOnlySpan<byte> data)
    {
        Span<byte> four = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(four, data.Length);
        s.Write(four);
        byte[] typeBytes = Encoding.ASCII.GetBytes(type);
        s.Write(typeBytes);
        s.Write(data);
        BinaryPrimitives.WriteUInt32BigEndian(four, Crc32(Crc32(0xFFFFFFFF, typeBytes), data) ^ 0xFFFFFFFF);
        s.Write(four);
    }

    private static readonly uint[] Table = Enumerable.Range(0, 256).Select(n =>
    {
        uint c = (uint)n;
        for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
        return c;
    }).ToArray();

    /// <summary>The CRC-32 of PNG chunks (ISO 3309), continued from <paramref name="crc"/>.</summary>
    public static uint Crc32(uint crc, ReadOnlySpan<byte> data)
    {
        foreach (byte b in data) crc = Table[(crc ^ b) & 0xFF] ^ (crc >> 8);
        return crc;
    }
}

/// <summary>Where a picture lands in a window when its shape is kept: centred, bars on the sides
/// or above and below (the viewer's drawing and its mouse both use it).</summary>
public static class Letterbox
{
    public static (int X, int Y, int Width, int Height) Fit(int pictureWidth, int pictureHeight, int areaWidth, int areaHeight)
    {
        double scale = Math.Min((double)areaWidth / pictureWidth, (double)areaHeight / pictureHeight);
        int w = Math.Max(1, (int)(pictureWidth * scale)), h = Math.Max(1, (int)(pictureHeight * scale));
        return ((areaWidth - w) / 2, (areaHeight - h) / 2, w, h);
    }
}
