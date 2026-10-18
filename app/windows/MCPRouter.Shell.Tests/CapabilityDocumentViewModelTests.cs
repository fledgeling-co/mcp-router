using MCPRouter.Shell.Model.CapabilityDocument;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class CapabilityDocumentViewModelTests
{
    [Fact]
    public void LoadDocument_PopulatesTabsAndDeltas()
    {
        var vm = new CapabilityDocumentViewModel();
        vm.LoadDocument("postgres-mcp");

        Assert.NotNull(vm.Document);
        Assert.Equal("postgres-mcp", vm.Document.CapabilityId);
        Assert.True(vm.Document.IsUpdateHeld);
        Assert.Equal(2, vm.Document.CapabilityDeltas.Count);
        Assert.NotEmpty(vm.Document.ChangelogText);
        Assert.NotEmpty(vm.Document.FlagsWorthKnowing);
    }
}
