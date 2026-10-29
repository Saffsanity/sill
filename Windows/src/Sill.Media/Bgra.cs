namespace Sill.Media;

/// <summary>
/// NV12 to 32-bit BGRA for drawing, fast enough for 4K at 60 frames a second: fixed-point
/// arithmetic, rows in parallel, and an optional step that samples every Nth pixel when the
/// window is smaller than the picture. <c>Sill.Protocol.Nv12.ToRgb</c> is the exact, slow one.
/// </summary>
public static unsafe class Bgra
{
    /// <summary>Writes <paramref name="width"/>/<paramref name="step"/> × <paramref name="height"/>/<paramref name="step"/>
    /// pixels to <paramref name="destination"/> (rows <paramref name="destinationStride"/> bytes apart).</summary>
    public static void FromNv12(byte[] nv12, int stride, int planeHeight, int left, int top, int width, int height, int step,
        bool fullRange, bool bt601, byte* destination, int destinationStride)
    {
        int outW = width / step, outH = height / step;
        // Y'CbCr → R'G'B' in 16.16 fixed point (BT.709 or 601; full or video range).
        double kr = bt601 ? 0.299 : 0.2126, kb = bt601 ? 0.114 : 0.0722, kg = 1 - kr - kb;
        double ys = fullRange ? 1 : 255.0 / 219, cs = fullRange ? 1 : 255.0 / 224;
        int yMul = (int)(ys * 65536), yOff = fullRange ? 0 : 16;
        int rv = (int)(2 * (1 - kr) * cs * 65536), bu = (int)(2 * (1 - kb) * cs * 65536);
        int gu = (int)(-2 * (1 - kb) * kb / kg * cs * 65536), gv = (int)(-2 * (1 - kr) * kr / kg * cs * 65536);
        int uvBase = stride * planeHeight;
        long dest = (long)destination;

        Parallel.For(0, outH, row =>
        {
            int sy = top + row * step;
            fixed (byte* src = nv12)
            {
                byte* yRow = src + sy * stride + left;
                byte* uvRow = src + uvBase + (sy >> 1) * stride + left;
                uint* o = (uint*)((byte*)dest + row * destinationStride);
                for (int x = 0, sx = 0; x < outW; x++, sx += step)
                {
                    int l = (yRow[sx] - yOff) * yMul;
                    byte* c = uvRow + (sx & ~1);
                    int u = c[0] - 128, v = c[1] - 128;
                    int r = (l + rv * v) >> 16, g = (l + gu * u + gv * v) >> 16, b = (l + bu * u) >> 16;
                    o[x] = 0xFF000000u | (uint)(Clamp(r) << 16) | (uint)(Clamp(g) << 8) | (uint)Clamp(b);
                }
            }
        });
    }

    private static int Clamp(int v) => v < 0 ? 0 : v > 255 ? 255 : v;
}
