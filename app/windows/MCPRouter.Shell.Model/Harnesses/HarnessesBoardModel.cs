using System;
using System.Collections.Generic;
using System.Linq;

namespace MCPRouter.Shell.Model.Harnesses;

public sealed class HarnessesBoardModel
{
    private readonly List<DetectedHarness> _harnesses = new();

    public IReadOnlyList<DetectedHarness> Harnesses => _harnesses;
    public int DoubleRunningCount => _harnesses.Count(h => h.State == HarnessReading.RoutedWithDirectServers);

    public void PopulateSampleData()
    {
        _harnesses.Clear();

        _harnesses.Add(new DetectedHarness(
            Harness: "claude",
            DisplayName: "Claude Desktop",
            Path: @"%APPDATA%\Claude\claude_desktop_config.json",
            Exists: true,
            State: HarnessReading.RoutedOverHTTP,
            Route: HarnessTransport.Http,
            Entries: 1,
            DuplicateCount: 0,
            Duplicates: Array.Empty<HarnessDuplicate>(),
            HttpCapability: "Speaks streamable HTTP natively without a bridge."
        ));

        _harnesses.Add(new DetectedHarness(
            Harness: "cursor",
            DisplayName: "Cursor",
            Path: @"%USERPROFILE%\.cursor\mcp.json",
            Exists: true,
            State: HarnessReading.RoutedWithDirectServers,
            Route: HarnessTransport.StdioShim,
            Entries: 4,
            DuplicateCount: 2,
            Duplicates: new List<HarnessDuplicate>
            {
                new("postgres", "postgres-mcp", "name"),
                new("fetch", "fetch", "identity")
            },
            HttpCapability: "Routes through stdio bridge.",
            Bridge: "mcp-remote"
        ));

        _harnesses.Add(new DetectedHarness(
            Harness: "antigravity",
            DisplayName: "Antigravity",
            Path: @"%USERPROFILE%\.antigravity\mcp.json",
            Exists: true,
            State: HarnessReading.RoutedWithDirectServers,
            Route: HarnessTransport.StdioShim,
            Entries: 18,
            DuplicateCount: 10,
            Duplicates: new List<HarnessDuplicate>
            {
                new("docker", "docker-mcp", "name")
            },
            HttpCapability: "Routes via per-session shim.",
            Bridge: "shim"
        ));

        _harnesses.Add(new DetectedHarness(
            Harness: "vscode",
            DisplayName: "VS Code / Codex",
            Path: @"%USERPROFILE%\.vscode\mcp.json",
            Exists: false,
            State: HarnessReading.NotRouted,
            Route: HarnessTransport.None,
            Entries: 0,
            DuplicateCount: 0,
            Duplicates: Array.Empty<HarnessDuplicate>(),
            HttpCapability: "Not installed or configured."
        ));
    }
}
