using MCPRouter.Shell.Model.Inbox;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InboxBoardModelTests
{
    [Fact]
    public void PopulateSampleData_CreatesUndecidedItems()
    {
        var model = new InboxBoardModel();
        model.PopulateSampleData();

        Assert.Equal(3, model.UndecidedCount);
        Assert.Equal(0, model.ApprovedCount);
        Assert.Equal(0, model.NotForMeCount);
        Assert.Equal(3, model.FilteredItems.Count);
    }

    [Fact]
    public void Approve_MovesItemToApproved()
    {
        var model = new InboxBoardModel();
        model.PopulateSampleData();

        model.Approve("postgres-mcp");

        Assert.Equal(2, model.UndecidedCount);
        Assert.Equal(1, model.ApprovedCount);
        Assert.Equal(2, model.FilteredItems.Count);

        model.SelectedFilter = DecisionState.Approved;
        Assert.Single(model.FilteredItems);
        Assert.Equal("postgres-mcp", model.FilteredItems[0].Id);
    }

    [Fact]
    public void Decline_MovesItemToNotForMe()
    {
        var model = new InboxBoardModel();
        model.PopulateSampleData();

        model.Decline("docker-mcp");

        Assert.Equal(2, model.UndecidedCount);
        Assert.Equal(1, model.NotForMeCount);

        model.SelectedFilter = DecisionState.NotForMe;
        Assert.Single(model.FilteredItems);
        Assert.Equal("docker-mcp", model.FilteredItems[0].Id);
    }
}
