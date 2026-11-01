using System.Net;
using System.Text;
using MCPRouter.Shell.Model.Inbox;
using MCPRouter.Shell.Model.Servers;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class InboxLiveTests
{
    private sealed class Handler : HttpMessageHandler
    {
        public List<HttpRequestMessage> Requests = new();
        public List<string?> Bodies = new();
        public bool Refuse;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation)
        {
            Requests.Add(request);
            Bodies.Add(request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellation));
            if (Refuse) return new(HttpStatusCode.Conflict) { Content = new StringContent("{\"error\":\"reviewChanged\"}") };
            return new(HttpStatusCode.OK) { Content = new StringContent(request.Method == HttpMethod.Get ? """
                {"items":[{"id":"io.example/atlas","deviceName":"Phone","queuedAt":"2026-10-20T09:00:00Z","state":"waiting","resolved":null,"reviewDigest":"digest"}],"pairedDeviceNames":["Phone"]}
                """ : "{\"id\":\"io.example/atlas\",\"state\":\"declined\"}", Encoding.UTF8, "application/json") };
        }
    }

    [Fact] public async Task GatedReadPartialAndEscapedDecision()
    {
        var handler = new Handler();
        using var client = new ControlApiClient(tokenProvider: () => "session-token", handler: handler);
        var service = new RouterInboxService(client);
        var model = new InboxBoardModel(service);
        await model.LoadAsync();
        Assert.True(model.HasLoaded);
        Assert.Null(model.Error);
        Assert.Equal("Phone", model.PairedDeviceName);
        Assert.False(Assert.Single(model.AllItems).CanApprove);
        Assert.Equal("Bearer", handler.Requests[0].Headers.Authorization?.Scheme);
        await Assert.ThrowsAsync<ControlApiException>(() => service.DecideAsync("io.example/atlas", "accept", "digest"));
        Assert.Equal("/inbox/io.example%2Fatlas/accept", handler.Requests[1].RequestUri!.AbsolutePath);
        Assert.Contains("\"reviewDigest\":\"digest\"", handler.Bodies[1]);
    }

    [Fact] public async Task RefusedDecisionKeepsLastReadingAndNeverApproves()
    {
        var handler = new Handler();
        using var client = new ControlApiClient(tokenProvider: () => "token", handler: handler);
        var model = new InboxBoardModel(new RouterInboxService(client));
        await model.LoadAsync();
        handler.Refuse = true;
        await model.DecideAsync("io.example/atlas", "decline");
        Assert.NotNull(model.Error);
        Assert.Equal(DecisionState.Undecided, Assert.Single(model.AllItems).State);
        await model.LoadAsync();
        Assert.NotNull(model.Error);
        Assert.Single(model.AllItems);
    }
}
