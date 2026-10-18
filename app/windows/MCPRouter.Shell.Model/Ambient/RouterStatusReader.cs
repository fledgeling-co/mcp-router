using MCPRouter.Shell.Model.Registry;

namespace MCPRouter.Shell.Model.Ambient;

/// <summary>
/// Reads the router's <c>/status</c> over the loopback control port - the live answer to "what is
/// the router doing" that the ambient surface renders.
/// </summary>
/// <remarks>
/// <para>The endpoint is resolved PER READ through <see cref="ControlEndpoint.BaseUrl"/> rather
/// than captured once, for the same reason the Servers board resolves it that way: the port is
/// the router's own configured value out of <c>servers.json</c>, and a reader that froze it at
/// construction would go on polling a port the machine had stopped using.</para>
///
/// <para><c>/status</c> is ungated (<c>src/router.ts</c> answers it ahead of the control block),
/// so this reader sends no token and never touches <c>control.token</c>.</para>
/// </remarks>
public sealed class RouterStatusReader : IAmbientRouterReader, IDisposable
{
    private readonly HttpClient _http;
    private readonly Func<string> _baseUrl;

    public RouterStatusReader(Func<string>? baseUrl = null, HttpMessageHandler? handler = null)
    {
        _baseUrl = baseUrl ?? ControlEndpoint.BaseUrl;
        _http = new HttpClient(handler ?? new HttpClientHandler())
        {
            // Shorter than the Servers board's three seconds: this poll runs every couple of
            // seconds and a slow answer that arrives after the next one has been asked for is
            // worse than no answer.
            Timeout = TimeSpan.FromSeconds(2),
        };
    }

    /// <summary>The last thing this reader did, for a log line. Never carries a token.</summary>
    public string LastDetail { get; private set; } = "nothing has been read";

    public async Task<AmbientReading> ReadAsync(CancellationToken cancellation = default)
    {
        var url = _baseUrl().TrimEnd('/') + "/status";
        try
        {
            using var response = await _http.GetAsync(url, cancellation).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                // An answer this reader did not expect says the thing on that port is not the
                // router it knows, which is not the same as an idle router.
                LastDetail = $"{url} answered {(int)response.StatusCode}";
                return AmbientReading.Unreachable;
            }
            var body = await response.Content.ReadAsStringAsync(cancellation).ConfigureAwait(false);
            var reading = AmbientStatusMapping.FromStatusJson(body);
            LastDetail = $"{url} answered 200: {reading.State}, "
                + $"{reading.ActiveCallCount} in flight, {reading.WaitingCount} waiting";
            return reading;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or OperationCanceledException or UriFormatException)
        {
            LastDetail = $"{url} did not answer ({ex.GetType().Name})";
            return AmbientReading.Unreachable;
        }
    }

    public void Dispose() => _http.Dispose();
}
