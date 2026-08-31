using MCPRouter.Shell.Model.Inbox;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InboxPresentationTests
{
    [Fact]
    public void Subtitle_WhenNoPhonePaired_ReportsNoPhone()
    {
        var sub = InboxPresentation.Subtitle(0, null);
        Assert.Equal("Nothing waiting · no phone paired", sub);

        var sub2 = InboxPresentation.Subtitle(3, "");
        Assert.Equal("3 waiting · no phone paired", sub2);
    }

    [Fact]
    public void Subtitle_WhenPhonePaired_ReportsDevice()
    {
        var sub = InboxPresentation.Subtitle(3, "Luke's iPhone");
        Assert.Equal("3 waiting from Luke's iPhone", sub);

        var sub2 = InboxPresentation.Subtitle(0, "Luke's iPhone");
        Assert.Equal("Nothing waiting · paired with Luke's iPhone", sub2);
    }

    [Fact]
    public void TabLabels_DisplayCountsCorrectly()
    {
        Assert.Equal("Undecided · 3", InboxPresentation.TabLabel(DecisionState.Undecided, 3));
        Assert.Equal("Approved · 12", InboxPresentation.TabLabel(DecisionState.Approved, 12));
        Assert.Equal("Not for me · 5", InboxPresentation.TabLabel(DecisionState.NotForMe, 5));
    }

    [Fact]
    public void Descriptions_ReflectCoreSafetyGuarantees()
    {
        Assert.Contains("the phone queues, it never installs", InboxPresentation.BoardDescription);
        Assert.Equal("What it would be able to do", InboxPresentation.ReviewSectionTitle);
    }
}
