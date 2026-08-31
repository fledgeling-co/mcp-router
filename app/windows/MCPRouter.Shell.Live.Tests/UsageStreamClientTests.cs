using System.Text;
using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// The SSE client against real loopback sockets, including the two golden files of bytes the
/// real router on this machine wrote over <c>GET /usage/stream</c> on 2026-08-31 (spec-WIN5
/// §7). The ladder is asserted through a recorded delay, never by waiting one out.
/// </summary>
public sealed class UsageStreamClientTests
{
    private static string GoldenPath(string fileName)
    {
        var dir = AppContext.BaseDirectory;
        var path = Path.Combine(dir, "Golden", fileName);
        Assert.True(File.Exists(path), $"golden capture missing from the build output: {fileName}");
        return path;
    }

    /// <summary>Everything the real router wrote, played back byte for byte.</summary>
    private static LoopbackServer ServingFile(string fileName, bool closeAfter = true)
    {
        var bytes = File.ReadAllBytes(GoldenPath(fileName));
        return new LoopbackServer(async (_, stream, cancellationToken) =>
        {
            await LoopbackServer.WriteSseHeadAsync(stream, cancellationToken);
            await stream.WriteAsync(bytes, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            if (closeAfter)
            {
                // Holding the socket half a second so a policy with a real minimum-healthy
                // duration still sees this connection as too short to reset the ladder.
                await Task.Delay(50, cancellationToken);
            }
        });
    }

    private static async Task<List<StreamEvent>> CollectAsync(
        UsageStreamClient client, int count, CancellationToken cancellationToken)
    {
        var events = new List<StreamEvent>();
        await foreach (var e in client.EventsAsync(cancellationToken))
        {
            events.Add(e);
            if (events.Count >= count) break;
        }
        return events;
    }

    private static readonly ReconnectPolicy TestPolicy = new()
    {
        InitialDelay = TimeSpan.FromMilliseconds(10),
        Ceiling = TimeSpan.FromMilliseconds(20),
        MaximumAttempts = 3,
        MinimumHealthyDuration = TimeSpan.FromMilliseconds(25),
    };

    [Fact]
    public async Task Golden_live_capture_decodes_to_its_records()
    {
        using var server = ServingFile("usage-stream-live.sse");
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy);

        var events = await CollectAsync(client, 3, CancellationToken.None);

        Assert.Equal(new StreamEvent.Phase(StreamPhase.Live), events[0]);
        var record = Assert.IsType<StreamEvent.Record>(events[1]);
        Assert.Equal("fixture", record.Value.Server);
        Assert.Equal("ping", record.Value.Tool);
        Assert.True(record.Value.Ok);
        Assert.Equal(186, record.Value.Ms);
        Assert.True(record.Value.Cold);
        Assert.Equal(32052, record.Value.Pid);
        Assert.Equal("node", record.Value.Client);
        // The Windows wire's own shape, from the machine's real bytes: no cwd, no project.
        Assert.Null(record.Value.Cwd);
        Assert.Null(record.Value.Project);
    }

    [Fact]
    public async Task Golden_error_capture_carries_a_failed_record_with_its_error()
    {
        using var server = ServingFile("usage-stream-err.sse");
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy);

        var events = await CollectAsync(client, 3, CancellationToken.None);

