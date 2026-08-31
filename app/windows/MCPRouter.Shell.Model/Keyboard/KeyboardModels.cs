using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Keyboard;

public sealed record KeyboardShortcut(
    string DestinationId,
    string KeyChord,
    string AccessKey,
    string DisplayName
);

public static class WindowsKeyboardModel
{
    public static readonly IReadOnlyList<KeyboardShortcut> DestinationShortcuts = new List<KeyboardShortcut>
    {
        new("servers", "Ctrl+1", "S", "Servers"),
        new("skills", "Ctrl+2", "K", "Skills"),
        new("discover", "Ctrl+3", "D", "Discover"),
        new("activity", "Ctrl+4", "A", "Activity"),
        new("checks", "Ctrl+5", "C", "Checks"),
        new("cleanup", "Ctrl+6", "L", "Cleanup"),
        new("inbox", "Ctrl+7", "I", "Inbox"),
        new("insights", "Ctrl+8", "N", "Insights"),
        new("harnesses", "Ctrl+9", "H", "Harnesses"),
        new("settings", "Ctrl+,", "T", "Settings")
    };
}
