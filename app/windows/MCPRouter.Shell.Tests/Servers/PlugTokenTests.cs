using System.Text.RegularExpressions;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// The plug's state-to-token decision, gated at the boundary where it now lives.
///
/// <para>DESIGN.md §12's restated row gives every jack state its hue — the indicator-hue table's
/// <c>SystemFillColorSuccess</c> / <c>Critical</c> / <c>Caution</c>, the same hue's published
/// <c>…Background</c> token as the ring, and the authored off tokens at rest — and §13 closes
/// the one debt over it: <b>the accent is never spent on a plug</b>, because the accent is the
/// user's. That refusal used to be a switch statement in the view, untestable without a XAML
/// host — the class of decision that ships wrong exactly once, with no gate able to say so. It
/// is now a pure function on <see cref="JackState"/> in Shell.Model, and these tests are the
/// gate.</para>
/// </summary>
public sealed class PlugTokenTests
{
    /// <summary>Every state's tokens, against the design authority's table. The map is total —
    /// the five states are the Mac's five states (spec-WIN4 §3.2), so these rows are the whole
    /// domain, not a sample.</summary>
    [Theory]
    [InlineData(JackState.Live, "SystemFillColorSuccess", "SystemFillColorSuccessBackground")]
    [InlineData(JackState.Tripped, "SystemFillColorCritical", "SystemFillColorCriticalBackground")]
    [InlineData(JackState.Held, "SystemFillColorCaution", "SystemFillColorCautionBackground")]
    [InlineData(JackState.NeedsSignIn, "SystemFillColorCaution", "SystemFillColorCautionBackground")]
    [InlineData(JackState.Dormant, "TextFillColorDisabled", "ControlStrokeColorDefault")]
    public void PlugTokensAreTheRestatedRows(JackState state, string fill, string ring)
    {
        Assert.Equal((fill, ring), state.PlugTokens());
    }

    /// <summary>The load-bearing half of §13's settled debt, swept across every state: a live
    /// plug takes the platform's own success token — the hue Windows already publishes for
    /// "a child process is running" — never <c>AccentFillColorDefault</c>, and no state maps to
    /// any accent token at all. A one-line regression in the map now fails here, headlessly,
    /// instead of shipping green through every lane.</summary>
    [Fact]
    public void LiveTakesTheSuccessTokenAndNoStateEverTakesTheAccent()
    {
        var (liveFill, _) = JackState.Live.PlugTokens();
        Assert.Equal("SystemFillColorSuccess", liveFill);
        Assert.NotEqual("AccentFillColorDefault", liveFill);

        foreach (var state in Enum.GetValues<JackState>())
        {
            var (fill, ring) = state.PlugTokens();
            Assert.False(fill.Contains("Accent", StringComparison.Ordinal),
                $"{state}: the plug's fill takes '{fill}' — §13's settled debt says the accent is never spent on a plug");
            Assert.False(ring.Contains("Accent", StringComparison.Ordinal),
                $"{state}: the plug's ring takes '{ring}' — §13's settled debt says the accent is never spent on a plug");
        }
    }

    /// <summary>The decision must stay in Shell.Model: the view resolves tokens, it does not own
    /// the map. A view that stops consuming the pure function is a view whose accent refusal is
    /// untested again, so the wiring itself is gated.</summary>
    [Fact]
    public void TheViewConsumesThePureMapRatherThanOwningTheDecision()
    {
        var source = RepoRoot.Read("app/windows/MCPRouter.Shell/Views/ServersBoard.xaml.cs");
        Assert.Contains("PlugTokens()", source);
    }

    /// <summary>The source-text half of the gate: no line of the view assigns an Accent brush
    /// to any element's fill or stroke — the plug element included, and every other Ellipse
    /// with it. The add action's accent-filled button is Style-level and untouched by this; the
    /// rule §13 settles is about fills and strokes, and this is where a future
    /// <c>plug.Fill = ThemeBrush("AccentFillColorDefaultBrush")</c> would have to land.</summary>
    [Fact]
    public void TheViewNeverAssignsAnAccentBrushToAFillOrStroke()
    {
        var source = RepoRoot.Read("app/windows/MCPRouter.Shell/Views/ServersBoard.xaml.cs");
        var lines = source.Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            Assert.False(Regex.IsMatch(lines[i], @"\.(Fill|Stroke)\s*=[^=].*\bAccent"),
                $"ServersBoard.xaml.cs:{i + 1} assigns an Accent brush to a fill or stroke — " +
                "§13's settled debt: the accent is the user's, never a plug's");
        }

        // The XAML half of the same surface: no element in the board's own markup starts from
        // an accent fill or stroke either.
        var xaml = RepoRoot.Read("app/windows/MCPRouter.Shell/Views/ServersBoard.xaml");
        Assert.DoesNotMatch(@"(Fill|Stroke)=""\{ThemeResource Accent", xaml);
    }
}
