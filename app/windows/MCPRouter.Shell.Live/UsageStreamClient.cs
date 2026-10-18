using System.Net.Http.Json;
using System.Text.Json;

namespace MCPRouter.Shell.Live;

/// <summary>
/// The condition of the live connection, as events rather than a property, so a consumer sees
/// the ordering exactly as it happened: the record that arrived before the drop, then the drop.
/// The Mac's <c>StreamPhase</c>, one platform over.
/// </summary>
public enum StreamPhase
{
    /// <summary>Nothing has been established yet - the first connection is being made.</summary>
    Connecting,

    Live,

    /// <summary>The stream dropped and the ladder is mid-climb. Information, not an error:
    /// retrying is already happening.</summary>
    Reconnecting,

    /// <summary>The ladder was walked to its top and given up. The only phase that earns a
    /// button.</summary>
    Disconnected,
}

/// <summary>What the live call log emits: one record, or one change of phase.</summary>
public abstract record StreamEvent
{
    public sealed record Record(CallRecord Value) : StreamEvent;

    public sealed record Phase(StreamPhase Value) : StreamEvent;
}

/// <summary>
/// How hard, and how long, to try reconnecting. Stated as a value so it can be asserted.
///
/// The values are the Mac client's measured ones, kept rather than re-tuned: the
/// minimum-healthy duration is the part that does the real work. A router that accepts and
/// instantly drops delivers a line every time, so "delivered something" alone would reset the
/// consecutive-failure count and make the bound unreachable against exactly the failure it
/// exists to report. Five seconds is comfortably under the router's 25-second heartbeat, so a
/// healthy but silent stream still counts as healthy.
/// </summary>
public sealed record ReconnectPolicy
{
    public TimeSpan InitialDelay { get; init; } = TimeSpan.FromMilliseconds(500);

    public TimeSpan Ceiling { get; init; } = TimeSpan.FromSeconds(30);

    public int MaximumAttempts { get; init; } = 6;

    public TimeSpan MinimumHealthyDuration { get; init; } = TimeSpan.FromSeconds(5);

    /// <summary>The delay before attempt <paramref name="attempt"/> (1-based), doubling from the
    /// initial delay and then holding at the ceiling.</summary>
    public TimeSpan Delay(int attempt)
    {
        if (attempt <= 1) return InitialDelay;
        var doublings = Math.Min(attempt - 1, 32);
        var scaledMs = InitialDelay.TotalMilliseconds * Math.Pow(2, doublings);
        return scaledMs > Ceiling.TotalMilliseconds ? Ceiling : TimeSpan.FromMilliseconds(scaledMs);
    }
}

