using System;

namespace MCPRouter.Shell.Model.Lifecycle;

public enum DaemonSupervisionKind
{
    LogonTask,
    StartupShortcut,
    InAppSupervised
}

public enum DaemonProcessStatus
{
    Stopped,
    Starting,
    Running,
    Failed
}

public sealed record DaemonLifecycleConfig(
    DaemonSupervisionKind Mode,
    int Port,
    string ExecutablePath,
    bool RestartOnCrash,
    int RestartDelaySeconds
);
