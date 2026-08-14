import Foundation

/// Why the inbox could not be read.
///
/// Two cases, and they are different conditions with different recoveries: the stored queue itself
/// being unreadable is this Mac's problem, and the registry being unreachable means the queue is
/// intact but nothing in it can be described yet.
public enum InboxServiceError: Error, Equatable, Sendable {
    /// The stored queue could not be read. Reached only from an observed failure.
    case unreadable(detail: String)
    /// The queue is intact; the registry the items resolve against is not.
    case registryUnreadable(ControlAPIError)
}

/// What the inbox is, at one instant.
public struct InboxSnapshot: Sendable, Equatable {
    public let items: [InboxItem]
    /// The device that queued these, or `nil` when nothing is paired. **Not a default string** — a
    /// build with no pairing must not render a device name it never observed.
    public let pairedDeviceName: String?

    public init(items: [InboxItem], pairedDeviceName: String?) {
        self.items = items
        self.pairedDeviceName = pairedDeviceName
    }
}

/// The seam between the Mac's inbox surface and whatever delivers queued items.
///
/// **No live implementation ships in this item**, for the same reason I1 shipped none of
/// `PairingService`: the transport does not exist, and inventing a client for a wire nothing serves
/// would mean guessing at the delivery semantics the transport item then has to match. What ships is
/// this protocol, the envelope the wire carries (`InboxEnvelope`), and a fixture reaching every
/// designed state — so the surface is built and tested now and the transport implements against
/// something exact.
///
/// **Items arrive resolved.** The service, not the board, looks each item's registry entry up,
/// because resolution is where the security property lives: the Mac reads what a thing does rather
/// than believing what the phone said about it. A board that resolved its own rows could be handed
/// a pre-resolved item by a future caller and would have no way to tell.
public protocol InboxService: Sendable {
    func snapshot() async throws(InboxServiceError) -> InboxSnapshot

    /// Whether this Mac can be paired with at all. Synchronous: it is a fact about this build's
    /// transport, not a question anyone has to be asked.
    func availability() -> PairingAvailability

    /// How long a code minted against this service stays live.
    ///
    /// On the seam rather than as a constant read by the session model, because the near-expiry
    /// state is otherwise unreachable in the running app: a five-minute window cannot be driven by
    /// an acceptance script, and a scenario that differs from `paired` in no observable way is a
    /// state the matrix claims to cover and does not. The Phase D critic found exactly that —
    /// `.expiring` produced a snapshot identical to `.paired`, so the distinctness guard passed on
    /// arithmetic rather than on a difference.
    func pairingLifetime() -> TimeInterval
}

public extension InboxService {
    /// The real window, which every implementation but the near-expiry fixture wants.
    func pairingLifetime() -> TimeInterval {
        MacPairing.lifetime
    }
}

/// The inbox of a build that has no transport: empty, unpaired, and unpairable.
///
/// **This is not a fixture, and the distinction is the whole point.** A fixture stands in for
/// something real that is not wired up yet; this is the *correct and complete* implementation for a
/// build in which nothing can arrive and no phone can be paired, which is every Release build until
/// the transport item ships. Wiring Release to `FixtureInboxService(.none)` would give the same two
/// values today and would mean the shipping path referenced a type whose other seven scenarios
/// invent data — one environment variable away from rendering them. Release does not name the
/// fixture type at all.
public struct NoTransportInboxService: InboxService {
    public init() {}

    public func snapshot() async throws(InboxServiceError) -> InboxSnapshot {
        InboxSnapshot(items: [], pairedDeviceName: nil)
    }

    public func availability() -> PairingAvailability {
        .noEndpoint
    }
}

