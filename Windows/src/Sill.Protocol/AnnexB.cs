namespace Sill.Protocol;

/// <summary>Annex B (ITU-T H.265 Annex B): NAL units each after a start code, what Media
/// Foundation's HEVC decoder and ffmpeg read. Sill sends hvcC-style length prefixes instead.</summary>
public static class AnnexB
{
    private static readonly byte[] StartCode = [0, 0, 0, 1];

    /// <summary>A kind 1 access unit as Annex B, with <paramref name="ps"/>'s sets first when given
    /// (before a keyframe, so a decoder can start there).</summary>
    public static byte[] Build(ParameterSets? ps, byte[] frame, IReadOnlyList<(int Offset, int Length)> nals)
    {
        int size = nals.Sum(n => n.Length + 4) + (ps?.Sets.Sum(s => s.Length + 4) ?? 0);
        var bytes = new byte[size];
        int at = 0;
        void Put(ReadOnlySpan<byte> nal) { StartCode.CopyTo(bytes, at); nal.CopyTo(bytes.AsSpan(at + 4)); at += 4 + nal.Length; }
        if (ps is not null) foreach (var set in ps.Sets) Put(set);
        foreach (var (offset, length) in nals) Put(frame.AsSpan(offset, length));
        return bytes;
    }

    /// <summary>The NAL units of an Annex B stream (split at each 00 00 01, trailing zeros dropped).</summary>
    public static IEnumerable<byte[]> Nals(byte[] s)
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
