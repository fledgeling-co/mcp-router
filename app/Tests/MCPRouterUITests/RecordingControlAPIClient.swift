import Foundation
import MCPRouterKit

/// A `ControlAPIClient` that records what was called on it, wrapping a real one.
///
/// **It lives in the test target, not in the Kit.** It was written into
/// `MCPRouterKit/Inbox/` and the Phase D critic was right to call that out: nothing in either app
/// references it, so shipping it meant a test instrument inside the product binary — where a later
/// caller could reach for it and where it counts toward the shipping surface for no benefit. The
/// fixtures next to it are a different case and stay: those are *selectable* by a Debug scenario
/// and exist to render designed states. This one only counts calls.
///
/// **Why a decorator rather than a stub.** The assertion M6 needs is not "the row disappeared" — a
/// local mutation looks identical to an install from the outside. It is *"`add` was called exactly
/// once, with `force == false`, and nothing else called it at all"*. A test that watches the UI
/// cannot tell those apart, and a stub that returns canned answers still cannot count.
///
/// So this forwards everything to a wrapped client and counts the calls that matter on the way
/// through. The forwarding is what keeps it honest: the surface under test is talking to the same
/// fixture it would talk to anyway, and the recording is a side effect rather than a substitute.
///
/// It is `@unchecked Sendable` **with its mutable state behind a lock**, which is the only shape in
/// which that annotation is honest (`SWIFT_PRACTICES.md` §1). The lock is here rather than an actor
/// because `ControlAPIClient` is not an actor-isolated protocol, and making this one would change
/// every call site's isolation to prove a property about a test double. `NSLock` and a scoped
/// `withLock`, for exactly the reason `D-p` recorded: `lock()`/`unlock()` are unavailable from an
/// async context, and an unsynchronised `var` under `@unchecked Sendable` is the data race that was
/// mislabelled a flake once already in this repo.
public final class RecordingControlAPIClient: ControlAPIClient, @unchecked Sendable {
    /// One record per call worth counting.
    public struct Calls: Sendable, Equatable {
        public var add = 0
        public var addForced = 0
        public var remove = 0
        public var searchRegistry = 0
        public var pairingIssue = 0
        public var pairingRevoke = 0
        public var promotions: [String] = []
        public var undos: [String] = []
        public var pairingPhoneRevokes: [String] = []
        public var pairingStateReads = 0

        public init() {}
    }

    private let wrapped: any ControlAPIClient
    private let extraUpdates: [ExtensionUpdateEntry]
    private let hideStoredUpdates: Bool
    private let refusedPromotions: Set<String>
    private let refusedUndos: Set<String>
    /// Holds a pairing issue in flight after it is counted, so a test can close the sheet while the
    /// router is still answering.
    private let issueGate: (@Sendable () async -> Void)?
    /// Replaces the listener the wrapped router reports, so a test can show the sheet a router with pairing
    /// off.
    private let listener: PairingListener?
    /// Makes the state read fail, so a test can show the sheet a router it cannot read.
    private let stateFailure: ControlAPIError?
    private let pairingStateOverride: (@Sendable () async throws(ControlAPIError) -> PairingState)?
    private let phoneRevokeOverride: (@Sendable (String) async throws(ControlAPIError) -> String)?
    private let lock = NSLock()
    private var _calls = Calls()

    public var calls: Calls {
        lock.withLock { _calls }
    }

    public init(
        wrapping wrapped: any ControlAPIClient,
        issueGate: (@Sendable () async -> Void)? = nil,
        extraUpdates: [ExtensionUpdateEntry] = [],
        hideStoredUpdates: Bool = false,
        refusedPromotions: Set<String> = [],
        refusedUndos: Set<String> = [],
        listener: PairingListener? = nil,
        stateFailure: ControlAPIError? = nil,
        pairingStateOverride: (@Sendable () async throws(ControlAPIError) -> PairingState)? = nil,
        phoneRevokeOverride: (@Sendable (String) async throws(ControlAPIError) -> String)? = nil
    ) {
        self.wrapped = wrapped
        self.issueGate = issueGate
        self.extraUpdates = extraUpdates
        self.hideStoredUpdates = hideStoredUpdates
        self.refusedPromotions = refusedPromotions
        self.refusedUndos = refusedUndos
        self.listener = listener
        self.stateFailure = stateFailure
        self.pairingStateOverride = pairingStateOverride
        self.phoneRevokeOverride = phoneRevokeOverride
    }

    private func record(_ mutate: (inout Calls) -> Void) {
        lock.withLock { mutate(&_calls) }
    }