/// Every designed state, on demand, with no transport and no phone.
///
/// One scenario per otherwise-unreachable cell of `spec-M6.md`'s state matrix.
/// `InboxScenarioCoverageTests` enumerates the scenarios and asserts each produces a distinct
/// snapshot, so a state added later cannot quietly ship with no way to see it.
public struct FixtureInboxService: InboxService {
    public enum Scenario: String, Sendable, CaseIterable {
        /// No endpoint, nothing paired, nothing queued — **what a Release build does**, and the
        /// default.
        case none
        /// An endpoint, a live code, a populated inbox.
        case paired
        /// Paired and reachable, nothing queued.
        case pairedEmpty
        /// No answer yet. Not the same as an answer of none.
        case loading
        /// A code within seconds of expiry, for the countdown and the expired branch.
        case expiring
        /// One item whose registry entry could not be read.
        case partial
        /// The read failed.
        case failed
        /// An item whose name is wider than its column.
        case overflow
    }

    public let scenario: Scenario
    private let now: Date

    /// The endpoint the Debug scenarios pretend to have.
    ///
    /// Documented loudly because it is the one value in this item that would be a lie if it ever
    /// reached a user: a Release build never constructs it (`ShellPairingFactory` ignores the
    /// environment), and `PairingEndpoint`'s failable initialiser is what stops a malformed one
    /// existing anywhere.
    public static let fixtureEndpoint = PairingEndpoint(
        host: "192.168.1.24",
        port: 7333,
        fingerprint: "SHA256:5f2b9c0e"
    )

    public static let fixtureDevice = "Luke's iPhone"

    public init(_ scenario: Scenario = .none, now: Date = Date()) {
        self.scenario = scenario
        self.now = now
    }

    public func availability() -> PairingAvailability {
        switch scenario {
        case .none:
            .noEndpoint
        case .paired, .pairedEmpty, .loading, .expiring, .partial, .failed, .overflow:
            Self.fixtureEndpoint.map(PairingAvailability.available) ?? .noEndpoint
        }
    }

    /// A code that expires in seconds rather than minutes, so the countdown and the expired branch
    /// are reachable in the running app instead of only in a test with an injected clock.
    public func pairingLifetime() -> TimeInterval {
        scenario == .expiring ? 12 : MacPairing.lifetime
    }

    public func snapshot() async throws(InboxServiceError) -> InboxSnapshot {
        switch scenario {
        case .none:
            return InboxSnapshot(items: [], pairedDeviceName: nil)
        case .pairedEmpty:
            return InboxSnapshot(items: [], pairedDeviceName: Self.fixtureDevice)
        case .loading:
            // A request that never returns, matching `FixtureControlAPIClient.loading`. Cancellation
            // is how the caller leaves, which is what a `.task` teardown does.
            try? await Task.sleep(nanoseconds: .max)
            return InboxSnapshot(items: [], pairedDeviceName: Self.fixtureDevice)
        case .failed:
            throw .unreadable(detail: "the queue file could not be read")
        case .paired, .expiring:
            return try InboxSnapshot(items: Self.populated(at: now), pairedDeviceName: Self.fixtureDevice)
        case .partial:
            return try InboxSnapshot(
                items: Self.withUnresolved(at: now),
                pairedDeviceName: Self.fixtureDevice
            )
        case .overflow:
            return try InboxSnapshot(items: Self.withLongName(at: now), pairedDeviceName: Self.fixtureDevice)
        }
    }

    // MARK: - The rows

    /// The stdio entries this fixture resolves against, and why they are authored rather than
    /// recorded.
    ///
    /// The **recorded** `registry-search.json` holds three entries, all of them `http`.
    /// `RegistryCapability.statement` renders those as remote, which is honest but never reaches
    /// "Runs a program on this Mac" — the headline the review sheet exists for, and the one the
    /// security argument turns on. So two stdio entries are authored, in `Control/Authored/` where
    /// this codebase already keeps fixtures for states a capture cannot reach, rather than the
    /// recorded file being edited to pretend an index served something it did not.
    static let authoredStdioID = "authored:local-notes"
    static let authoredLongNameID = "authored:local-notes-long"

    static func envelope(
        id: String,
        entry: String,
        name: String,
        queuedAt: Date
    ) -> InboxEnvelope {
        InboxEnvelope(
            version: 1,
            id: id,
            entryID: entry,
            displayName: name,
            queuedAt: queuedAt,
            deviceName: fixtureDevice
        )
    }

