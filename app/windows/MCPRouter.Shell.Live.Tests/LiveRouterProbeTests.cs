using System.Text;
using System.Text.Json;
using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// The S6 probe (plan-WIN5 §S6): the same client code, against a router that is actually
/// running. Opt-in, because a router nobody started is an environment this lane must not
/// pretend to have: name one with the <c>WIN5_LIVE_ROUTER</c> environment variable (the base
/// URL, e.g. <c>http://127.0.0.1:8979</c>) and the probe connects, walks the initialize dance
/// over plain HTTP to make one real failing call, and asserts the record arrives on the
/// running router's own <c>GET /usage/stream</c> and in its <c>GET /usage</c> backfill.
///
/// Without the variable the probe is a Skip - recorded as not-run, never as a pass. The
/// golden-file tests above are what runs on every ordinary invocation.
/// </summary>
public sealed class LiveRouterProbeTests
{
    /// <summary>
    /// A dynamic skip: xunit 2 has no Assert.Skip to call from a test body, so the skip is
    /// decided where xunit does read it - in the attribute. Without the variable the probe
    /// reports Skipped with the reason on it; it is never silently passed.
    /// </summary>
    private sealed class LiveRouterFactAttribute : FactAttribute
    {
        public LiveRouterFactAttribute()
        {
            if (Environment.GetEnvironmentVariable("WIN5_LIVE_ROUTER") is not { Length: > 0 } base_)
            {
                Skip = "no live router named by WIN5_LIVE_ROUTER - skipped, not passed";
            }
        }
    }

    [LiveRouterFact]
    public async Task The_running_routers_stream_and_backfill_carry_a_call_this_probe_made()
    {
        var baseUri = Environment.GetEnvironmentVariable("WIN5_LIVE_ROUTER");
        Assert.False(string.IsNullOrWhiteSpace(baseUri), "probe ran without a router to name");

        var mark = $"probe{DateTimeOffset.UtcNow:HHmmss}";
        using var http = new HttpClient { BaseAddress = new Uri($"{baseUri.TrimEnd('/')}/") };

        // One real call through the router, over the same JSON-RPC-over-HTTP surface the
        // harnesses use: initialize, then tools/call against an upstream that does not exist.
        // The failing call is deliberate - it exercises the err path of the record without
        // depending on what any fixture answers.
        await JsonRpcAsync(http, "initialize", new
        {
            protocolVersion = "2025-03-26",
            capabilities = new { },
            clientInfo = new { name = "win5-live-probe", version = "1.0.0" },
        });
        await JsonRpcAsync(http, "notifications/initialized", null);
        var result = await JsonRpcAsync(http, "tools/call", new
        {
            name = $"{mark}__nope",
            arguments = new { },
        });
        Assert.True(result.TryGetProperty("result", out var callResult)
            && callResult.TryGetProperty("isError", out var isError)
            && isError.GetBoolean(),
            "the router should answer a call to an unknown upstream with a tool error");

        // The stream, through the board's own client. A record the router writes for the call
        // above must arrive here, live, decoded into the same CallRecord the board renders.
        using var client = new UsageStreamClient(new Uri($"{baseUri.TrimEnd('/')}/"), new ReconnectPolicy
        {
            InitialDelay = TimeSpan.FromMilliseconds(100),
            Ceiling = TimeSpan.FromMilliseconds(200),
            MaximumAttempts = 3,
        });
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        CallRecord? live = null;
        var sawLivePhase = false;
        await foreach (var e in client.EventsAsync(cts.Token))
        {
            switch (e)
            {
                case StreamEvent.Phase { Value: StreamPhase.Live }:
                    sawLivePhase = true;
                    break;
                case StreamEvent.Record r when r.Value.Server == mark:
                    live = r.Value;
                    break;
            }

            if (sawLivePhase && live is not null) break;
        }

        Assert.True(sawLivePhase, "the running router never reached the live phase");
        Assert.NotNull(live);
        Assert.Equal(mark, live!.Server);
        Assert.Equal("nope", live.Tool);
        Assert.False(live.Ok);
        Assert.False(string.IsNullOrEmpty(live.Err));

        // The backfill, through the same client: the call is in the router's tail as well, so
        // the board's two halves agree on a router that is actually running.
        var snapshot = await client.SnapshotAsync(cts.Token);
        Assert.Contains(snapshot.Records, r => r.Server == mark && r.Tool == "nope" && !r.Ok);
    }

    /// <summary>One JSON-RPC POST, keeping the session header the router assigns on initialize.</summary>
    private static async Task<JsonElement> JsonRpcAsync(HttpClient http, string method, object? @params)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "mcp");
        request.Headers.Accept.ParseAdd("application/json");
        request.Headers.Accept.ParseAdd("text/event-stream");
        // A notification carries no id member at all - an explicit null makes it a request with
        // a null id, which the router rightly answers 400.
        var isNotification = method.StartsWith("notifications", StringComparison.Ordinal);
        var payload = isNotification
            ? JsonSerializer.Serialize(new { jsonrpc = "2.0", method })
            : JsonSerializer.Serialize(new { jsonrpc = "2.0", id = 1, method, @params });
        request.Content = new StringContent(payload, Encoding.UTF8, "application/json");

        using var response = await http.SendAsync(request);
        response.EnsureSuccessStatusCode();
        if (response.Headers.TryGetValues("mcp-session-id", out var values))
        {
            http.DefaultRequestHeaders.Remove("mcp-session-id");
            http.DefaultRequestHeaders.Add("mcp-session-id", values);
        }

        if (method.StartsWith("notifications", StringComparison.Ordinal))
        {
            return default;
        }

        var body = await response.Content.ReadAsStringAsync();
        // Streamable HTTP may answer in SSE framing when the Accept header offers it - the body
        // is `event: message\n` then `data: {...}`. The payload is whichever line carries it.
        if ((response.Content.Headers.ContentType?.MediaType ?? "").StartsWith("text/event-stream",
                StringComparison.OrdinalIgnoreCase) || body.StartsWith("event:", StringComparison.Ordinal))
        {
            foreach (var line in body.Split('\n'))
            {
                if (line.StartsWith("data:", StringComparison.Ordinal))
                {
                    return JsonSerializer.Deserialize<JsonElement>(line["data:".Length..].Trim());
                }
            }

            throw new InvalidOperationException("the router's SSE reply carried no data line");
        }

        return JsonSerializer.Deserialize<JsonElement>(body);
    }
}
