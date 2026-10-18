using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The sanitiser and the text it guards. Every string on this board is attacker-controlled - the
/// threat is drawn from the Mac's recorded analysis, and each family below is a family that
/// defeats a weaker filter (the first Mac cut missed the implicit marks, the line separators and
/// the zero-width family, and a review derived from the threat found them). Hostiles are spelled
/// with escapes so a reviewer can see exactly which codepoint family each case carries.
/// </summary>
public sealed class RegistryTextTests
{
    public static IEnumerable<object[]> HostileStrings()
    {
        // LRE / PDF embedding, and the isolate family.
        yield return new object[] { "\u202Aevilde\u202E", "evilde" };
        yield return new object[] { "\u2066evilde\u2069", "evilde" };
        // Implicit marks - no embedding needed, so the families above do not cover them.
        yield return new object[] { "evi\u200Fde\u200Ent", "evident" };
        yield return new object[] { "evi\u061Cde", "evide" };
        // Line and paragraph separators - newlines that are not C0. (Written as escapes: the C#
        // compiler treats U+2028 and U+2029 as line breaks in source.)
        yield return new object[] { "evi\u2028de\u2029nt", "evident" };
        // Zero-width space / joiner: two distinct strings that draw identically.
        yield return new object[] { "evi\u200Bde\u200Dnt", "evident" };
        // Deprecated format controls.
        yield return new object[] { "evi\u206Cde", "evide" };
        // C0 (including \r, \n, \t), DEL, and C1.
        yield return new object[] { "evi\rde\nnt\t", "evident" };
        yield return new object[] { "evi\u0085de", "evide" };
        yield return new object[] { "evi\u007Fde", "evide" };
    }

    [Theory]
    [MemberData(nameof(HostileStrings))]
    public void SanitizerStripsDisplaySpoofingFamilies(string hostile, string expected)
    {
        var clean = RegistryText.Sanitize(hostile);
        Assert.Equal(expected, clean);
        // The round trip is stable: sanitising clean output changes nothing.
        Assert.Equal(expected, RegistryText.Sanitize(clean));
    }

    [Fact]
    public void CleanTextPassesThroughUnchanged()
    {
        const string clean = "context-budget - diffs a delivered feature, cafe 2,984";
        Assert.Equal(clean, RegistryText.Sanitize(clean));
    }

    [Fact]
    public void CapTruncatesWithEllipsis()
    {
        var capped = RegistryText.Sanitize(new string('a', 500), cap: 60);
        Assert.Equal(61, capped.Length);
        Assert.EndsWith("\u2026", capped);
    }

    [Fact]
    public void CapLeavesShortTextAlone()
    {
        Assert.Equal("short", RegistryText.Sanitize("short", cap: 60));
    }

    [Theory]
    [InlineData("context budget analyzer", "CB")]
    [InlineData("filesystem", "FI")]
    [InlineData("  ", "?")]
    [InlineData("", "?")]
    public void MonogramTakesOneOrTwoInitials(string name, string expected)
    {
        Assert.Equal(expected, RegistryText.Monogram(name));
    }

    [Fact]
    public void MonogramIsSanitisedFirst()
    {
        // A name carrying a zero-width joiner reads by its cleaned initials, not its raw ones.
        Assert.Equal("AB", RegistryText.Monogram("a\u200Db"));
    }

    [Theory]
    [InlineData(0, "0")]
    [InlineData(9880, "9,880")]
    [InlineData(1234567, "1,234,567")]
    public void DecimalUsesThousandsSeparators(int value, string expected)
    {
        Assert.Equal(expected, RegistryText.Decimal(value));
    }

    [Theory]
    [InlineData("https://server.smithery.ai/@org/thing/mcp", "server.smithery.ai")]
    [InlineData("http://api.trusted.com.evil.io/x", "api.trusted.com.evil.io")]
    public void HostOfReturnsTheAuthority(string url, string expected)
    {
        Assert.Equal(expected, RegistryText.HostOf(url));
    }

    [Fact]
    public void HostOfReadsTheHostNotTheUserinfo()
    {
        // The case a hand-rolled parse gets wrong: the authority's userinfo carries the lookalike.
        Assert.Equal("evil.io", RegistryText.HostOf("https://api.smithery.ai@evil.io/mcp"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not a url")]
    [InlineData("ftp://example.com")]
    public void HostOfReturnsNullForNonHttpOrUnparseable(string? url)
    {
        Assert.Null(RegistryText.HostOf(url));
    }

    [Theory]
    [InlineData("2025-11-19T07:26:28.312Z")]        // Smithery: three fractional digits
    [InlineData("2025-09-14T15:20:36.371442Z")]     // official registry: six
    [InlineData("2026-01-02T03:04:05Z")]            // GitHub pushedAt: none
    public void TimestampsParseAllThreeWireShapes(string raw)
    {
        Assert.NotNull(RegistryText.TryParseTimestamp(raw));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("yesterday")]
    public void TimestampsThatCannotBeParsedReturnNull(string? raw)
    {
        Assert.Null(RegistryText.TryParseTimestamp(raw));
    }
}
