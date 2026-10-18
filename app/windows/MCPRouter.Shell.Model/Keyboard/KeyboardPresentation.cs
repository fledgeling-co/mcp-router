using System;
using System.Linq;

namespace MCPRouter.Shell.Model.Keyboard;

public static class KeyboardPresentation
{
    public const string PaneCyclingKey = "F6";
    public const string PaneCyclingDescription = "F6 cycles between sidebar and active board pane.";

    public static string ShortcutFor(string destinationId)
    {
        var sc = WindowsKeyboardModel.DestinationShortcuts.FirstOrDefault(s => s.DestinationId == destinationId);
        return sc?.KeyChord ?? string.Empty;
    }

    public static string AccessKeyFor(string destinationId)
    {
        var sc = WindowsKeyboardModel.DestinationShortcuts.FirstOrDefault(s => s.DestinationId == destinationId);
        return sc?.AccessKey ?? string.Empty;
    }
}
