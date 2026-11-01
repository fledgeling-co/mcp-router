using System.Text.Json;
using System.Text.Json.Nodes;

namespace MCPRouter.Shell.Model.Servers;

public sealed class HeldChangeReview(ControlApiClient client, string serverName)
{
    public string ServerName { get; } = serverName;
    public HeldChanges? Snapshot { get; private set; }
    public ControlApiException? Failure { get; private set; }
    public string? Notice { get; private set; }
    public bool Busy { get; private set; }
    public bool RequiresReload { get; private set; }
    public bool CanApprove => !Busy && !RequiresReload && Snapshot is { Pending: true } snapshot
        && snapshot.Server == ServerName && ValidDigest(snapshot.PendingDigest);

    public static bool ValidDigest(string? value) => value is { Length: 64 }
        && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

    public async Task LoadAsync(CancellationToken cancellation = default)
    {
        if (Busy) return;
        Busy = true;
        try { await LoadSnapshotAsync(cancellation); }
        finally { Busy = false; }
    }

    private async Task LoadSnapshotAsync(CancellationToken cancellation)
    {
        Snapshot = null;
        Failure = null;
        RequiresReload = true;
        try
        {
            var snapshot = await client.GetChangesAsync(ServerName, cancellation);
            if (snapshot.Server != ServerName)
                throw new ControlApiException(ControlApiFailure.MalformedResponse, "the review response named a different server");
            Snapshot = snapshot;
            RequiresReload = !snapshot.Pending || !ValidDigest(snapshot.PendingDigest);
            Notice = !snapshot.Pending ? "This server has no pending changes. Nothing was approved."
                : RequiresReload ? "This router did not provide a review snapshot. Reload before approving." : null;
        }
        catch (ControlApiException failure) { Failure = failure; }
    }

    public async Task<bool> ApproveAsync(CancellationToken cancellation = default)
    {
        if (Busy) return false;
        if (!CanApprove)
        {
            Failure = new(ControlApiFailure.Server, "Reload the held changes for this server before approving.", 428);
            return false;
        }
        var reviewed = Snapshot!;
        Busy = true;
        Failure = null;
        Notice = null;
        try
        {
            await client.ApprovePendingChangeAsync(ServerName, reviewed, cancellation);
            Snapshot = null;
            RequiresReload = true;
            return true;
        }
        catch (ControlApiException failure)
        {
            if (failure.Status == 409)
            {
                await LoadSnapshotAsync(cancellation);
                Notice = Snapshot is not null
                    ? "The pending tools changed. Review the refreshed diff before approving again. Nothing was approved by this request."
                    : "The pending tools changed and could not be refreshed. Reload the review before approving.";
            }
            else
            {
                Failure = failure;
                if (failure.Status == 428) RequiresReload = true;
            }
            return false;
        }
        finally { Busy = false; }
    }
}

public static class HeldChangePresentation
{
    public static string PrettyMetadata(string? raw)
    {
        if (raw is null) return "Not supplied by the router.";
        try { return JsonNode.Parse(raw)?.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) ?? raw; }
        catch (JsonException) { return "Metadata could not be parsed. Raw value:\n" + raw; }
    }

    public static IReadOnlyList<string> MetadataChanges(string? before, string? after)
    {
        try
        {
            var lines = new List<string>();
            Compare(JsonNode.Parse(before ?? "null"), JsonNode.Parse(after ?? "null"), "$", lines);
            return lines;
        }
        catch (JsonException) { return ["Metadata could not be compared. Read the complete raw values below."]; }
    }

    private static void Compare(JsonNode? before, JsonNode? after, string path, List<string> lines)
    {
        if (JsonNode.DeepEquals(before, after)) return;
        if (before is JsonObject oldObject && after is JsonObject newObject)
        {
            foreach (var name in oldObject.Select(pair => pair.Key).Union(newObject.Select(pair => pair.Key)).Order(StringComparer.Ordinal))
            {
                var child = path + "[" + JsonSerializer.Serialize(name) + "]";
                if (!oldObject.ContainsKey(name)) lines.Add("Adds " + child);
                else if (!newObject.ContainsKey(name)) lines.Add("Removes " + child);
                else Compare(oldObject[name], newObject[name], child, lines);
            }
        }
        else lines.Add("Changes " + path);
    }
}
