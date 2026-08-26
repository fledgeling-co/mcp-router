import Foundation

/// Everything that can go wrong talking to the router.
///
/// `routerNotRunning` is a distinct case rather than one more transport failure, because the
/// design treats it as a first-class state with its own surface: the router is loopback, so
/// "unreachable" does not mean the network is down or the service is degraded — it means the
/// daemon is not running on this machine, and the honest response is to say so and offer to start
/// it. A client that folds this into a generic connection error cannot render that state, and the
/// user gets "something went wrong" for a condition with one obvious fix.
public enum ControlAPIError: Error, Equatable, Sendable {
    /// Nothing is listening on the loopback control port.
    case routerNotRunning

    /// The control token was missing, wrong, or has been rotated.
    case unauthorized

    /// The router answered, but not with something this version understands.
    case malformedResponse(detail: String)

    /// The router answered with an error status and a message.
    ///
    /// `hint` carries the router's own advice where it sends one — a refused add replies
    /// `{error, hint: "retry with ?force=1 to add it anyway"}`, and that sentence is the whole
    /// difference between a dead end and a next step. Dropping it would leave the user told what
    /// failed and not what to do, which is exactly what the copy rules forbid.
    case server(status: Int, message: String, hint: String? = nil)

    /// The request did not complete.
    case transport(detail: String)

    /// The pane title for this condition.
    ///
    /// Split into headline / advice / action because that is how the surfaces actually render it,
    /// and because `DESIGN.md` §6 asks for **one** wording per state across both devices. A single
    /// paraphrased sentence here would mean the pane says one thing and the client says another,
    /// which is exactly the two-wordings failure that rule exists to prevent.
    ///
    /// The two full-pane conditions are asserted verbatim against
    /// `design/mocks/html/f3-connection-states.html` by `ControlCopyTests`, so rewording either the
    /// mock or this file fails the build rather than drifting quietly.
    public var headline: String {
        switch self {
        case .routerNotRunning: "The router isn't running"
        case .unauthorized: "This app isn't authorised to talk to the router"
        case .malformedResponse: "The router sent a response this version doesn't understand"
        case .server: "The router couldn't complete that"
        case .transport: "Couldn't reach the router"
        }
    }

    /// What to do about it. Never blames the user, never emotes, and always says what is safe.
    public var advice: String {
        switch self {
        case .routerNotRunning:
            """
            Nothing is listening on the control port, so there is nothing to show yet. \
            Starting it takes a moment and your servers stay exactly as you left them.
            """
        case .unauthorized:
            """
            The control token was rotated or removed. Re-pair to continue — \
            your servers and their history are untouched.
            """
        case let .malformedResponse(detail):
            "The router may be newer or older than this app (\(detail))."
        case let .server(status, message, hint):
            if let hint, !hint.isEmpty {
                "The router returned \(status) — \(message). \(hint)"
            } else {
                "The router returned \(status) — \(message)."
            }
        case let .transport(detail):
            "The request did not complete (\(detail))."
        }
    }

    /// The label of the one action that fixes this, where there is one. Verb-first, per §6.
    public var actionLabel: String? {
        switch self {
        case .routerNotRunning: "Start the router"
        case .unauthorized: "Re-pair…"
        case .malformedResponse, .server, .transport: nil
        }
    }

    /// Copy that states what happened and what to do about it, next to the thing that failed.
    /// Never blames the user and never emotes.
    ///
    /// The one-line form, for a place too small for a pane. It is composed from the same two
    /// strings the pane renders rather than being written separately, so there is no second
    /// wording to keep in step.
    public var userFacingDescription: String {
        "\(headline). \(advice)"
    }
}

/// What the app is allowed to ask the router for.
///
/// Every endpoint the apps need has an operation here. That completeness is the point rather than
/// a convenience: the Mac app talks to the router **only** across this boundary, so a shape that
/// is modelled but not callable leaves a hole a later surface has to route around — and routing
/// around it means a second channel, which is the one thing this design does not allow.
///
/// Note what is still absent: there is no `update(server:command:)` or anything like it. The only
/// mutation shape for an existing server is `ServerPatch`, which cannot carry a command line.
/// `add` takes `NewServer`, a separate type, so declaring a server and editing one can never be
/// confused for each other.
public protocol ControlAPIClient: Sendable {
    /// Spelled short so the one operation that answers a different error type still fits its
    /// signature on one line.
    ///
    /// Not cosmetic: SwiftFormat wraps a longer signature and puts the brace on its own line, and
    /// SwiftLint's `opening_brace` wants it on the signature's. `.swiftlint.yml` reconciles those
    /// two only for wrapped *statement conditions*, so a declaration long enough to wrap is a pair
    /// of gates nothing can satisfy at once. An alias costs a name and satisfies both.
    typealias Payload = CapabilityDocumentPayload

    // MARK: Reading

    /// Every declared server and the router's own state.
    func servers() async throws(ControlAPIError) -> ServersResponse

    /// One server, by name.
    func server(named name: String) async throws(ControlAPIError) -> MCPServer

    /// The recent call log, with the filters the endpoint actually offers.
    ///
    /// `GET /usage` reads `limit`, `server` and `cwd` from the query string (`src/control.ts`
    /// ~line 425). A no-argument version could only ever fetch the last 200 rows unfiltered, which
    /// makes "show me this server's calls" or "show me this project's calls" impossible through
    /// the one boundary the app is allowed to use — the endpoint supports it and the client did
    /// not, which is the callable-surface gap A9 is about, in its quieter form.
    func usage(limit: Int?, server: String?, cwd: String?) async throws(ControlAPIError) -> UsageResponse

