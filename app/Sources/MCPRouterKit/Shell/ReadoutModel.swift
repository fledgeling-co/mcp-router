import Foundation

/// The at-rest readout's numbers, and the only place in the shell a displayed figure is computed.
///
/// Every value here is one the router actually served. `DESIGN.md` §6 closes on the rule this type
/// exists to keep: *"Numbers the router does not observe are never displayed. There is no
/// fabricated memory saving anywhere in this app, because the router never runs the world where
/// every server is resident and so has nothing to subtract from."* There is accordingly nothing in
/// this type from which such a figure could be derived, and `ReadoutModelTests` asserts the
/// rendered strings carry no metric beyond the two counts and the trace.
///
/// The clock is passed in rather than read. A window that evicts on wall-clock time and is tested
/// against wall-clock time is a test that either sleeps for a minute or proves nothing; every
/// mutation here takes the instant it happens at, so the boundary can be driven exactly.
public struct ReadoutModel: Equatable, Sendable {
    /// One poll's answer, kept with the moment it arrived.
    public struct Sample: Equatable, Sendable {
        public let at: Date
        public let running: Int

        public init(at: Date, running: Int) {
            self.at = at
            self.running = running
        }
    }

    /// The trace's width. `DESIGN.md` and the brief both say the last 60 seconds.
    public static let window: TimeInterval = 60

    /// Child processes running, as of the last successful poll. **`nil` is not zero**: it means
    /// the router reported nothing, and a zero would be an observation nobody made.
    public private(set) var running: Int?
    /// Servers declared, from the same response.
    public private(set) var declared: Int?
    /// Declared servers whose tool surface could not be read — `MCPServer.indexError` is set.
    ///
    /// This is what makes `DESIGN.md` §5's Partial state real rather than decorative: the router
    /// tells us which servers failed to index and why, so the readout can say what arrived and
    /// what did not instead of presenting a short list as a complete one.
    public private(set) var notIndexed: Int?
    /// The samples still inside the window, oldest first.
    public private(set) var samples: [Sample]
    /// The condition replacing the counts, when the last poll failed.
    public private(set) var failure: ControlAPIError?

    public init(
        running: Int? = nil,
        declared: Int? = nil,
        notIndexed: Int? = nil,
        samples: [Sample] = [],
        failure: ControlAPIError? = nil
    ) {
        self.running = running
        self.declared = declared
        self.notIndexed = notIndexed
        self.samples = samples
        self.failure = failure
    }

    // MARK: - The two things that can happen

    /// A poll answered. The snapshot is authoritative for both counts, and contributes one sample.
    ///
    /// `running` counts servers the router reports as running — nothing is inferred about a server
    /// the response did not mention, which is the same rule `ServerStateTracker` keeps.
    public func applying(_ response: ServersResponse, at now: Date) -> ReadoutModel {
        applying(response.servers, at: now)
    }

    /// The same reading, taken from the servers alone.
    ///
    /// `ServerStateTracker.LoadState` carries `[MCPServer]` rather than the whole `ServersResponse`
    /// — deliberately, because a `.stale` snapshot corrected by call records is no longer any single
    /// response and presenting it as one would overstate it. Nothing above reads `port`, `idleMs`,
    /// `since` or `pendingAuth`, so this is the honest shape and the response overload delegates to
    /// it rather than the other way round.
    public func applying(_ servers: [MCPServer], at now: Date) -> ReadoutModel {
        let live = servers.filter(\.isRunning).count
        return ReadoutModel(
            running: live,
            declared: servers.count,
            notIndexed: servers.filter { $0.indexError != nil }.count,
            samples: Self.evicting(samples + [Sample(at: now, running: live)], at: now),
            failure: nil
        )
    }

    /// A poll failed.
    ///
    /// Two rules, and both are load-bearing. **No sample is appended** — a failed poll observed
    /// nothing, and writing a zero would draw a trace dropping to the floor for a router that may
    /// be running perfectly. And **the counts go absent rather than stale**: continuing to show the
    /// last good numbers presents them as current, which is a quieter lie than a zero but the same
    /// kind. The samples already collected stay, because they were real when they were taken; they
    /// still age out of the window on their own.
    public func applying(_ error: ControlAPIError, at now: Date) -> ReadoutModel {
        ReadoutModel(
            running: nil,
            declared: nil,
            notIndexed: nil,
            samples: Self.evicting(samples, at: now),
            failure: error
        )
    }

    private static func evicting(_ samples: [Sample], at now: Date) -> [Sample] {
        samples.filter { now.timeIntervalSince($0.at) <= window }
    }

    // MARK: - What the view asks it

    /// The router answered and has nothing declared. Distinct from `nil`, which is "no answer".
    public var isEmpty: Bool { declared == 0 }

