using System.Text.Json;

namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// Where the router's control API lives, read the way the router itself writes it.
///
/// The port is the router's own configured value — the top-level <c>port</c> key of
/// <c>servers.json</c> when present, else the published default 8879 (<c>src/config.ts line 306</c>).
/// The file is read for exactly that one key and nothing else is kept: it carries credentials,
/// so this type parses one number and discards the document whole.
/// </summary>
public static class ControlEndpoint
{
    public const int DefaultPort = 8879;
    public const string Host = "127.0.0.1";

    /// <summary>The router home: <c>MCP_ROUTER_HOME</c> when set, else
    /// <c>%USERPROFILE%\.claude\mcp-router</c> — the same resolution <c>src/config.ts line 100</c>
    /// makes.</summary>
    public static string RouterHome()
    {
        var configured = Environment.GetEnvironmentVariable("MCP_ROUTER_HOME");
        if (!string.IsNullOrWhiteSpace(configured)) return configured;
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            "mcp-router");
    }

    public static string ServersJsonPath() => Path.Combine(RouterHome(), "servers.json");

    /// <summary>The mutating half of the control API is gated by this bearer token
    /// (<c>src/control.ts line 46</c>). The file is read into memory for the header and never logged,
    /// printed, or copied anywhere by this app.</summary>
    public static string? ControlTokenPath() => Path.Combine(RouterHome(), "control.token");

    public static int Port()
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(ServersJsonPath()));
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("port", out var port)
                && port.TryGetInt32(out var value)
                && value is > 0 and < 65536)
            {
                return value;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            // No readable config means the published default, the same fallback the router
            // itself applies when the key is absent.
        }

        return DefaultPort;
    }

    public static string BaseUrl() => $"http://{Host}:{Port()}";
}
