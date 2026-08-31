using System.Net;
using System.Net.Sockets;
using System.Text;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// A real loopback HTTP server, one TCP socket per connection, for tests that need the client
/// to cross an actual boundary.
///
/// This is not a stub of the router: the bytes a test writes here are the bytes
/// <see cref="UsageStreamClient"/> reads, over a real TCP connection through the real HTTP
/// stack, with nothing in between. Where the bytes matter most - the SSE framing the real
/// router writes - the tests feed the captured golden files verbatim.
/// </summary>
internal sealed class LoopbackServer : IDisposable
{
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _stopping = new();

    public LoopbackServer(Func<string, Stream, CancellationToken, Task> handler)
    {
        Handler = handler;
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        _ = Task.Run(() => AcceptLoopAsync(_stopping.Token));
    }

    private Func<string, Stream, CancellationToken, Task> Handler { get; }

    public int Port { get; }

    public Uri BaseUri => new($"http://127.0.0.1:{Port}/");

    private int _connections;

    /// <summary>Connections accepted since start, so a test can assert about reconnects.</summary>
    public int Connections => _connections;

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (SocketException)
            {
                return;
            }

            Interlocked.Increment(ref _connections);
            _ = Task.Run(async () =>
            {
                try
                {
                    using (client)
                    using (var stream = client.GetStream())
                    {
                        var path = await ReadRequestPathAsync(stream, cancellationToken);
                        await Handler(path, stream, cancellationToken);
                    }
                }
                catch (Exception) when (cancellationToken.IsCancellationRequested)
                {
                    // The server is being torn down mid-connection; the test already ended.
                }
                catch (IOException)
                {
                    // A client that hangs up mid-request is the test's business, not an error.
                }
            }, CancellationToken.None);
        }
    }

    /// <summary>Reads one HTTP request's head and returns the path+query. A minimal parser on
    /// purpose: the client sends exactly one request shape here.</summary>
    private static async Task<string> ReadRequestPathAsync(Stream stream, CancellationToken cancellationToken)
    {
        var buffer = new byte[16 * 1024];
        var head = new StringBuilder();
        while (!head.ToString().Contains("\r\n\r\n"))
        {
            var read = await stream.ReadAsync(buffer, 0, buffer.Length, cancellationToken);
            if (read == 0) break;
            head.Append(Encoding.ASCII.GetString(buffer, 0, read));
        }

        var firstLine = head.ToString().Split("\r\n")[0];
        var parts = firstLine.Split(' ');
        return parts.Length > 1 ? parts[1] : "/";
    }

    /// <summary>Writes a 200 SSE response head, then hands the body to the test.</summary>
    public static async Task WriteSseHeadAsync(Stream stream, CancellationToken cancellationToken)
    {
        var head = "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n" +
                   "cache-control: no-store\r\nconnection: keep-alive\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head), cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    public static async Task WriteJsonAsync(Stream stream, string json, CancellationToken cancellationToken)
    {
        var body = Encoding.UTF8.GetBytes(json);
        var head = $"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {body.Length}\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head), cancellationToken);
        await stream.WriteAsync(body, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    /// <summary>Writes a bare non-200 status. A client that retries a closed connection
    /// silently would make "refused mid-request" non-deterministic, so the ladder tests climb
    /// against the failure a real server can really serve: an answer, and not a 200.</summary>
    public static async Task WriteStatusAsync(Stream stream, int code, CancellationToken cancellationToken)
    {
        var head = $"HTTP/1.1 {code} nope\r\ncontent-length: 0\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head), cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    /// <summary>A handler that answers every request with a non-200 status - a transport
    /// failure from the client's point of view, and the ladder's climb.</summary>
    public static LoopbackServer Refusing() =>
        new((_, stream, ct) => WriteStatusAsync(stream, 500, ct));

    public void Dispose()
    {
        _stopping.Cancel();
        try
        {
            _listener.Stop();
        }
        catch (Exception)
        {
            // Stopping twice is harmless; the second call is this one.
        }

        _stopping.Dispose();
    }
}