    /// True once there is a count to show. The view renders the counts only here.
    public var hasCounts: Bool { running != nil && declared != nil }

    /// The highest simultaneous child-process count inside the window.
    public var peak: Int? { samples.map(\.running).max() }

    /// The span the samples actually cover, in seconds.
    ///
    /// This is what stops the footer claiming a minute it does not have. Twenty seconds after
    /// launch the trace holds twenty seconds, and saying "last 60s" there would be a statement
    /// about data that does not exist.
    public func observedSpan(at now: Date) -> TimeInterval? {
        guard let oldest = samples.first?.at else { return nil }
        return min(now.timeIntervalSince(oldest), Self.window)
    }

    /// The footer line: the window actually held, and the peak inside it.
    ///
    /// `nil` when there is nothing to describe, so the view omits the line rather than printing a
    /// sentence about an empty trace.
    public func traceLabel(at now: Date) -> String? {
        guard let span = observedSpan(at: now), let peak else { return nil }
        return "last \(Int(span.rounded()))s · peak \(peak)"
    }

    /// The trace as fractions of the window and of the peak, oldest first — `(x, y)` in `0...1`.
    ///
    /// Shaped here rather than in the view so the geometry is testable and so the view holds no
    /// arithmetic. An all-zero trace still returns points at `y == 0`; it never returns an empty
    /// path for a window that had samples in it.
    public func normalisedPoints(at now: Date) -> [(x: Double, y: Double)] {
        guard let oldest = samples.first?.at, let peak, peak > 0 else {
            return samples.map { _ in (x: 0, y: 0) }
        }
        let span = max(now.timeIntervalSince(oldest), 1)
        return samples.map { sample in
            (
                x: min(sample.at.timeIntervalSince(oldest) / span, 1),
                y: Double(sample.running) / Double(peak)
            )
        }
    }
}

// MARK: - The state the readout is in

/// Which of `DESIGN.md` §5's states the readout is rendering, as a value the view switches over.
///
/// A view that reconstructs this from three optionals gets it subtly wrong the first time someone
/// adds a fourth — "no counts" and "no answer yet" are different conditions with different copy,
/// and the difference between them is the whole of A18. Deriving it once, here, means the test can
/// drive the boundary and the view holds no logic to disagree with.
public enum ReadoutState: Equatable, Sendable {
    /// No answer has arrived yet. The skeleton renders — never a spinner (§5).
    case loading
    /// The router answered and declares nothing.
    case empty
    /// The router answered and some servers could not be indexed. `DESIGN.md` §5's Partial: say
    /// what arrived and what did not.
    case partial(running: Int, declared: Int, notIndexed: Int)
    /// The router answered and everything it declares was read.
    case populated(running: Int, declared: Int)
    /// The last poll failed. The condition's own copy renders, verbatim.
    case failed(ControlAPIError)
}

public extension ReadoutModel {
    /// The state this model puts the readout in.
    ///
    /// Order matters and is deliberate: a failure outranks stale counts, because the counts have
    /// already been cleared to `nil` by `applying(_ error:)` and rendering them would present an
    /// observation nobody made. `loading` is last among the count-free cases precisely because it
    /// is the *absence* of both an answer and a failure.
    var state: ReadoutState {
        if let failure { return .failed(failure) }
        guard let running, let declared else { return .loading }
        if declared == 0 { return .empty }
        if let notIndexed, notIndexed > 0 {
            return .partial(running: running, declared: declared, notIndexed: notIndexed)
        }
        return .populated(running: running, declared: declared)
    }
}

// MARK: - Badges

public extension Destination {
    /// This destination's badge count, from what the router served.
    ///
    /// Three rules, each one a clause. **`nil` servers means `nil` badge** — when the router is not
    /// running there is no observation, and a zero would be one (A18). **A destination with no
    /// `badgeSource` never gets a count**, whatever a caller passes, which is what keeps Skills bare
    /// (A13). And **zero renders no badge at all**: an empty badge is noise, not information, and
    /// every row would carry one.
    ///
    /// **`.queuedFromPhone` returns nil here, and that is the point rather than an omission.** The
    /// inbox queue is held by the app, not served on `MCPServer`, so there is nothing in `servers`
    /// from which to derive it — and deriving it from an unrelated array is exactly the fabrication
    /// this function exists to prevent. `ShellModel.badge(for:)` routes that case to
    /// `InboxBoardModel.waitingCount`, which counts the same rows the list renders.
    func badgeCount(from servers: [MCPServer]?) -> Int? {
        guard let badgeSource, let servers else { return nil }
        let count = switch badgeSource {
        case .serversNeedingAttention: servers.filter(\.needsAttention).count
        case .serversNeverUsed: servers.filter(\.neverUsed).count
        case .queuedFromPhone: 0
        }
        return count > 0 ? count : nil
    }
}
