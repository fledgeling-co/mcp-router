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

    // ------------------------------------------------------ DEF-084: the Discover store rows

    /// <summary>
    /// Both bands hand their realised containers to a handler. This is the assertion that a row's
    /// accessible name is set on the CONTAINER rather than in the DataTemplate: the template's
    /// root is a child of the ListViewItem, so naming it leaves the item itself announcing
    /// ToString() on the item object - which is what published
    /// "MCPRouter.Shell.Views.DiscoverRow" for every row in the store.
    /// </summary>
    [Fact]
    public void DiscoverBoard_BothBandsNameTheirRowContainers()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/DiscoverBoard.xaml");
        XNamespace x = "http://schemas.microsoft.com/winfx/2006/xaml";

        var bands = view.Descendants()
            .Where(e => e.Name.LocalName == "ListView")
            .Where(e => (string?)e.Attribute("ItemTemplate") == "{StaticResource DiscoverRowTemplate}")
            .ToList();

        Assert.Equal(2, bands.Count);
        foreach (var band in bands)
        {
            var name = (string?)band.Attribute(x + "Name");
            Assert.Equal("OnRowContainerChanging",
                (string?)band.Attribute("ContainerContentChanging"));
            Assert.False(string.IsNullOrWhiteSpace((string?)band.Attribute("AutomationProperties.Name")),
                $"{name} publishes no accessible name");
            Assert.False(string.IsNullOrWhiteSpace((string?)band.Attribute("AutomationProperties.AutomationId")),
                $"{name} carries no automation id");
        }
    }

    /// <summary>
    /// And NOTHING inside the row template carries a Name. The absence is the assertion, the same
    /// one DEF-075 settled one surface along: each TextBlock in the row publishes its own Text, so
    /// a static Name would make Narrator read a label where the value belongs, and would give a
    /// by-name assertion a constant to find.
    /// </summary>
    [Fact]
    public void DiscoverBoard_RowTemplateOverridesNoElementsOwnName()
    {
        var view = View("app/windows/MCPRouter.Shell/Views/DiscoverBoard.xaml");
        XNamespace x = "http://schemas.microsoft.com/winfx/2006/xaml";

        var template = view.Descendants()
            .Single(e => e.Name.LocalName == "DataTemplate"
                         && (string?)e.Attribute(x + "Key") == "DiscoverRowTemplate");

        var named = template.Descendants()
            .Where(e => e.Attribute("AutomationProperties.Name") is not null
                        || e.Attribute(Automation + "AutomationProperties.Name") is not null)
            .Select(e => e.Name.LocalName)
            .ToList();

        Assert.True(named.Count == 0,
            "these row-template elements override their own accessible name: " + string.Join(", ", named));
    }

    /// <summary>
    /// The code half, read as source text rather than as a tree - which is the honest limit of
    /// this rung: it can say the handler assigns both properties to the container it was handed,
    /// and it cannot say the handler ever runs. The live rung
    /// (scripts/windows/uia/shell-lane.ps1, the discover.rows arm) is the one that reads the names
    /// back off a running shell.
    /// </summary>
    [Fact]
    public void DiscoverBoard_RowContainerHandlerAssignsNameAndIdToTheContainer()
    {
        var code = RepoRoot.Read("app/windows/MCPRouter.Shell/Views/DiscoverBoard.xaml.cs");
        Assert.Contains("private void OnRowContainerChanging(", code);
        Assert.Contains("AutomationProperties.SetName(container, row.AccessibleName)", code);
        Assert.Contains("AutomationProperties.SetAutomationId(container, row.AutomationId)", code);

        // The floor under the handler: a row realised by a path that never raises
        // ContainerContentChanging still announces the capability rather than the class.
        var model = RepoRoot.Read("app/windows/MCPRouter.Shell/Views/DiscoverRow.cs");
        Assert.Contains("public override string ToString() => AccessibleName;", model);
    }

    // ---------------------------------------------------- DEF-089: the navigation pane's name

    [Fact]
    public void ShellWindow_NavigationPanePublishesAName()
    {
        var view = View("app/windows/MCPRouter.Shell/Shell/ShellWindow.xaml");
        XNamespace x = "http://schemas.microsoft.com/winfx/2006/xaml";

        var nav = view.Descendants()
            .Single(e => e.Name.LocalName == "NavigationView");

        Assert.Equal("Nav", (string?)nav.Attribute(x + "Name"));
        Assert.False(string.IsNullOrWhiteSpace((string?)nav.Attribute("AutomationProperties.Name")),
            "the NavigationView publishes no accessible name; a live dump reads its Name back as "
            + "the empty string, so nothing else supplies one");
    }
}
