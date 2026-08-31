using System;

namespace MCPRouter.Shell.Model.Lifecycle;

public static class LifecyclePresentation
{
    public const string UserSessionRequirement = "The router daemon runs in the user session so it can interact with local browser instances for OAuth flows and access per-user harness configurations.";

    public static string ModeDescription(DaemonSupervisionKind mode)
    {
        return mode switch
        {
            DaemonSupervisionKind.LogonTask => "Scheduled Task at user logon (restarts on crash, un-elevated)",
            DaemonSupervisionKind.StartupShortcut => "Windows Startup folder shortcut",
            DaemonSupervisionKind.InAppSupervised => "Supervised directly by Windows Shell process",
            _ => mode.ToString()
        };
    }
}
