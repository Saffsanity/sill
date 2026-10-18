using System.Globalization;
using System.Text;

namespace Sill.Protocol;

/// <summary>
/// Text the other end supplies (the Mac's name in a link or kind 20) as a one-line label before
/// it is shown. Mirrors <c>SafeText.label</c> in Sources/StreamProtocol/SafeText.swift: every kind
/// of whitespace becomes one space, control and format characters (bidirectional overrides,
/// zero-width characters) are removed, the ends are trimmed, at most <c>limit</c> characters
/// (grapheme clusters) are kept.
/// </summary>
public static class SafeText
{
    public const int LabelLimit = 64;

    public static string Label(string text, int limit = LabelLimit)
    {
        var sb = new StringBuilder();
        bool pendingSpace = false;
        foreach (Rune r in text.EnumerateRunes())
        {
            var category = Rune.GetUnicodeCategory(r);
            if (Rune.IsWhiteSpace(r) || category is UnicodeCategory.LineSeparator or UnicodeCategory.ParagraphSeparator)
            {
                pendingSpace = sb.Length > 0;
                continue;
            }
            if (category is UnicodeCategory.Control or UnicodeCategory.Format or UnicodeCategory.Surrogate
                or UnicodeCategory.PrivateUse or UnicodeCategory.OtherNotAssigned)
                continue;
            if (pendingSpace) { sb.Append(' '); pendingSpace = false; }
            sb.Append(r.ToString());
        }
        string output = sb.ToString();
        var info = new StringInfo(output);
        if (info.LengthInTextElements > limit)
            output = info.SubstringByTextElements(0, limit).TrimEnd(' ');
        return output;
    }
}
