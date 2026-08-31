using System.Globalization;
using System.Text;

namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// Text hygiene for the one surface where <b>every string is attacker-controlled</b>.
///
/// <c>displayName</c>, <c>name</c>, <c>description</c> and every element of an install command are
/// chosen by whoever published the entry, and this is the surface where a user decides whether to
/// run their code. The sanitiser is a port of the Mac's <c>RegistryPresentation.sanitized</c>,
/// whose threat model is recorded there: bidi overrides and isolates, the implicit marks that
/// need no embedding, line separators that are not C0, zero-width characters that make two
/// distinct strings draw identically, deprecated format controls, and the C0/C1 ranges. Applied
/// at this boundary so no view can forget it.
/// </summary>
public static class RegistryText
{
    public static string Sanitize(string raw)
    {
        var sb = new StringBuilder(raw.Length);
        foreach (var ch in raw)
        {
            var v = (int)ch;
            if (v is >= 0x202A and <= 0x202E) continue;          // bidi embeddings + overrides
            if (v is >= 0x2066 and <= 0x2069) continue;          // bidi isolates
            if (v is 0x200E or 0x200F or 0x061C) continue;       // LRM / RLM / ALM — no embedding needed
            if (v is 0x2028 or 0x2029) continue;                 // line / paragraph separator
            if (v is >= 0x200B and <= 0x200D) continue;          // zero-width space / non-joiner / joiner
            if (v is >= 0x206A and <= 0x206F) continue;          // deprecated format controls
            if (v < 0x20 || v == 0x7F) continue;                 // C0 (incl. \n, \t) and DEL
            if (v is >= 0x80 and <= 0x9F) continue;              // C1
            sb.Append(ch);
        }

        return sb.ToString();
    }

    /// <summary>Sanitised, and capped so one entry cannot push everything else off the surface —
    /// <c>description</c> is unbounded on the wire, and a megabyte of text in a dialog is a denial
    /// of the dialog.</summary>
    public static string Sanitize(string raw, int cap)
    {
        var clean = Sanitize(raw);
        if (clean.Length <= cap) return clean;
        return string.Concat(clean.AsSpan(0, cap), "…");
    }

    /// <summary>The one or two letters on the monogram plate, from the name the entry gave.
    /// Artwork on this board is always drawn locally — <c>iconUrl</c> is a host an attacker
    /// chose, and fetching it would be a second channel off the loopback boundary.</summary>
    public static string Monogram(string displayName)
    {
        var clean = Sanitize(displayName).Trim();
        var words = clean.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0 || words[0].Length == 0) return "?";
        if (words.Length > 1 && words[1].Length > 0)
        {
            return char.ToUpperInvariant(words[0][0]).ToString()
                   + char.ToUpperInvariant(words[1][0]).ToString();
        }

        var first = words[0];
        return first.Length >= 2
            ? first[..2].ToUpperInvariant()
            : first.ToUpperInvariant();
    }

    /// <summary>Thousands-separated decimal in the invariant culture — the instrument voice for
    /// numerals (DESIGN.md §12), and stable across the user's locale so a test can hold it.</summary>
    public static string Decimal(long value) =>
        value.ToString("N0", CultureInfo.InvariantCulture);

    /// <summary>The host of a URL, or null when it does not parse to one. Deliberately
    /// <see cref="Uri" />'s parser rather than any string handling: a hand-rolled parse is how
    /// <c>https://api.smithery.ai@evil.io/</code> gets read as the wrong host. Returns the host
    /// only — never the path, which is where a misleading string would hide.</summary>
    public static string? HostOf(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        if (!Uri.TryCreate(raw, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme is not ("http" or "https")) return null;
        var host = uri.Host;
        return host.Length == 0 ? null : Sanitize(host);
    }

    /// <summary>Both shapes the indexes actually emit — Smithery sends three fractional digits,
    /// the official registry six, GitHub's <c>pushedAt</c> none. One parser configured for
    /// fractional seconds rejects the third; the round-trip parse below accepts all three.
    /// Returns null when nothing parses, and the caller drops the cell rather than drawing a
    /// placeholder — a dash where a date belongs is a quieter lie than a wrong date, and still a
    /// lie.</summary>
    public static DateTimeOffset? TryParseTimestamp(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        if (DateTimeOffset.TryParse(
                raw,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsed))
        {
            return parsed;
        }

        return null;
    }

    /// <summary>The day a row's date cell shows, in the invariant culture: "19 Nov 2025".</summary>
    public static string Day(DateTimeOffset when) =>
        when.ToString("d MMM yyyy", CultureInfo.InvariantCulture);
}
