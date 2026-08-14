import Foundation

/// Keeps a live view of which servers are running.
///
/// **Why this is a merge rather than a subscription.** The router publishes no server-state feed.
/// It answers `GET /servers` with a snapshot, and it streams call records on `/usage/stream` —
/// that is the whole of what it observes. So "live" here is those two things combined, and
/// nothing else: a timed refresh for the truth, and arriving calls to correct it between refreshes.
///
/// The rule that keeps this honest is that neither source is ever extrapolated. A call record for
/// a server proves that server ran a tool at that moment, so it is marked running. A poll is the
/// authority for every field including state, so it can move a server back to idle. A server that
/// appears in neither is not invented, and no figure is derived that neither source measured —
/// there is no computed memory saving here, because the router never runs the world it would have
/// to be subtracted from.
public actor ServerStateTracker {
    private let client: any ControlAPIClient
    private let stream: ControlEventStream?
    private let pollInterval: Duration
    private let clock: any StreamClock

    private var servers: [String: MCPServer] = [:]
    private var order: [String] = []
    private var phase: StreamPhase = .disconnected
    private var continuations: [UUID: AsyncStream<TrackerState>.Continuation] = [:]

    public init(
        client: any ControlAPIClient,
        stream: ControlEventStream? = nil,
        pollInterval: Duration = .seconds(5),
        clock: any StreamClock = SystemStreamClock()
    ) {
        self.client = client
        self.stream = stream
        self.pollInterval = pollInterval
        self.clock = clock
    }

    /// What a surface renders: the servers in the router's own order, and the stream's condition.
    public struct TrackerState: Equatable, Sendable {
        public var servers: [MCPServer]
        public var phase: StreamPhase
    }

    public func state() -> TrackerState {
        TrackerState(servers: order.compactMap { servers[$0] }, phase: phase)
    }

    /// Updates, as they happen.
    public func updates() -> AsyncStream<TrackerState> {
        AsyncStream { continuation in
            let id = UUID()
            // No `await`: this `Task` inherits the actor's isolation, so the call is already on it.
            // The termination handler below is a different matter — that closure is `@Sendable` and
            // runs wherever the consumer let the stream go, so it genuinely has to hop back.
            Task { self.register(id, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id) } }
        }
    }

    private func register(_ id: UUID, _ continuation: AsyncStream<TrackerState>.Continuation) {
        continuations[id] = continuation
        continuation.yield(state())
    }

    private func unregister(_ id: UUID) {
        continuations[id] = nil
    }

    private func publish() {
        let snapshot = state()
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - The two sources

    /// Apply a poll. The snapshot is authoritative for every field, including a server that has
    /// stopped — which is the only way a server ever leaves the running state.
    public func apply(poll response: ServersResponse) {
        var next: [String: MCPServer] = [:]
        var nextOrder: [String] = []
        for server in response.servers {
            next[server.name] = server
            nextOrder.append(server.name)
        }
        servers = next
        order = nextOrder
        publish()
    }

    /// Apply one call record. A call proves the server was running when it happened, so a server
    /// the last poll called idle is corrected — but only for a server the poll actually listed. A
    /// record naming something undeclared is ignored rather than conjuring a row for a server the
    /// router never reported.
    public func apply(record: CallRecord) {
        guard var server = servers[record.server] else { return }
        guard server.state != .running else { return }
        server.state = .running
        servers[record.server] = server
        publish()
    }

    public func apply(phase newPhase: StreamPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        publish()
    }

    // MARK: - Running it

    /// Poll and consume the stream until cancelled.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.pollLoop() }
            if stream != nil {
                group.addTask { [weak self] in await self?.consumeStream() }
            }
            await group.waitForAll()
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            if let response = try? await client.servers() {
                apply(poll: response)
            }
            do { try await clock.sleep(for: pollInterval) } catch { return }
        }
    }

    private func consumeStream() async {
        guard let stream else { return }
        for await event in stream.events() {
            switch event {
            case let .record(record): apply(record: record)
            case let .phase(newPhase): apply(phase: newPhase)
            }
        }
    }
}