    static func populated(at now: Date) throws(InboxServiceError) -> [InboxItem] {
        try [
            item(id: "q-1", entry: authoredStdioID, name: "Local notes", ago: 120, at: now),
            item(id: "q-2", entry: "smithery:deepwiki", name: "DeepWiki", ago: 3600, at: now)
        ]
    }

    /// One resolved item and one that could not be — the Partial state, which is `resolved == nil`
    /// rather than a flag beside it.
    static func withUnresolved(at now: Date) throws(InboxServiceError) -> [InboxItem] {
        try [
            item(id: "q-1", entry: authoredStdioID, name: "Local notes", ago: 120, at: now),
            item(
                id: "q-missing",
                entry: "smithery:withdrawn-entry",
                name: "Withdrawn entry",
                ago: 900,
                at: now
            )
        ]
    }

    static func withLongName(at now: Date) throws(InboxServiceError) -> [InboxItem] {
        try [
            item(
                id: "q-long",
                entry: authoredLongNameID,
                name: "Local notes, scratch drafts, and everything else in that one folder",
                ago: 60,
                at: now
            )
        ]
    }

    /// Builds one row, resolving its entry the way the real service will: by looking the coordinate
    /// up rather than by trusting the name the envelope carries.
    static func item(
        id: String,
        entry: String,
        name: String,
        ago: TimeInterval,
        at now: Date
    ) throws(InboxServiceError) -> InboxItem {
        try InboxItem(
            envelope: envelope(
                id: id,
                entry: entry,
                name: name,
                queuedAt: now.addingTimeInterval(-ago)
            ),
            resolved: resolve(entryID: entry)
        )
    }

    /// Reads one entry out of the authored and recorded fixtures, in that order.
    ///
    /// **Two failures live here and they are not the same one.** An entry that is genuinely not in
    /// either file returns `nil`, and the caller renders Partial — which is true, and is what the
    /// `partial` scenario's `smithery:withdrawn-entry` exercises. A registry file that is *missing
    /// or malformed* throws.
    ///
    /// The Phase D critic found these collapsed into one `try?`-and-`nil`, which meant a renamed
    /// resource made every row say "This entry could not be read" and the acceptance script's
    /// Partial assertions passed on it. A decode whose failure mode is a wrong screen is exactly
    /// what `SWIFT_PRACTICES.md` §2 forbids, and the Partial state was the wrong screen: it names
    /// the registry as the thing that lacks the entry, when in fact the app could not read the
    /// registry at all.
    static func resolve(entryID: String) throws(InboxServiceError) -> RegistryEntry? {
        for resource in ["inbox-entries", "registry-search"] {
            guard let entry = try entries(in: resource).first(where: { $0.id == entryID }) else {
                continue
            }
            return entry
        }
        return nil
    }

    /// Internal rather than private **so the missing-file branch can be exercised at all**.
    ///
    /// Both named resources are bundled, so nothing reachable through `resolve` ever takes that
    /// branch — a mutation replacing the throw with an empty array survived every test until this
    /// was callable with a name that is deliberately not there. A branch no test can reach is not
    /// covered by the tests that pass around it.
    static func entries(in resource: String) throws(InboxServiceError) -> [RegistryEntry] {
        guard let url = Bundle.module.url(
            forResource: resource,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
            ?? Bundle.module.url(forResource: resource, withExtension: "json", subdirectory: "Authored")
            ?? Bundle.module.url(forResource: resource, withExtension: "json")
        else {
            throw .registryUnreadable(
                .malformedResponse(detail: "the bundled registry fixture '\(resource).json' is missing")
            )
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RegistrySearchResponse.self, from: data).results
        } catch {
            throw .registryUnreadable(
                .malformedResponse(
                    detail: "the bundled registry fixture '\(resource).json' could not be read"
                )
            )
        }
    }
}
