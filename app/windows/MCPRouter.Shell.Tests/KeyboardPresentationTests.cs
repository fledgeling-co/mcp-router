using MCPRouter.Shell.Model.Keyboard;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class KeyboardPresentationTests
{
    [Theory]
    [InlineData("servers", "Ctrl+1", "S")]
    [InlineData("skills", "Ctrl+2", "K")]
    [InlineData("discover", "Ctrl+3", "D")]
    [InlineData("activity", "Ctrl+4", "A")]
    [InlineData("checks", "Ctrl+5", "C")]
    [InlineData("cleanup", "Ctrl+6", "L")]
    [InlineData("inbox", "Ctrl+7", "I")]
    [InlineData("insights", "Ctrl+8", "N")]
    [InlineData("harnesses", "Ctrl+9", "H")]
    [InlineData("settings", "Ctrl+,", "T")]
    public void DestinationShortcuts_MapToControlKeysAndAccessKeys(string destinationId, string expectedShortcut, string expectedAccessKey)
    {
        Assert.Equal(expectedShortcut, KeyboardPresentation.ShortcutFor(destinationId));
        Assert.Equal(expectedAccessKey, KeyboardPresentation.AccessKeyFor(destinationId));
    }

    [Fact]
    public void PaneCycling_IsF6()
    {
        Assert.Equal("F6", KeyboardPresentation.PaneCyclingKey);
    }
}