        var failure = Assert.IsType<StreamEvent.Record>(events[2]);
        Assert.False(failure.Value.Ok);
        Assert.Equal("unknown upstream server \"dieoncall\"", failure.Value.Err);
        Assert.Equal(CallResultKind.Failed, failure.Value.ResultKind);
        // The ok record in the same capture stays ok: classification reads each record alone.
        Assert.Equal(CallResultKind.Ok, Assert.IsType<StreamEvent.Record>(events[1]).Value.ResultKind);
    }

    [Fact]
    public async Task Comments_are_skipped_and_never_decoded()
    {
        // The greeting and the heartbeat are comments in both captures; the golden tests above
        // already prove no event and no malformed count came from them. This one pins the
        // malformed count at zero explicitly, because a parser that starts decoding comments
        // fails exactly this quietly.
        using var server = ServingFile("usage-stream-live.sse");
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy);

        await CollectAsync(client, 3, CancellationToken.None);

        Assert.Equal(0, client.MalformedRecords);
    }

    [Fact]
    public async Task One_malformed_record_is_skipped_and_counted_without_stopping_the_stream()
    {
        var good = Encoding.UTF8.GetBytes(
            "data: {\"ts\":\"2026-08-31T10:00:00Z\",\"server\":\"s\",\"tool\":\"t\",\"ok\":true,\"ms\":5,\"cold\":false}\n\n");
        var bad = Encoding.UTF8.GetBytes("data: {not json at all\n\n");
        var stream = Encoding.UTF8.GetBytes(": connected\n\n");
        using var server = new LoopbackServer(async (_, s, ct) =>
        {
            await LoopbackServer.WriteSseHeadAsync(s, ct);
            await s.WriteAsync(stream, ct);
            await s.WriteAsync(bad, ct);
            await s.WriteAsync(good, ct);
            await s.FlushAsync(ct);
            await Task.Delay(50, ct);
        });
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy);

        var events = await CollectAsync(client, 2, CancellationToken.None);

        Assert.Equal(1, client.MalformedRecords);
        Assert.IsType<StreamEvent.Record>(events[1]);
    }

    [Fact]
    public async Task A_refused_router_walks_the_ladder_then_reports_disconnected()
    {
        using var server = LoopbackServer.Refusing();
        var delays = new List<TimeSpan>();
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy)
        {
            Delay = (span, _) =>
            {
                delays.Add(span);
                return Task.CompletedTask;
            },
        };

        // 3 attempts, all refused: two Reconnecting phases with the ladder's delays between,
        // then the one phase that earns a button.
        var events = await CollectAsync(client, 3, CancellationToken.None);

        Assert.Equal(
            new[] { StreamPhase.Reconnecting, StreamPhase.Reconnecting, StreamPhase.Disconnected },
            events.OfType<StreamEvent.Phase>().Select(p => p.Value).ToArray());
        Assert.Equal(new[] { TimeSpan.FromMilliseconds(10), TimeSpan.FromMilliseconds(20) }, delays);
        Assert.Equal(3, server.Connections);
    }

    [Fact]
    public async Task A_connection_that_stayed_healthy_resets_the_ladder()
    {
        // First connection: greets, then holds past the minimum-healthy duration before
        // closing, so the policy reads it as having worked and resets the count. Second
        // connection: refused. The first delay of the new climb is the INITIAL delay, which is
        // only observable if the reset happened - a cumulative count would ask for 20ms.
        var bytes = Encoding.UTF8.GetBytes(": connected\n\n");
        var hold = TestPolicy.MinimumHealthyDuration + TimeSpan.FromMilliseconds(30);
        var refusedAfterFirst = false;
        using var server = new LoopbackServer(async (_, stream, cancellationToken) =>
        {
            if (refusedAfterFirst)
            {
                await LoopbackServer.WriteStatusAsync(stream, 503, cancellationToken);
                return;
            }

            await LoopbackServer.WriteSseHeadAsync(stream, cancellationToken);
            await stream.WriteAsync(bytes, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            await Task.Delay(hold, cancellationToken);
        });
        var delays = new List<TimeSpan>();
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy)
        {
            Delay = (span, _) =>
            {
                delays.Add(span);
                refusedAfterFirst = true;
                return Task.CompletedTask;
            },
        };

        // Live, then Reconnecting, Reconnecting: the second climb. The reset is observable
        // only in the delays - a cumulative count asks for 10ms then 20ms, a reset asks for
        // 10ms then 10ms again.
        var events = await CollectAsync(client, 4, CancellationToken.None);

        Assert.Equal(StreamPhase.Live, Assert.IsType<StreamEvent.Phase>(events[0]).Value);
        Assert.Equal(
            new[] { StreamPhase.Live, StreamPhase.Reconnecting, StreamPhase.Reconnecting, StreamPhase.Reconnecting },
            events.OfType<StreamEvent.Phase>().Select(p => p.Value).ToArray());
        // The worker runs one delay ahead of the consumer (the channel decouples them), so
        // what the reset proves is the SHAPE of the first two climbs: 10ms then 10ms again. A
        // cumulative count would have asked 10ms then 20ms.
        Assert.Equal(
            new[] { TestPolicy.InitialDelay, TestPolicy.InitialDelay },
            delays.Take(2).ToArray());
    }

    [Fact]
    public async Task The_ladder_holds_at_its_ceiling()
    {
        var policy = new ReconnectPolicy
        {
            InitialDelay = TimeSpan.FromSeconds(0.5),
            Ceiling = TimeSpan.FromSeconds(30),
            MaximumAttempts = 6,
        };

        Assert.Equal(TimeSpan.FromSeconds(0.5), policy.Delay(1));
        Assert.Equal(TimeSpan.FromSeconds(1), policy.Delay(2));
        Assert.Equal(TimeSpan.FromSeconds(2), policy.Delay(3));
        Assert.Equal(TimeSpan.FromSeconds(4), policy.Delay(4));
        Assert.Equal(TimeSpan.FromSeconds(8), policy.Delay(5));
        Assert.Equal(TimeSpan.FromSeconds(16), policy.Delay(6));
        Assert.Equal(TimeSpan.FromSeconds(30), policy.Delay(7));
        Assert.Equal(TimeSpan.FromSeconds(30), policy.Delay(33));
    }

    [Fact]
    public async Task The_backfill_decodes_newest_first()
    {
        using var server = new LoopbackServer((path, stream, cancellationToken) =>
        {
            Assert.StartsWith("/usage?limit=", path);
            var json = """
                {"since":"2026-08-31T09:00:00.000Z","records":[
                  {"ts":"2026-08-31T10:00:02.000Z","server":"b","tool":"second","ok":true,"ms":9,"cold":false},
                  {"ts":"2026-08-31T10:00:01.000Z","server":"a","tool":"first","ok":true,"ms":9,"cold":true}
                ]}
                """;
            return LoopbackServer.WriteJsonAsync(stream, json, cancellationToken);
        });
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy);

        var snapshot = await client.SnapshotAsync(CancellationToken.None);

        Assert.Equal("2026-08-31T09:00:00.000Z", snapshot.Since);
        Assert.Equal(2, snapshot.Records.Count);
        Assert.Equal("second", snapshot.Records[0].Tool);
        Assert.Equal("first", snapshot.Records[1].Tool);
    }

    [Fact]
    public async Task Cancelling_the_enumeration_ends_it_without_a_disconnected_phase()
    {
        var bytes = File.ReadAllBytes(GoldenPath("usage-stream-live.sse"));
        using var server = new LoopbackServer(async (_, stream, cancellationToken) =>
        {
            await LoopbackServer.WriteSseHeadAsync(stream, cancellationToken);
            await stream.WriteAsync(bytes, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                // The test is stopping the server; this connection ends with it.
            }
        });
        using var client = new UsageStreamClient(server.BaseUri, TestPolicy);

        var events = await CollectAsync(client, 2, CancellationToken.None);

        Assert.Equal(2, events.Count);
        Assert.DoesNotContain(events, e => e is StreamEvent.Phase { Value: StreamPhase.Disconnected });
    }
}
