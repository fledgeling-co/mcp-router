import Foundation
import Network

/// A real HTTP server on loopback, for tests.
///
/// Not a mocked `URLSession`. A protocol stub replaces the thing under test — the request never
/// gets built, the response never gets parsed, and the header the router actually requires is
/// never actually sent. This serves real bytes over a real socket, so what the tests assert is
/// what a router would see.
///
/// `@unchecked Sendable` with a stated reason, per the house rule: every mutable field is guarded
/// by `lock`, and nothing else touches them. Network.framework delivers on its own queue, so some
/// synchronisation is unavoidable here; a lock is the smallest honest one.
final class HTTPStub: @unchecked Sendable {
    struct Response {
        var status: Int
        var body: String
        var contentType = "application/json"

        static func json(_ status: Int, _ body: String) -> Response {
            Response(status: status, body: body)
        }
    }

    /// A streamed response: a head, then lines emitted over time, then optionally a hard close.
    struct Stream {
        var lines: [String]
        var gap: TimeInterval = 0.02
        /// Drop the connection after the lines rather than ending cleanly.
        var thenDrop = false
    }

    private let listener: NWListener
    private let lock = NSLock()
    private var responses: [String: Response] = [:]
    private var tokenResponses: [(bearer: String, response: Response)] = []
    private var streamScript: Stream?
    private var recorded: [String] = []
    private var connectionCount = 0
    private var lastStreamLineAt: Date?

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    /// A scheme, a loopback host and a port always compose into a URL — there is no input here that
    /// can fail — so the fallback is unreachable rather than a default that could quietly stand in.
    var baseURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Every request head this stub received, newest last.
    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// How many connections were opened — the oracle for "retried exactly once".
    var connections: Int {
        lock.lock(); defer { lock.unlock() }
        return connectionCount
    }

    /// When the stub handed its **last** scripted line to the socket.
    ///
    /// The oracle for "streamed, not batched". Comparing a record's arrival against a wall-clock
    /// budget measured this instead: connection setup. On a contended CI runner the first record
    /// took 0.52s against a 0.36s bound and the test failed — while streaming perfectly, because
    /// most of that 0.52s was URLSession and the TCP handshake, not stream latency. Against this
    /// timestamp the question becomes an ordering one with no threshold to tune.
    var lastLineSentAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return lastStreamLineAt
    }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .global())
        waitUntilReady()
    }

    private func waitUntilReady() {
        for _ in 0 ..< 200 where port == 0 {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func stop() {
        listener.cancel()
    }

    /// Answer `METHOD /path` with this response. The key is matched on the request line.
    func on(_ method: String, _ path: String, _ response: Response) {
        lock.lock(); defer { lock.unlock() }
        responses["\(method) \(path)"] = response
    }

    /// Serve an event stream instead of a fixed body.
    func onStream(_ script: Stream) {
        lock.lock(); defer { lock.unlock() }
        streamScript = script
    }

    /// Answer any request carrying this `Authorization` value with this response, whatever the
    /// route.
    ///
    /// The route table alone cannot express "this credential is refused and that one is accepted",
    /// which is the entire shape of a rotation: one path answering differently depending on what
    /// was sent. Matched before the route table, so a stale token is refused on every endpoint the
    /// way a real router would refuse it.
    func onToken(_ bearer: String, _ response: Response) {
        lock.lock(); defer { lock.unlock() }
        tokenResponses.append((bearer, response))
    }

    private func lookup(_ head: String) -> (Response?, Stream?) {
        lock.lock(); defer { lock.unlock() }
        guard let requestLine = head.split(separator: "\r\n").first else { return (nil, nil) }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return (nil, nil) }
        let method = String(parts[0])
        // Strip the query; tests key on the path.
        let path = String(parts[1].split(separator: "?").first ?? parts[1])

        if path == "/usage/stream", let streamScript { return (nil, streamScript) }
        for (bearer, response) in tokenResponses where head.contains(bearer) {
            return (response, nil)
        }
        return (responses["\(method) \(path)"], nil)
    }

    private func handle(_ connection: NWConnection) {
        lock.lock(); connectionCount += 1; lock.unlock()

        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let head = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            lock.lock(); recorded.append(head); lock.unlock()

            let (response, script) = lookup(head)

            if let script {
                send(
                    connection,
                    head: "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
                        + "Connection: keep-alive\r\n\r\n"
                )
                DispatchQueue.global().async {
                    for (index, line) in script.lines.enumerated() {
                        Thread.sleep(forTimeInterval: script.gap)
                        // Terminated, and then some. `AsyncBytes.lines` yields nothing until it
                        // sees a newline, so a stub that sends bare text delivers one enormous
                        // line when the socket finally closes — which looks exactly like a client
                        // that buffers rather than streams. The blank line after it is the SSE
                        // frame terminator the router itself sends.
                        let isLast = index == script.lines.count - 1
                        if isLast {
                            self.lock.lock()
                            self.lastStreamLineAt = Date()
                            self.lock.unlock()
                        }
                        self.send(connection, head: line + "\n\n") {
                            // Cancelling straight after the loop would race the final write and
                            // truncate the last event — which reads in a test as "the stream
                            // dropped an event" rather than "the stub closed too early". A drop
                            // and a clean end are different conditions, so the close waits until
                            // the bytes are actually gone.
                            if isLast { connection.cancel() }
                        }
                    }
                }
                return
            }

            let answer = response ?? Response(status: 404, body: #"{"error":"no stub for this route"}"#)
            let bytes = Array(answer.body.utf8).count
            let payload = "HTTP/1.1 \(answer.status) \(Self.reason(answer.status))\r\n"
                + "Content-Type: \(answer.contentType)\r\n"
                + "Content-Length: \(bytes)\r\n"
                + "Connection: close\r\n\r\n"
                + answer.body
            send(connection, head: payload) { connection.cancel() }
        }
    }

    private func send(_ connection: NWConnection, head: String, then done: (@Sendable () -> Void)? = nil) {
        connection.send(
            content: Data(head.utf8),
            completion: .contentProcessed { _ in done?() }
        )
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 409: "Conflict"
        case 422: "Unprocessable Entity"
        default: "Status"
        }
    }
}
