using MCPRouter.Shell.Model.Cleanup;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class CleanupBoardModelTests
{
    [Fact]
    public void PopulateSampleData_CreatesNeverCalledAndQuietRows()
    {
        var model = new CleanupBoardModel();
        model.PopulateSampleData();

        Assert.Equal(3, model.NeverCalledRows.Count);
        Assert.Equal(2, model.QuietRows.Count);
        Assert.Equal(5, model.TotalCandidates);
        Assert.Equal(1, model.SelectedCount); // ai-elements selected by default
    }

    [Fact]
    public void SetSelection_TogglesRowSelection()
    {
        var model = new CleanupBoardModel();
        model.PopulateSampleData();

        model.SetSelection("pocketsmith", true);
        Assert.Equal(2, model.SelectedCount);

        model.SetSelection("ai-elements", false);
        Assert.Equal(1, model.SelectedCount);
    }

    [Fact]
    public void MarkAllAsKeep_ClearsAllSelections()
    {
        var model = new CleanupBoardModel();
        model.PopulateSampleData();

        model.MarkAllAsKeep();
        Assert.Equal(0, model.SelectedCount);
        Assert.Empty(model.GetSelectedRows());
    }

    [Fact]
    public void GetSelectedRows_ReturnsOnlySelectedItems()
    {
        var model = new CleanupBoardModel();
        model.PopulateSampleData();

        var selected = model.GetSelectedRows();
        Assert.Single(selected);
        Assert.Equal("ai-elements", selected[0].Id);
    }
}