    // MARK: - The calls this item asserts on

    public func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
        record {
            $0.add += 1
            // Counted separately rather than as a boolean: "was forced at least once" and "how many
            // adds were forced" are different questions, and a flag would answer neither after two
            // calls.
            if force { $0.addForced += 1 }
        }
        return try await wrapped.add(server, force: force)
    }

    public func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
        record { $0.remove += 1 }
        return try await wrapped.remove(name, keepHistory: keepHistory)
    }

    public func searchRegistry(
        query: String,
        limit: Int
    ) async throws(ControlAPIError) -> RegistrySearchResponse {
        record { $0.searchRegistry += 1 }
        return try await wrapped.searchRegistry(query: query, limit: limit)
    }

    // MARK: - Pairing

    public func issuePairingCode() async throws(ControlAPIError) -> IssuedPairingCode {
        record { $0.pairingIssue += 1 }
        if let issueGate { await issueGate() }
        return try await wrapped.issuePairingCode()
    }

    public func pairingState() async throws(ControlAPIError) -> PairingState {
        record { $0.pairingStateReads += 1 }
        if let stateFailure { throw stateFailure }
        let state: PairingState = if let pairingStateOverride {
            try await pairingStateOverride()
        } else {
            try await wrapped.pairingState()
        }
        return PairingState(
            code: state.code,
            listener: listener ?? state.listener,
            confirmedPhones: state.confirmedPhones
        )
    }

    public func revokePairedPhone(id: String) async throws(ControlAPIError) -> String {
        record { $0.pairingPhoneRevokes.append(id) }
        if let phoneRevokeOverride { return try await phoneRevokeOverride(id) }
        return try await wrapped.revokePairedPhone(id: id)
    }

    public func revokePairingCode() async throws(ControlAPIError) -> Bool {
        record { $0.pairingRevoke += 1 }
        return try await wrapped.revokePairingCode()
    }

    public func promoteFromCache(
        _ name: String,
        pluginVersion: String
    ) async throws(ControlAPIError) -> PromotionAck {
        record { $0.promotions.append(name) }
        if refusedPromotions.contains(name) {
            throw .server(status: 409, message: "cache entry changed", hint: "Review the new version")
        }
        return try await wrapped.promoteFromCache(name, pluginVersion: pluginVersion)
    }

    public func undoPromotion(
        _ name: String,
        kind: StoredExtensionKind,
        restore: String
    ) async throws(ControlAPIError) -> UndoAck {
        record { $0.undos.append(name) }
        if refusedUndos.contains(name) {
            throw .server(status: 409, message: "restore is unavailable", hint: "Keep the installed copy")
        }
        return try await wrapped.undoPromotion(name, kind: kind, restore: restore)
    }

    public func extensionUpdates() async throws(ControlAPIError) -> ExtensionUpdatesResponse {
        if hideStoredUpdates { return ExtensionUpdatesResponse() }
        var response = try await wrapped.extensionUpdates()
        response.entries += extraUpdates
        return response
    }

    // MARK: - Straight passthrough

    public func servers() async throws(ControlAPIError) -> ServersResponse {
        try await wrapped.servers()
    }

    public func server(named name: String) async throws(ControlAPIError) -> MCPServer {
        try await wrapped.server(named: name)
    }

    public func usage(
        limit: Int?,
        server: String?,
        cwd: String?
    ) async throws(ControlAPIError) -> UsageResponse {
        try await wrapped.usage(limit: limit, server: server, cwd: cwd)
    }

    public func usageSummary() async throws(ControlAPIError) -> UsageSummary {
        try await wrapped.usageSummary()
    }

    public func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
        try await wrapped.heldChanges(for: name)
    }

    public func skills() async throws(ControlAPIError) -> SkillsResponse {
        try await wrapped.skills()
    }

    public func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
        try await wrapped.marketplaces()
    }

    public func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
        try await wrapped.reindex(name)
    }

    public func patch(
        server name: String,
        _ patch: ServerPatch
    ) async throws(ControlAPIError) -> MCPServer {
        try await wrapped.patch(server: name, patch)
    }

    public func approvePendingChange(
        server name: String,
        expectedDigest: String
    ) async throws(ControlAPIError) -> ApprovalResult {
        try await wrapped.approvePendingChange(server: name, expectedDigest: expectedDigest)
    }

    public func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
        try await wrapped.beginAuthorization(for: name)
    }

    public func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
        try await wrapped.signOut(name)
    }

    public func resetUsage() async throws(ControlAPIError) -> UsageReset {
        try await wrapped.resetUsage()
    }
}
