using System.Text.Json;
using System.Text.Json.Serialization;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Inbox;

public sealed record RouterInboxRow(
    string Id, string DeviceName, string QueuedAt, string State,
    JsonElement? Resolved, string ReviewDigest);
public sealed record InboxDecisionResponse(string Id, string State);
public sealed record RouterInboxResponse(
    IReadOnlyList<RouterInboxRow> Items, IReadOnlyList<string>? PairedDeviceNames);

public interface IRouterInboxService
{
    Task<RouterInboxResponse> ReadAsync(CancellationToken cancellation = default);
    Task DecideAsync(string id, string action, string? digest, CancellationToken cancellation = default);
}

public sealed class RouterInboxService(ControlApiClient client) : IRouterInboxService
{
    public Task<RouterInboxResponse> ReadAsync(CancellationToken cancellation = default) => client.GetInboxAsync(cancellation);
    public Task DecideAsync(string id, string action, string? digest, CancellationToken cancellation = default) =>
        client.DecideInboxAsync(id, action, digest, cancellation);

    public static InboxItem Present(RouterInboxRow row)
    {
        if (string.IsNullOrWhiteSpace(row.Id) || string.IsNullOrWhiteSpace(row.DeviceName)
            || !DateTimeOffset.TryParse(row.QueuedAt, out var queued)
            || row.State is not ("waiting" or "accepted" or "declined")
            || string.IsNullOrEmpty(row.ReviewDigest))
            throw new ControlApiException(ControlApiFailure.MalformedResponse, "an inbox row is incomplete");
        var resolved = row.Resolved is { ValueKind: JsonValueKind.Object } value ? value : (JsonElement?)null;
        string? Read(JsonElement? node, string key) => node is {} obj && obj.TryGetProperty(key, out var property)
            && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
        JsonElement? install = resolved is {} entry && entry.TryGetProperty("install", out var found)
            && found.ValueKind == JsonValueKind.Object ? found : null;
        var name = Read(resolved, "displayName") ?? row.Id;
        var type = Read(install, "type");
        var command = Read(install, "command");
        var url = Read(install, "url");
        var requires = install is {} ins && ins.TryGetProperty("requires", out var req)
            && req.ValueKind == JsonValueKind.Array && req.GetArrayLength() > 0;
        var execution = type == "stdio" ? command : url;
        var lines = new List<InboxCapabilityLine>();
        if (resolved is null) lines.Add(new("The registry entry could not be resolved. This item cannot be approved.", true));
        else
        {
            lines.Add(new(Read(resolved, "description") ?? "The registry supplies no description.", false));
            if (!string.IsNullOrEmpty(execution)) lines.Add(new($"Runs through {type}: {execution}", true));
            if (install is {} config && config.TryGetProperty("args", out var args) && args.ValueKind == JsonValueKind.Array)
                lines.Add(new("Arguments: " + string.Join(" ", args.EnumerateArray().Select(a => a.GetString())), true));
            if (requires) lines.Add(new("This entry needs credentials and cannot be approved from the phone inbox.", true));
        }
        return new InboxItem(row.Id, name, InboxOriginKind.Phone, $"from {row.DeviceName}",
            queued.ToLocalTime().ToString("g"), "Your phone queued this for review. Approval declares the server on this computer.",
            lines, row.State switch { "accepted" => DecisionState.Approved, "declined" => DecisionState.NotForMe, _ => DecisionState.Undecided },
            ReviewDigest: row.ReviewDigest,
            CanApprove: resolved is not null && !requires && !string.IsNullOrWhiteSpace(execution));
    }
}
