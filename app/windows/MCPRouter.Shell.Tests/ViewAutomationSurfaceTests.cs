using System.Linq;
using System.Xml.Linq;
using MCPRouter.Shell.Model.Settings;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The structural rung under DEF-076 and DEF-075: what the two view files DECLARE on the
/// automation plane. The live rung is the out-of-process UIA lane
/// (scripts/windows/uia/shell-lane.ps1, section 3b), which is the one that can say the tree
/// really publishes these. This suite is the arm that runs everywhere, including on a host with
/// no interactive session, and it reads the XAML as XML rather than as text so an attribute that
/// moves line does not silently stop being checked.
///
/// What it cannot say, and does not: that a toggle is bound to anything. A name in markup and a
/// live control are different claims. The lane makes the second one.
/// </summary>
public sealed class ViewAutomationSurfaceTests
{
    private static readonly XNamespace Automation =
        "using:Microsoft.UI.Xaml.Automation";

    private static XDocument View(string relative)
        => XDocument.Parse(RepoRoot.Read(relative));

    private static string? Prop(XElement element, string name)
        => (string?)element.Attribute(Automation + ("AutomationProperties." + name));

    // ------------------------------------------------------------------ DEF-076: the Settings board

    [Fact]
    public void SettingsBoard_DeclaresOneAddressableSectionPerDeclaredSection()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/SettingsBoard.xaml");
        var ids = view.Descendants()
            .Select(e => Prop(e, "AutomationId"))
            .Where(id => id is not null && id.StartsWith("settings.section."))
            .ToList();

        // Seven, because SettingsPresentation declares seven - not because seven is typed here.
        // DEF-076 was exactly the gap between a ledger row claiming seven and a view rendering
        // three, and nothing in the build could tell the two numbers apart.
        Assert.Equal(SettingsPresentation.SectionOrder.Count, ids.Count);
        foreach (var section in SettingsPresentation.SectionOrder)
        {
            Assert.Contains(SettingsPresentation.SectionAutomationId(section), ids);
        }
    }

    [Fact]
    public void SettingsBoard_SectionsCarryAName()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/SettingsBoard.xaml");
        foreach (var section in SettingsPresentation.SectionOrder)
        {
            var id = SettingsPresentation.SectionAutomationId(section);
            var element = view.Descendants().Single(e => Prop(e, "AutomationId") == id);
            Assert.False(string.IsNullOrWhiteSpace(Prop(element, "Name")),
                $"{id} publishes no accessible name");
        }
    }

    [Fact]
    public void SettingsBoard_DeclaresOneToggleSwitchPerToggleKey_EachBoundAndTagged()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/SettingsBoard.xaml");
        var toggles = view.Descendants()
            .Where(e => e.Name.LocalName == "ToggleSwitch")
            .ToList();

        Assert.Equal(SettingsPresentation.ToggleKeys.Count, toggles.Count);

        foreach (var toggle in toggles)
        {
            var key = (string?)toggle.Attribute("Tag");
            Assert.NotNull(key);
            Assert.Contains(key!, SettingsPresentation.ToggleKeys);

            // The inert-UI check. A ToggleSwitch with no Toggled handler flips and changes
            // nothing, which is the defect one layer along from the one being fixed.
            Assert.Equal("OnToggled", (string?)toggle.Attribute("Toggled"));

            // And it must NOT carry a literal IsOn: the seed comes from the model, so that the
            // switch and the state it claims to show cannot start out disagreeing.
            Assert.Null(toggle.Attribute("IsOn"));
        }
    }

    /// <summary>
    /// The readout is addressable and carries NO AutomationProperties.Name. That absence is the
    /// assertion: a TextBlock publishes its own Text as its accessible name, and a static Name
    /// would override it - so the out-of-process lane, which watches this element for the effect
    /// of a toggle, would read the same string forever. The first census run measured exactly
    /// that and reported the board inert when it was not.
    /// </summary>
    [Fact]
    public void SettingsBoard_StateReadoutIsAddressableAndPublishesItsValue()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/SettingsBoard.xaml");
        var readout = view.Descendants()
            .SingleOrDefault(e => Prop(e, "AutomationId") == "settings.state.summary");
        Assert.NotNull(readout);
        Assert.Null(Prop(readout!, "Name"));
    }

    // ------------------------------------------------------------------ DEF-075: the Discover detail

    /// <summary>
    /// Every x:Named element in the dialog content is addressable by a stable automation id.
    /// Ids rather than names on the text elements deliberately: a TextBlock publishes its own
    /// Text as its accessible name, and an AutomationProperties.Name would override that, so
    /// Narrator would read the label instead of the content. The containers, which publish
    /// nothing of their own, carry names as well.
    /// </summary>
    [Fact]
    public void DiscoverDetail_EveryNamedElementIsAddressable()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/DiscoverDetailContent.xaml");
        XNamespace x = "http://schemas.microsoft.com/winfx/2006/xaml";

        var named = view.Descendants()
            .Where(e => e.Attribute(x + "Name") is not null && e.Name.LocalName != "UserControl")
            .ToList();

        Assert.NotEmpty(named);
        var missing = named
            .Where(e => string.IsNullOrWhiteSpace(Prop(e, "AutomationId")))
            .Select(e => (string?)e.Attribute(x + "Name"))
            .ToList();

        Assert.True(missing.Count == 0,
            "these elements carry no AutomationProperties.AutomationId: " + string.Join(", ", missing));
    }

    [Fact]
    public void DiscoverDetail_ContainersThatPublishNoTextCarryAName()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/DiscoverDetailContent.xaml");
        foreach (var id in new[]
                 {
                     "discover.detail.root",
                     "discover.detail.argv",
                     "discover.detail.requirements",
                     "discover.detail.requirements.fields",
                 })
        {
            var element = view.Descendants().Single(e => Prop(e, "AutomationId") == id);
            Assert.False(string.IsNullOrWhiteSpace(Prop(element, "Name")),
                $"{id} publishes no accessible name");
        }
    }
}
