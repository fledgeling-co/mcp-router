using MCPRouter.Shell.Model.Harnesses;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class HarnessesBoardModelTests
{
    [Fact]
    public void PopulateSampleData_DiscoversWindowsHarnesses()
    {
        var model = new HarnessesBoardModel();
        model.PopulateSampleData();

        Assert.Equal(4, model.Harnesses.Count);
        Assert.Equal(2, model.DoubleRunningCount);
    }
}
