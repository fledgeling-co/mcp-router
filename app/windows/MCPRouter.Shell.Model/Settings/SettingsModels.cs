using System;

namespace MCPRouter.Shell.Model.Settings;

public enum SettingsSection
{
    Router,
    Harnesses,
    SessionAnalyst,
    Updates,
    Security,
    AmbientSurface,
    Advanced
}

public sealed record RouterSettingsState(
    string Endpoint = "http://127.0.0.1:8879",
    string HomeDirectory = @"%USERPROFILE%\.claude\mcp-router",
    string IdleReaper = "300 s (5 min)",
    string CountingSince = "2026-08-01",
    bool LaunchAtLogin = true,
    bool ShowAmbientIcon = true,
    bool RequireConfirmationOnDestructive = true
);