    /// Per-server totals since the counter was last reset.
    func usageSummary() async throws(ControlAPIError) -> UsageSummary

    /// The tool-surface change a server is holding for review, if any.
    func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges

    /// Search the configured registries.
    func searchRegistry(query: String, limit: Int) async throws(ControlAPIError) -> RegistrySearchResponse

    /// Every skill the router can see, across every client that has a skills mechanism.
    ///
    /// Read-only, and deliberately so for now: changing what is installed means writing files that
    /// the client applications themselves hold open, and that write wants preconditions and an undo
    /// this surface does not yet have. The board renders its write controls dimmed with that reason
    /// rather than offering an action it cannot make safe.
    ///
    /// A router older than this endpoint answers 404. Implementations map that to
    /// `malformedResponse`, not to `server(status:)` — "the router couldn't complete that" is the
    /// wrong sentence for "this router does not have the feature", and the version-skew wording is
    /// the one the board is designed around.
    func skills() async throws(ControlAPIError) -> SkillsResponse

    /// Every followed marketplace, with what it supplies.
    func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse

    /// Every harness detected on this machine, and how each one currently reaches the router.
    ///
    /// The app may not read a harness configuration file itself — `no-raw-design-values.sh`'s A36
    /// rule forbids `FileManager`, `Data(contentsOf:)`, `URL(fileURLWithPath:)` and `Bundle`
    /// anywhere under `Boards/`, because reading a file is one of the ways past this boundary. So
    /// the Harnesses board exists only if this operation does.
    func harnesses() async throws(ControlAPIError) -> HarnessesResponse

    /// Everything the Insights board draws, counted from what the router served and opened.
    func insights() async throws(ControlAPIError) -> InsightsResponse

    /// One capability's own documents, read by the router out of the package it starts it from.
    ///
    /// The one read on this protocol that answers a **different error type**, and deliberately: the
    /// panel's designed states are "nothing is published", "this server has no package", "its
    /// directory is gone" and "the document is over the transport cap", and collapsing four named
    /// situations into *the router couldn't complete that* is what `DESIGN.md` §6 forbids.
    ///
    /// Images arrive as bytes rather than references, so nothing downstream holds a path. That is
    /// M19's rule and A36's: reading a file is one of the ways past this boundary.
    func capabilityDocument(for server: String) async throws(CapabilityDocumentError) -> Payload

    // MARK: Writing

    /// Declare a new server. `force` adopts one that failed to start, which the router otherwise
    /// refuses with a hint saying so.
    func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer

    /// Remove a server. `keepHistory` leaves its usage rows in place.
    func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer

    /// Re-read a server's tool surface.
    func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult

    /// Change the settings a control API is permitted to change.
    func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer

    /// Accept a server's held tool-surface change.
    ///
    /// Deliberately its own operation rather than a field on `ServerPatch`: the router exposes it
    /// as a separate call, and folding it into the patch body would produce a request that looks
    /// like it worked and changes nothing. It returns `ApprovalResult`, which is what the router
    /// actually replies — not a server object.
    func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult

    /// Begin an OAuth flow for an HTTP upstream. The app opens the returned URL.
    func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart

    /// Discard a server's stored credentials.
    func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut

    /// Clear the usage counters.
    func resetUsage() async throws(ControlAPIError) -> UsageReset
}

public extension ControlAPIClient {
    /// A client that does not serve M22's two boards, answering as a router that does not have
    /// them — because for a surface those are the same state.
    ///
    /// Unlike every other operation on this protocol, these two exist **only on the Swift
    /// router**: the TypeScript router is still the installed default and answers both 404, which
    /// `LiveControlAPIClient` already maps to this exact error. So a conformer with no opinion
    /// about them is indistinguishable from a router that predates them, and the boards are
    /// designed around that state either way. `malformedResponse` carries the wording — *the
    /// router may be newer or older than this app* — and a default that returned an empty
    /// response instead would render "no harnesses on this Mac", which is a finding rather than
    /// an absence.
    func harnesses() async throws(ControlAPIError) -> HarnessesResponse {
        throw ControlAPIError.malformedResponse(detail: "this router has no /harnesses endpoint")
    }

    func insights() async throws(ControlAPIError) -> InsightsResponse {
        throw ControlAPIError.malformedResponse(detail: "this router has no /insights endpoint")
    }

    /// A client that cannot ask for a document answers the state that says so.
    ///
    /// `notServed` is the honest answer for a conformer with nothing behind it — the phone's client,
    /// a preview, a harness — and it stays the default here rather than being deleted along with
    /// the absence M30 closed: a surface with nothing to ask is not a router that answered.
    func capabilityDocument(for _: String) async throws(CapabilityDocumentError) -> Payload {
        throw CapabilityDocumentError.notServed
    }

    /// Defaults so a caller that wants the ordinary behaviour does not have to name the flag.
    func add(_ server: NewServer) async throws(ControlAPIError) -> AddedServer {
        try await add(server, force: false)
    }

    func remove(_ name: String) async throws(ControlAPIError) -> RemovedServer {
        try await remove(name, keepHistory: false)
    }

    func searchRegistry(query: String) async throws(ControlAPIError) -> RegistrySearchResponse {
        try await searchRegistry(query: query, limit: 30)
    }

    /// The whole recent log, which is what most callers want.
    func usage() async throws(ControlAPIError) -> UsageResponse {
        try await usage(limit: nil, server: nil, cwd: nil)
    }

    /// One server's calls.
    func usage(server: String) async throws(ControlAPIError) -> UsageResponse {
        try await usage(limit: nil, server: server, cwd: nil)
    }
}
