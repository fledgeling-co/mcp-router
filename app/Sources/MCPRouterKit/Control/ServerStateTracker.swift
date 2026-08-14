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
    /// The router-level facts the last successful poll carried, kept alongside the servers and
    /// cleared by nothing. A surface needs the reap horizon to render a countdown and the pending
    /// flow to avoid offering an authorisation twice; both arrive on `ServersResponse` and both
    /// used to be dropped on the floor here.
    private var idleMs: Int?
    private var pendingAuth: PendingAuth?
    /// Whether any poll has ever succeeded.
    ///
    /// **Derived, not stored.** As a stored flag it duplicated a fact `loadKind` already carries,
    /// which made `(hasLoaded: false, loadKind: .stale)` and `(hasLoaded: true, loadKind: .failed)`
    /// representable in the actor's own storage — two states the type's whole design says cannot
    /// exist, held together only by one assignment being written correctly. Computing it leaves
    /// nothing to disagree.
    ///
    /// It cannot be replaced by `servers.isEmpty`: a successful poll returning no servers is the
    /// genuine *Empty* state, and treating emptiness as "never loaded" would render a fresh router
    /// with nothing declared as a hard failure. `SWIFT_PRACTICES.md` §2 names that exact shape —
    /// the TypeScript router already shipped it once, reading a flat `servers.json` as zero servers
    /// with no error at all.
    private var hasLoaded: Bool {
        switch loadKind {
        case .loading, .failed: false
        // `.stale` is only ever reached from a success, so it is itself the record of one.
        case .loaded, .stale: true
        }
    }

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
        streamCondition = stream == nil ? .notConfigured : .phase(.disconnected)
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

        /// The router's own reap horizon, in milliseconds, from the last poll that answered.
        ///
        /// Retained because a surface that renders "reaps in 200s" has to get that number from
        /// somewhere, and the only honest somewhere is the router. Without it the servers board
        /// would have to assume a horizon — the prototype assumes 300 seconds — and an assumed
        /// number displayed as an observation is exactly what `DESIGN.md` §6 forbids.
        ///
        /// `nil` until a poll has succeeded. It is deliberately **not** cleared by a failure, for
        /// the same reason the servers are not: a failure to refresh is not evidence that the
        /// router's configuration changed.
        public let idleMs: Int?

        /// An OAuth flow the router already has open, from the last poll that answered.
        ///
        /// The difference between "this server needs authorising" and "a browser window is already
        /// open waiting for you" — a surface that cannot tell those apart offers the button twice,
        /// and the second press abandons the first flow.
        public let pendingAuth: PendingAuth?

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

        public init(
            load: LoadState,
            stream: StreamCondition,
            idleMs: Int? = nil,
            pendingAuth: PendingAuth? = nil
        ) {
            self.load = load
            self.stream = stream
            self.idleMs = idleMs
            self.pendingAuth = pendingAuth
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
        return TrackerState(
            load: load,
            stream: streamCondition,
            idleMs: idleMs,
            pendingAuth: pendingAuth
        )
    }

    /// Updates, as they happen.
    ///
    /// Registration happens **synchronously**, before this returns. Deferring it into a `Task`
    /// leaves a window in which a failure and its recovery can both occur before the subscriber
    /// exists, so a surface subscribing at the wrong moment silently never learns the feed broke —
    /// which is the same invisible-failure shape this whole type was fixed to stop producing.
    public func updates() -> AsyncStream<TrackerState> {
        // Bounded, and this is the bound that matters rather than the dedup below. The dedup only
        // suppresses a state identical to the one before it, so a router flapping between
        // `.loaded` and `.stale` — the ordinary failing-router case, and the case this whole
        // feature is about — publishes distinct values forever. An `.unbounded` stream then grows
        // without limit behind a subscriber that is merely backgrounded. A surface renders the
        // present, so keeping the newest few and dropping the rest loses nothing it would draw.
        let (stream, continuation) = AsyncStream<TrackerState>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
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
        loadKind = .loaded
        // Router-level facts, kept so a surface can render a countdown from the router's own horizon
        // rather than from a number it made up.
        idleMs = response.idleMs
        pendingAuth = response.pendingAuth
        publish()
    }

    /// Apply a failed poll.
    ///
    /// The servers are deliberately **not** cleared. A failure to refresh is not evidence that the
    /// servers went away, and deleting what the user is reading in order to report a connection
    /// problem destroys data no source said was gone.
    /// It is published, not merely recorded. A failure stored and never broadcast leaves every
    /// subscribed surface frozen on the last good frame with no way to learn the feed has died —
    /// the same invisible failure as the original `try?`, one layer further out.
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

    /// Apply the server the router returned from a write.
    ///
    /// `PATCH /servers/:name` replies with the whole updated server, which is the router's own
    /// statement about one server at one instant — the same shape of evidence as a call record, and
    /// governed by the same precedence: a completed poll wins, because a poll is a statement about
    /// the whole world at the moment the router answered.
    ///
    /// **This is what makes a successful write visible in place** (`DESIGN.md` §5: "in-place state
    /// change; macOS does not toast a click"). Without it a surface has to either wait a whole poll
    /// interval, during which a toggle the user just moved sits showing its old value, or write the
    /// value it *expects* locally — and the expected value is the app's guess, which is exactly the
    /// invention this type refuses everywhere else. The value applied here was sent by the router.
    ///
    /// A name the last poll did not list is ignored, for the same reason `apply(record:)` ignores
    /// one: a write response is not licence to conjure a row.
    public func apply(updated server: MCPServer) {
        guard servers[server.name] != nil else { return }
        servers[server.name] = server
        publish()
    }

    /// Apply a phase reported by the stream.    ///
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
        //
        // Except when the iteration ended because *we* were cancelled. A deliberate teardown is
        // not a dropped stream, and reporting one would be the same lie in the other direction:
        // a `.disconnected` asserting a failure that did not happen, published to every subscriber
        // on the ordinary shutdown path. Nothing is reported, because after cancellation there is
        // no longer anyone whose question this answers.
        guard !Task.isCancelled else { return }
        apply(phase: .disconnected)
    }
}