/// <summary>
/// Opens <c>GET /usage/stream</c> on the loopback control API and turns it into events, with
/// the reconnect ladder and the comment handling around it.
///
/// The transport details that matter, all measured against the real router (spec-WIN5 §2): the
/// stream opens with a <c>: connected</c> comment and stays alive on a <c>: ping</c> comment
/// every 25 seconds. A line beginning with a colon is a comment under the one rule the SSE
/// format itself gives, and decoding it would produce a stream of parse failures that look
/// like a broken router - so comments are skipped, never decoded. One record this version
/// cannot decode is skipped and counted, not thrown: a single malformed record must not
/// masquerade as the router going away, but it is counted by shape so the skip is never
/// silent.
///
/// The client carries no credential. The control API gates only mutating methods on its token
/// (<c>src/control.ts</c>, <c>handleControl</c>), every route this client reads is a GET, so
/// there is nothing to authenticate with and nothing to leak.
/// </summary>
public sealed class UsageStreamClient : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly HttpClient _http;
    private readonly Uri _baseUri;
    private readonly ReconnectPolicy _policy;

    /// <summary>Records this version could not decode, counted by shape and never by content.</summary>
    public int MalformedRecords { get; private set; }

    /// <summary>
    /// The delay, injectable so a test asserts the ladder instead of waiting it out. The
    /// default is the real clock.
    /// </summary>
    public Func<TimeSpan, CancellationToken, Task> Delay { private get; init; } =
        static (span, cancellationToken) => Task.Delay(span, cancellationToken);

    public UsageStreamClient(Uri? baseUri = null, ReconnectPolicy? policy = null, HttpClient? httpClient = null)
    {
        _baseUri = baseUri ?? new Uri("http://127.0.0.1:8879/");
        _policy = policy ?? new ReconnectPolicy();
        _http = httpClient ?? new HttpClient(new SocketsHttpHandler
        {
            PooledConnectionLifetime = TimeSpan.FromMinutes(2),
        });

        // The default is 100 seconds over the WHOLE response, body included, which would tear
        // a healthy but quiet stream down mid-read and look exactly like a router that left.
        _http.Timeout = Timeout.InfiniteTimeSpan;
    }

    /// <summary>The events, until the consumer stops listening or the ladder gives up.
    ///
    /// The ladder runs on a worker writing into a channel, and this enumerator reads the
    /// channel. The indirection is not style: an async iterator may not yield inside a try
    /// that has a catch clause, and the ladder is one long try around a live socket. The
    /// channel also gives the consumer a clean exit - walking away from the enumeration
    /// cancels the worker and closes the socket behind it.</summary>
    public async IAsyncEnumerable<StreamEvent> EventsAsync(
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var channel = System.Threading.Channels.Channel.CreateUnbounded<StreamEvent>(
            new System.Threading.Channels.UnboundedChannelOptions
            {
                SingleReader = true,
                SingleWriter = true,
            });

        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var worker = Task.Run(() => RunLadderAsync(channel.Writer, linked.Token), CancellationToken.None);

        try
        {
            await foreach (var e in channel.Reader.ReadAllAsync(linked.Token))
            {
                yield return e;
            }
        }
        finally
        {
            linked.Cancel();
            channel.Writer.TryComplete();
        }
    }

    /// <summary>The reconnect ladder itself. Writes every event the connection and the policy
    /// produce, then completes the channel - connected, records as they arrive, and either a
    /// disconnect at the top of the ladder or silence until the consumer walks away.</summary>
    private async Task RunLadderAsync(
        System.Threading.Channels.ChannelWriter<StreamEvent> writer,
        CancellationToken cancellationToken)
    {
        try
        {
            var attempt = 0;
            while (!cancellationToken.IsCancellationRequested)
            {
                var opened = System.Diagnostics.Stopwatch.StartNew();
                var deliveredAnyLine = false;
                var failed = false;

                try
                {
                    await foreach (var signal in ConsumeOnceAsync(cancellationToken)
                        .WithCancellation(cancellationToken))
                    {
                        switch (signal.Kind)
                        {
                            case SseKind.Opened:
                                await writer.WriteAsync(new StreamEvent.Phase(StreamPhase.Live), cancellationToken);
                                break;
                            case SseKind.Line:
                                deliveredAnyLine = true;
                                break;
                            case SseKind.Malformed:
                                MalformedRecords++;
                                break;
                            case SseKind.Rec:
                                await writer.WriteAsync(
                                    new StreamEvent.Record(signal.Value!), cancellationToken);
                                break;
                        }
                    }
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    return;
                }
                catch (Exception)
                {
                    // Every transport failure is one attempt. The message is deliberately
                    // dropped: the phase events are what the board draws, and an error string
                    // here would tempt a surface into paraphrasing the socket.
                    failed = true;
                }

                // A clean end of body is still a disconnection - the router closed us. But a
                // connection that actually talked resets the count, because the policy bounds
                // CONSECUTIVE failures; without the healthy-duration term a router that greets
                // and instantly drops would reset it every time.
                var healthy = !failed && deliveredAnyLine && opened.Elapsed >= _policy.MinimumHealthyDuration;
                attempt = healthy ? 0 : attempt + 1;

                if (attempt >= _policy.MaximumAttempts)
                {
                    await writer.WriteAsync(new StreamEvent.Phase(StreamPhase.Disconnected), cancellationToken);
                    return;
                }

                await writer.WriteAsync(new StreamEvent.Phase(StreamPhase.Reconnecting), cancellationToken);
                await Delay(_policy.Delay(attempt), cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // The consumer walked away, or the caller cancelled; either ends the ladder.
        }
        finally
        {
            writer.TryComplete();
        }
    }

    public async Task<UsageSnapshot> SnapshotAsync(CancellationToken cancellationToken = default)
    {
        using var response = await _http.GetAsync(
            new Uri(_baseUri, $"usage?limit={UsageSnapshot.Limit}"), cancellationToken);
        response.EnsureSuccessStatusCode();
        var snapshot = await response.Content.ReadFromJsonAsync<UsageSnapshot>(JsonOptions, cancellationToken);
        return snapshot ?? throw new InvalidOperationException("the usage response decoded to nothing");
    }

    private async IAsyncEnumerable<SseEvent> ConsumeOnceAsync(
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_baseUri, "usage/stream"));
        request.Headers.Accept.ParseAdd("text/event-stream");

        using var response = await _http.SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);

        // Anything but 200 ends this attempt and starts the ladder; a router serving 404 here
        // is a router this client has the wrong idea about, and the phase events say so.
        if (response.StatusCode != System.Net.HttpStatusCode.OK)
        {
            throw new HttpRequestException($"the usage stream answered {response.StatusCode}");
        }

        yield return new SseEvent(SseKind.Opened);

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new StreamReader(stream);

        while (await reader.ReadLineAsync(cancellationToken) is { } line)
        {
            // The greeting and the heartbeat both land here. This line still counts as
            // delivery - it is the observable difference between a router that is there and
            // talking and a socket that opened on nothing.
            if (line.StartsWith(':'))
            {
                yield return new SseEvent(SseKind.Line);
                continue;
            }

            if (!line.StartsWith("data:")) continue;

            var payload = line["data:".Length..].Trim();
            if (payload.Length == 0) continue;

            // Counted, not thrown, and never carried as text: the board has no use for the
            // payload it could not read, and a log of unread payloads is a log of
            // credentials-adjacent strings waiting to be printed.
            CallRecord? record = null;
            var malformed = false;
            try
            {
                record = JsonSerializer.Deserialize<CallRecord>(payload, JsonOptions);
            }
            catch (JsonException)
            {
                // An iterator may not yield from a catch; the flag carries it out.
                malformed = true;
            }

            if (malformed)
            {
                yield return new SseEvent(SseKind.Malformed);
                continue;
            }

            if (record is not null) yield return new SseEvent(SseKind.Rec, record);
        }
    }

    public void Dispose() => _http.Dispose();

    /// <summary>Internal framing signals one connection produces, translated into stream events above.</summary>
    private enum SseKind
    {
        Opened,
        Line,
        Malformed,
        Rec,
    }

    private readonly record struct SseEvent(SseKind Kind, CallRecord? Value = null);
}
