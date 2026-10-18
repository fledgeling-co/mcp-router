using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

/// <summary>
/// spec-WIN4 §3.4: <c>Reap idle</c> is drawn, wired, and disabled — <b>with the measured
/// reason</b>. §5's Disabled rule names the channels a discoverable reason travels on: the
/// accessibility <c>HelpText</c> (WIN3's pattern), and the head's own reason line.
///
/// <para><see cref="MCPRouter.Shell.Model.Servers.ServersCopy.ReapIdleReason"/> existed before
/// anything attached it, which is how a "discoverable" reason can be neither discovered nor
/// discoverable: a copy constant no surface draws is a sentence in a test, not a reason on the
/// board. These gates read the view's own source, because the wiring — not the wording — is
/// what was missing, and the wording already has its own sentence-case gate.</para>
/// </summary>
public sealed class ReapReasonTests
{
    private const string ViewSource = "app/windows/MCPRouter.Shell/Views/ServersBoard.xaml.cs";
    private const string ViewXaml = "app/windows/MCPRouter.Shell/Views/ServersBoard.xaml";

    /// <summary>The accessibility plane is where a reason survives a disabled control — the
    /// same pattern the disconnected state's StartButton carries, and the same constant, so
    /// screen-reader users hear the one wording sighted users read.</summary>
    [Fact]
    public void TheDisabledReapActionCarriesItsReasonOnTheAccessibilityPlane()
    {
        var source = RepoRoot.Read(ViewSource);
        Assert.Contains("AutomationProperties.SetHelpText(ReapButton, ServersCopy.ReapIdleReason)", source);
        Assert.Contains("ToolTipService.SetToolTip(ReapButton, ServersCopy.ReapIdleReason)", source);
    }

    /// <summary>The head's own reason line: the sighted channel. The line is drawn in the
    /// board's head, beside the dimmed action it explains, and its copy is the same
    /// <c>ReapIdleReason</c> — three channels, one wording.</summary>
    [Fact]
    public void TheHeadDrawsTheReasonLineBesideTheActionItExplains()
    {
        Assert.Contains("x:Name=\"ReapReasonText\"", RepoRoot.Read(ViewXaml));
        Assert.Contains("ReapReasonText.Text = ServersCopy.ReapIdleReason", RepoRoot.Read(ViewSource));
    }
}
