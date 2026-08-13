import Foundation

/// What the live call log emits.
///
/// Phases are events rather than a separate observable property, so a consumer sees the ordering
/// exactly as it happened: the record that arrived before the drop, then the drop.
public enum StreamEvent: Equatable, Sendable {
    case record(CallRecord)
    case phase(StreamPhase)
}

/// The condition of the live connection.
///
/// Three states rather than a Bool, because "retrying" and "given up" call for different things
/// on screen: the first is information and the second is the only one that earns a button. A
/// consumer that cannot tell them apart either nags during a blip or goes quiet forever.
public enum StreamPhase: String, Equatable, Sendable, CaseIterable {
    case live
    case reconnecting
    case disconnected
}

/// How hard, and how long, to try reconnecting.
///
/// Stated as a value rather than left to the implementation so it can be asserted. An unbounded
/// retry is the failure this closes: it looks identical to a working stream that happens to be
/// quiet, so a router that has gone for good never gets reported.
public struct ReconnectPolicy: Equatable, Sendable {
    public var initialDelay: Duration
    public var ceiling: Duration
    public var maximumAttempts: Int

    public init(
        initialDelay: Duration = .milliseconds(500),
        ceiling: Duration = .seconds(30),
        maximumAttempts: Int = 6
    ) {
        self.initialDelay = initialDelay
        self.ceiling = ceiling
        self.maximumAttempts = maximumAttempts
    }

    /// The delay before attempt `n` (1-based), doubling and then holding at the ceiling.
    public func delay(forAttempt n: Int) -> Duration {
        guard n > 1 else { return initialDelay }
        let doublings = min(n - 1, 32)
        let scaled = initialDelay * Int(truncating: NSDecimalNumber(decimal: pow(2, doublings)))
        return scaled > ceiling ? ceiling : scaled
    }
}

/// Sleeping, made injectable so a test asserts the delays instead of waiting them out.
public protocol StreamClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct SystemStreamClock: StreamClock {
    public init() {}
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Records what it was asked to wait, and returns immediately.
public actor RecordingStreamClock: StreamClock {
    private var waits: [Duration] = []
    public init() {}
    public func sleep(for duration: Duration) async throws {
        waits.append(duration)
    }

    public func recorded() -> [Duration] {
        waits
    }
}

/// Opens `/usage/stream` and turns it into events.
///
/// The transport detail worth stating: the router keeps the connection alive with a comment line
/// every 25 seconds (`: ping`) and opens with `: connected`. Those are not events, and decoding
/// them would produce a stream of parse failures that look like a broken router. They are skipped
/// by the one rule the SSE format actually gives us — a line beginning with a colon is a comment.
public struct ControlEventStream: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let policy: ReconnectPolicy
    private let clock: any StreamClock
    private let tokenProvider: @Sendable () async -> String?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8879")!,
        session: URLSession = .shared,
        policy: ReconnectPolicy = ReconnectPolicy(),
        clock: any StreamClock = SystemStreamClock(),
        tokenProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.policy = policy
        self.clock = clock
        self.tokenProvider = tokenProvider
    }

    /// The events, until the consumer stops listening or the policy gives up.
    public func events() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let task = Task {
                var attempt = 0

                while !Task.isCancelled {
                    do {
                        let delivered = try await consumeOnce(continuation: continuation)
                        // A clean end of body is still a disconnection — the router closed us. But
                        // a connection that actually *talked* resets the count, because the policy
                        // bounds **consecutive** failures. Without this reset the counter is
                        // cumulative, and a stream that reconnected happily six times across a day
                        // would give up on the seventh for no reason the user could see.
                        attempt = delivered ? 0 : attempt + 1
                    } catch is CancellationError {
                        return
                    } catch {
                        attempt += 1
                    }

                    guard attempt < policy.maximumAttempts, !Task.isCancelled else {
                        continuation.yield(.phase(.disconnected))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.phase(.reconnecting))
                    do {
                        try await clock.sleep(for: policy.delay(forAttempt: attempt))
                    } catch {
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One connection's worth of events. Returns when the body ends; throws when it fails.
    ///
    /// The return value is whether the connection delivered anything at all — a line, of any kind,
    /// including a heartbeat comment. That is the observable difference between "the router is
    /// there and talking" and "the socket opened and nothing came", and it is what the retry
    /// counter resets on.
    @discardableResult
    private func consumeOnce(continuation: AsyncStream<StreamEvent>.Continuation) async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("usage/stream"))
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        continuation.yield(.phase(.live))
        var delivered = false

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            delivered = true
            // A comment. The heartbeat and the greeting both land here.
            if line.hasPrefix(":") { continue }
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty else { continue }
            guard let record = try? JSONDecoder().decode(CallRecord.self, from: Data(payload.utf8)) else {
                // One unreadable event is not a reason to tear down a working stream; the next
                // one may be fine. It is skipped rather than thrown so a single malformed record
                // cannot masquerade as the router going away.
                continue
            }
            continuation.yield(.record(record))
        }
        return delivered
    }
}
