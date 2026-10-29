namespace Sill.Protocol;

/// <summary>
/// The picture size in an HEVC sequence parameter set (ITU-T H.265 §7.3.2.2): the coded size,
/// and the conformance window that crops it to what is shown (1512×948 shown, 1512×960 coded).
/// A decoder needs the coded size on its input type; the PNG is the shown size.
/// </summary>
public sealed record HevcSps(int CodedWidth, int CodedHeight, int Left, int Right, int Top, int Bottom)
{
    public int Width => CodedWidth - Left - Right;
    public int Height => CodedHeight - Top - Bottom;

    /// <summary>Null for anything that is not an SPS (NAL type 33) this reader follows.</summary>
    public static HevcSps? Parse(ReadOnlySpan<byte> nal)
    {
        if (nal.Length < 3 || ((nal[0] >> 1) & 0x3F) != 33) return null;
        var r = new BitReader(Unescape(nal[2..]));
        try
        {
            r.Bits(4);                                   // sps_video_parameter_set_id
            int maxSubLayersMinus1 = r.Bits(3);
            r.Bits(1);                                   // sps_temporal_id_nesting_flag
            // profile_tier_level(1, maxSubLayersMinus1): the general profile (88 bits) and level (8).
            r.Skip(88 + 8);
            var profilePresent = new bool[maxSubLayersMinus1];
            var levelPresent = new bool[maxSubLayersMinus1];
            for (int i = 0; i < maxSubLayersMinus1; i++) { profilePresent[i] = r.Bits(1) == 1; levelPresent[i] = r.Bits(1) == 1; }
            if (maxSubLayersMinus1 > 0) r.Skip(2 * (8 - maxSubLayersMinus1));   // reserved_zero_2bits
            for (int i = 0; i < maxSubLayersMinus1; i++) { if (profilePresent[i]) r.Skip(88); if (levelPresent[i]) r.Skip(8); }

            r.Ue();                                      // sps_seq_parameter_set_id
            int chroma = r.Ue();                         // chroma_format_idc
            if (chroma == 3) r.Bits(1);                  // separate_colour_plane_flag
            int width = r.Ue(), height = r.Ue();
            int left = 0, right = 0, top = 0, bottom = 0;
            if (r.Bits(1) == 1)                          // conformance_window_flag
            {
                // Offsets count in chroma samples: 2 luma columns and rows each in 4:2:0.
                int subW = chroma is 1 or 2 ? 2 : 1, subH = chroma == 1 ? 2 : 1;
                left = r.Ue() * subW; right = r.Ue() * subW; top = r.Ue() * subH; bottom = r.Ue() * subH;
            }
            if (width <= 0 || height <= 0 || left + right >= width || top + bottom >= height) return null;
            return new HevcSps(width, height, left, right, top, bottom);
        }
        catch (EndOfStreamException) { return null; }
    }

    // RBSP: drop each emulation-prevention 0x03 that follows two zero bytes.
    private static byte[] Unescape(ReadOnlySpan<byte> ebsp)
    {
        var rbsp = new List<byte>(ebsp.Length);
        int zeros = 0;
        foreach (byte b in ebsp)
        {
            if (zeros >= 2 && b == 3) { zeros = 0; continue; }
            rbsp.Add(b);
            zeros = b == 0 ? zeros + 1 : 0;
        }
        return [.. rbsp];
    }

    private sealed class BitReader(byte[] data)
    {
        private int bit;

        public int Bits(int n)
        {
            int v = 0;
            for (int i = 0; i < n; i++)
            {
                if (bit >= data.Length * 8) throw new EndOfStreamException();
                v = (v << 1) | ((data[bit >> 3] >> (7 - (bit & 7))) & 1);
                bit++;
            }
            return v;
        }

        public void Skip(int n)
        {
            if (bit + n > data.Length * 8) throw new EndOfStreamException();
            bit += n;
        }

        // ue(v), Exp-Golomb.
        public int Ue()
        {
            int zeros = 0;
            while (Bits(1) == 0) if (++zeros > 31) throw new EndOfStreamException();
            return zeros == 0 ? 0 : (1 << zeros) - 1 + Bits(zeros);
        }
    }
}
