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
///
/// **What it reports when a source fails** is the other half, and the half this type originally
/// could not do at all. `DESIGN.md` §5 asks every data surface for nine states; a surface can only
/// render a state its data source can express. See `TrackerState`.
///
/// **Precedence, stated so it is a contract rather than an accident of scheduling.** A completed
/// poll wins over a call record, including a record that arrived while that poll was in flight.
/// The poll is a statement about the whole world at the moment the router answered; a record is a
/// statement about one server at one instant. Reconciling by arrival order instead would let a
/// record that predates the response survive it, which is the same class of lie as extrapolating.
public actor ServerStateTracker {
    private let client: any ControlAPIClient
    private let stream: ControlEventStream?
    private let pollInterval: Duration
    private let clock: any StreamClock

    private var servers: [String: MCPServer] = [:]
    private var order: [String] = []
    private var loadKind: LoadKind = .loading
    private var streamCondition: StreamCondition
    /// Whether any poll has ever succeeded.
    ///
    /// This is what makes `.failed` and `.stale` decidable, and it cannot be replaced by
    /// `servers.isEmpty`: a successful poll returning no servers is the genuine *Empty* state, and
    /// treating emptiness as "never loaded" would render a fresh router with nothing declared as a
    /// hard failure. `SWIFT_PRACTICES.md` §2 names that exact shape — the TypeScript router already
    /// shipped it once, reading a flat `servers.json` as zero servers with no error at all.
    private var hasLoaded = false
    private var continuations: [UUID: AsyncStream<TrackerState>.Continuation] = [:]
    /// The last snapshot actually broadcast, so an unchanged state is not re-sent.
    ///
    /// Without this a failing poll republishes an identical snapshot on every interval forever.
    /// `AsyncStream` buffers without bound by default, so a subscriber that is slow — or merely
    /// backgrounded — accumulates thousands of copies of one unchanging failure.
    private var lastPublished: TrackerState?
    /// Guards against a second `run()`.
    ///
    /// `run()` suspends at `waitForAll()`, which releases the actor: without this a second caller
    /// starts a second poll loop and a second stream consumer. Two loops overlap their requests,
    /// so an older response can land after a newer one and overwrite it, and every publication is
    /// doubled.
    private var isRunning = false

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
        // Decided once, here, and never guessed later. A tracker with no stream is polling-only by
        // construction, which is a supported configuration rather than a fault — so it must not be
        // born claiming a stream that dropped.
        self.streamCondition = stream == nil ? .notConfigured : .phase(.disconnected)
    }

    /// What the last poll produced, carrying the servers that belong to it.
    ///
    /// The distinction that earns the fourth case is `.failed` versus `.stale`. They carry the same
    /// error and mean opposite things to a surface: `.failed` means nothing has ever loaded, so the
    /// pane *is* the error; `.stale` means a poll did succeed, those servers are real, and only the
    /// refresh has broken — so the data stays and the error goes above it.
    ///
    /// A two-case ok/error model cannot express the second, and a surface built on one must either
    /// throw away good data to show a failure or hide a failure to keep the data. Both are wrong,
    /// and a stale snapshot under a live error is the most common real condition of the four.
    ///
    /// **The servers live inside the case rather than beside it** so that the combinations that
    /// would be lies cannot be built at all: there is no way to express `.loading` holding three
    /// servers, or `.failed` with rows behind it. A sibling `servers` property would leave both
    /// representable and rely on this actor never producing them, which is a weaker guarantee than
    /// the compiler's.
    public enum LoadState: Equatable, Sendable {
        /// No poll has completed yet. Distinct from `.loaded([])`, which is a successful read that
        /// found no servers.
        case loading
        /// The last poll succeeded, with the servers it returned — possibly none.
        case loaded([MCPServer])
        /// The last poll failed and none has ever succeeded. There is nothing behind this.
        case failed(ControlAPIError)
        /// The last poll failed, but an earlier one succeeded.
        ///
        /// The servers are **the last successful poll as corrected by any call records seen
        /// since** — not a frozen instant. A record arriving after the failure is still direct
        /// evidence that that server ran, so it is still applied; describing this as an untouched
        /// snapshot would overstate what is being shown.
        case stale([MCPServer], ControlAPIError)
    }

    /// Whether an event stream exists at all, and what it is doing if it does.
    ///
    /// `StreamPhase` is F3's and is deliberately not widened: it is `String`-raw-valued, and R4
    /// diffs F3's recorded fixtures against the Swift router, so adding a case to it would move a
    /// contract this feature has no business touching. Wrapping it says "there is no stream"
    /// without changing what a stream reports about itself.
    public enum StreamCondition: Equatable, Sendable {
        /// No event stream was supplied. Polling is the only source, by design — not a fault, and
        /// never to be rendered as a connection problem.
        case notConfigured
        /// A stream was supplied and is in this phase.
        case phase(StreamPhase)
    }

    /// What a surface renders.
    ///
    /// `load` and `stream` are two independent facts because they fail independently — a healthy
    /// poll with a dropped stream is ordinary, and folding them into one value would force a
    /// surface to lie about one of them. Both are `let`: a state handed to a surface is a reading,
    /// and a reading a caller can edit is not a reading.
    public struct TrackerState: Equatable, Sendable {
        public let load: LoadState
        public let stream: StreamCondition

        /// The servers to show, whatever the load state — empty when nothing has ever loaded.
        ///
        /// Derived rather than stored, so it cannot disagree with `load`.
        public var servers: [MCPServer] {
            switch load {
            case .loading, .failed: []
            case let .loaded(servers): servers
            case let .stale(servers, _): servers
            }
        }

        public init(load: LoadState, stream: StreamCondition) {
            self.load = load
            self.stream = stream
        }
    }

    /// The actor's own record of what the last poll did, without the payload — the servers are
    /// materialised into `LoadState` at the moment a state is read, so `apply(record:)` has one
    /// place to correct and cannot leave two copies disagreeing.
    private enum LoadKind: Equatable {
        case loading
        case loaded
        case failed(ControlAPIError)
        case stale(ControlAPIError)
    }

    public func state() -> TrackerState {
        let visible = order.compactMap { servers[$0] }
        let load: LoadState = switch loadKind {
        case .loading: .loading
        case .loaded: .loaded(visible)
        case let .failed(error): .failed(error)
        case let .stale(error): .stale(visible, error)
        }
        return TrackerState(load: load, stream: streamCondition)
    }

    /// Updates, as they happen.
    ///
    /// Registration happens **synchronously**, before this returns. Deferring it into a `Task`
    /// leaves a window in which a failure and its recovery can both occur before the subscriber
    /// exists, so a surface subscribing at the wrong moment silently never learns the feed broke —
    /// which is the same invisible-failure shape this whole type was fixed to stop producing.
    public func updates() -> AsyncStream<TrackerState> {
        let (stream, continuation) = AsyncStream<TrackerState>.makeStream()
        let id = UUID()
        register(id, continuation)
        // Termination is the one half that genuinely has to hop: that closure is `@Sendable` and
        // runs wherever the consumer let the stream go.
        continuation.onTermination = { _ in Task { await self.unregister(id) } }
        return stream
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
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - The two sources

    /// Apply a poll. The snapshot is authoritative for every field, including a server that has
    /// stopped — which is the only way a server ever leaves the running state, and including a
    /// call record that arrived while this poll was in flight.
    public func apply(poll response: ServersResponse) {
        var next: [String: MCPServer] = [:]
        var nextOrder: [String] = []
        for server in response.servers {
            next[server.name] = server
            nextOrder.append(server.name)
        }
        servers = next
        order = nextOrder
        hasLoaded = true
        loadKind = .loaded
        publish()
    }

    /// Apply a failed poll.
    ///
    /// The servers are deliberately **not** cleared. A failure to refresh is not evidence that the
    /// servers went away, and deleting what the user is reading in order to report a connection
    /// problem destroys data no source said was gone.
    public func apply(pollFailure error: ControlAPIError) {
        loadKind = hasLoaded ? .stale(error) : .failed(error)
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

    /// Apply a phase reported by the stream.
    ///
    /// A tracker with no stream ignores this. Without that guard a caller could put a polling-only
    /// tracker into `.phase(.live)`, which is the same lie as the one this type was fixed to stop
    /// telling, merely in the cheerful direction — a surface would draw a live indicator for a
    /// stream that does not exist.
    public func apply(phase newPhase: StreamPhase) {
        guard case let .phase(current) = streamCondition else { return }
        guard current != newPhase else { return }
        streamCondition = .phase(newPhase)
        publish()
    }

    // MARK: - Running it

    /// Poll and consume the stream until cancelled.
    ///
    /// Calling this twice is a no-op rather than a second set of loops; see `isRunning`.
    public func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

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
            do {
                let response = try await client.servers()
                apply(poll: response)
            } catch {
                // Typed: `client.servers()` is `throws(ControlAPIError)`, so the whole of F3's
                // distinction arrives intact — `routerNotRunning` and `unauthorized` stay different
                // things, and `.server` keeps the hint that is the difference between a dead end
                // and a next step. This was `try?`, which discarded all of it and retried in
                // silence, leaving every failure state unrenderable.
                apply(pollFailure: error)
            }
            // This `catch` means cancellation, not a failure to report: returning is correct.
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
        // Iteration ending means no further events will arrive — the stream gave up, or was torn
        // down. Leaving the condition at whatever it last reported would strand a surface showing
        // "live" over a feed that has stopped, which is the stream-shaped version of the pinned
        // `.disconnected` this feature exists to remove.
        apply(phase: .disconnected)
    }
}
