using System.Net;
using System.Text;
using System.Text.Json;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests.Servers;

public sealed class HeldChangeReviewTests
{
    private const string Digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private const string ChangedDigest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    private static HeldChanges Snapshot(string? digest = Digest, string server = "a b/c") => new()
    {
        Server = server, Pending = true, PendingDigest = digest, Changes = [],
    };
    private static HttpResponseMessage Json(HttpStatusCode status, object body) => new(status)
    {
        Content = new StringContent(JsonSerializer.Serialize(body, ServersWire.Options), Encoding.UTF8, "application/json"),
    };
    private sealed class Wire(Func<HttpRequestMessage, HttpResponseMessage> answer) : HttpMessageHandler
    {
        public List<(string Method, string Path, string? Token, string Body)> Seen { get; } = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation)
        {
            Seen.Add((request.Method.Method, request.RequestUri!.PathAndQuery, request.Headers.Authorization?.ToString(),
                request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellation)));
            return answer(request);
        }
    }
    private static ControlApiClient Client(Wire wire, string token = "local-test-token") => new(tokenProvider: () => token, handler: wire);

    [Fact]
    public async Task ApprovalSendsOnlyTheExactReviewedDigestToTheEscapedSameServer()
    {
        using var wire = new Wire(_ => Json(HttpStatusCode.OK, new { server = "a b/c", approved = 0 }));
        using var client = Client(wire);
        var result = await client.ApprovePendingChangeAsync("a b/c", Snapshot());
        var seen = Assert.Single(wire.Seen);
        Assert.Equal("POST", seen.Method);
        Assert.Equal("/servers/a%20b%2Fc/approve", seen.Path);
        Assert.Equal("Bearer local-test-token", seen.Token);
        using var body = JsonDocument.Parse(seen.Body);
        Assert.Equal(Digest, body.RootElement.GetProperty("expectedDigest").GetString());
        Assert.Single(body.RootElement.EnumerateObject());
        Assert.Equal(0, result.Approved);
    }

    [Theory]
    [InlineData(null, "a b/c")]
    [InlineData("not-a-snapshot", "a b/c")]
    [InlineData(Digest, "different-server")]
    public async Task MissingSnapshotOrOtherServerFailsLocallyWithoutAnHttpWrite(string? digest, string server)
    {
        using var wire = new Wire(_ => throw new Exception("must not send"));
        using var client = Client(wire);
        var error = await Assert.ThrowsAsync<ControlApiException>(() => client.ApprovePendingChangeAsync("a b/c", Snapshot(digest, server)));
        Assert.Equal(428, error.Status);
        Assert.Empty(wire.Seen);
    }

    [Fact]
    public async Task AValidReviewWithNoControlTokenFailsLocally()
    {
        using var wire = new Wire(_ => throw new Exception("must not send"));
        using var client = Client(wire, "");
        var error = await Assert.ThrowsAsync<ControlApiException>(() => client.ApprovePendingChangeAsync("a b/c", Snapshot()));
        Assert.Equal(ControlApiFailure.Unauthorized, error.Kind);
        Assert.Empty(wire.Seen);
    }

    [Fact]
    public async Task StaleApprovalRefreshesTheDiffButRequiresAnotherExplicitApproval()
    {
        var digest = Digest;
        var posts = 0;
        using var wire = new Wire(request =>
        {
            if (request.Method == HttpMethod.Get) return Json(HttpStatusCode.OK, Snapshot(digest));
            posts++;
            if (posts == 1) { digest = ChangedDigest; return Json(HttpStatusCode.Conflict, new { error = "changed after review" }); }
            return Json(HttpStatusCode.OK, new { server = "a b/c", approved = 1 });
        });
        using var client = Client(wire);
        var review = new HeldChangeReview(client, "a b/c");
        await review.LoadAsync();
        Assert.False(await review.ApproveAsync());
        Assert.Equal(1, posts);
        Assert.Equal(ChangedDigest, review.Snapshot!.PendingDigest);
        Assert.Contains("Review the refreshed diff", review.Notice);
        Assert.Equal(new[] { "GET", "POST", "GET" }, wire.Seen.Select(request => request.Method));
        Assert.True(await review.ApproveAsync());
        Assert.Equal(2, posts);
        Assert.Contains(ChangedDigest, wire.Seen.Last().Body);
    }

    [Fact]
    public async Task A428IsNotRetriedAndDisablesApprovalUntilExplicitReload()
    {
        using var wire = new Wire(request => request.Method == HttpMethod.Get ? Json(HttpStatusCode.OK, Snapshot())
            : Json((HttpStatusCode)428, new { error = "review required" }));
        using var client = Client(wire);
        var review = new HeldChangeReview(client, "a b/c");
        await review.LoadAsync();
        Assert.False(await review.ApproveAsync());
        Assert.Equal(428, review.Failure!.Status);
        Assert.False(review.CanApprove);
        Assert.False(await review.ApproveAsync());
        Assert.Single(wire.Seen, request => request.Method == "POST");
        await review.LoadAsync();
        Assert.True(review.CanApprove);
    }

    [Fact]
    public async Task AReviewReadForAnotherServerCannotBecomeAnApproval()
    {
        using var wire = new Wire(_ => Json(HttpStatusCode.OK, Snapshot(server: "other")));
        using var client = Client(wire);
        var review = new HeldChangeReview(client, "a b/c");
        await review.LoadAsync();
        Assert.False(review.CanApprove);
        Assert.Equal(ControlApiFailure.MalformedResponse, review.Failure!.Kind);
        Assert.False(await review.ApproveAsync());
        Assert.DoesNotContain(wire.Seen, request => request.Method == "POST");
    }

    [Fact]
    public void CompleteMetadataDiffNamesOutputAnnotationsMetaAndInputChanges()
    {
        const string before = "{\"inputSchema\":{\"type\":\"object\",\"properties\":{}},\"outputSchema\":{\"type\":\"string\"},\"annotations\":{\"readOnlyHint\":true},\"_meta\":{\"audience\":\"user\"}}";
        const string after = "{\"inputSchema\":{\"type\":\"object\",\"properties\":{\"context\":{\"type\":\"string\"}}},\"outputSchema\":{\"type\":\"object\"},\"annotations\":{\"readOnlyHint\":false},\"_meta\":{\"audience\":\"assistant\"}}";
        var changes = HeldChangePresentation.MetadataChanges(before, after);
        Assert.Contains(changes, line => line.Contains("context"));
        Assert.Contains(changes, line => line.Contains("outputSchema"));
        Assert.Contains(changes, line => line.Contains("annotations"));
        Assert.Contains(changes, line => line.Contains("_meta"));
        Assert.Contains("assistant", HeldChangePresentation.PrettyMetadata(after));
        Assert.Contains("\n", HeldChangePresentation.PrettyMetadata(after));
        Assert.Empty(HeldChangePresentation.MetadataChanges("{\"x\":1,\"y\":2}", "{\"y\":2,\"x\":1}"));
        Assert.Contains("Raw value", HeldChangePresentation.PrettyMetadata("broken json"));
    }
}
