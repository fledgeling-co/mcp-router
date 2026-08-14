import Foundation
import MCP

// The boundaries R3 plugs into, frozen by R2 so the two runners cannot collide.
//
// The rule that shapes every protocol here: **a seam with nothing attached must behave correctly
// on its own.** An absent control handler means control paths 404; it does not mean the router
// traps. Each protocol therefore has a no-op default whose behaviour is the correct inert one,
// and the pool and listener are written against the protocol rather than against the presence of
// an implementation.

// MARK: - Control

/// One request arriving at the control API.
///
/// A value rather than four parameters because the shape kept being wrong: the first version passed
/// `path` alone, which cannot express `/usage?since=…` — and folding the query into `path` would
/// then break `claims(path:)`, since a handler matching `/usage` would stop recognising its own
/// endpoint the moment a caller added a parameter.
public struct ControlRequest: Sendable, Hashable {
    public var method: String
    /// The path with **no** query string, e.g. `/usage`. This is what `claims(path:)` is asked about.
    public var path: String
    /// The raw query string as received, without the leading `?`. Left unparsed on purpose: percent
    /// decoding and repeated keys are decisions the handler should make, not ones this seam should
    /// make for it.
    public var rawQuery: String?
    public var headers: [String: String]
    /// The body, buffered exactly once by the listener. Raw bytes: nothing on this side of the seam
    /// decodes them, for the reason T3 records — routing happens before any semantic decode, so a
    /// control-path decode failure can never consume, reject or alter a request bound for MCP.
    public var body: Data?
    /// The connection it arrived on, for handlers that attribute a request to a caller.
    public var connection: ConnectionDescriptor?

    public init(
        method: String,
        path: String,
        rawQuery: String? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        connection: ConnectionDescriptor? = nil
    ) {
        self.method = method
        self.path = path
        self.rawQuery = rawQuery
        self.headers = headers
        self.body = body
        self.connection = connection
    }
}

/// What a control response carries.
///
/// The streaming case exists because `/usage/stream` does: a response whose length is unknown when
/// the headers are written, and which ends when the client goes away rather than when the handler
/// runs out of things to say. Modelling only `Data` would have forced R3 to either buffer an endless
/// stream or bypass this seam entirely.
public enum ControlBody: Sendable {
    case data(Data?)
    /// Chunks written as they are produced. Finishing the stream ends the response.
    ///
    /// Disconnection is signalled the other way: the listener stops consuming, which fires the
    /// stream's own `onTermination`. A producer that wants to know its reader has gone registers
    /// there — no separate cancellation channel, and none that can be forgotten.
    case stream(AsyncStream<Data>)
}

/// Where R3's control API attaches.
public protocol ControlHandling: Sendable {
    /// Whether this path belongs to the control API. Consulted *before* the MCP endpoint, and given
    /// the path with its query already removed.
    func claims(path: String) -> Bool

    /// Answer a claimed request. Returning `nil` means "claimed but unhandled", which the listener
    /// renders as 404 rather than falling through to the MCP endpoint — a fall-through would let a
    /// mistyped control path reach the relay.
    func respond(to request: ControlRequest) async -> ControlResponse?
}

/// A control-API response, kept deliberately free of any HTTP library type so this seam does not
/// drag NIO — or any other listener choice — across the boundary.
public struct ControlResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: ControlBody

    public init(status: Int, headers: [String: String] = [:], body: ControlBody) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public init(status: Int, headers: [String: String] = [:], body: Data? = nil) {
        self.init(status: status, headers: headers, body: .data(body))
    }
}

/// The inert control handler: claims nothing, answers nothing.
public struct NoControlHandling: ControlHandling {
    public init() {}
    public func claims(path: String) -> Bool {
        false
    }

    public func respond(to request: ControlRequest) async -> ControlResponse? {
        nil
    }
}

// MARK: - Caller identity

/// A connection, described by value.
///
/// Deliberately **not** a channel, socket or file handle: the listener is free to be NIO today and
/// something else tomorrow, and a seam that exposed its internals would make that a breaking change
/// for R3. It carries only what identification needs.
public struct ConnectionDescriptor: Sendable, Hashable {
    /// Peer address as the listener sees it, e.g. `127.0.0.1:54321`.
    public let peer: String
    /// When the connection was accepted, in milliseconds since the epoch.
    public let acceptedAtMilliseconds: Double

    public init(peer: String, acceptedAtMilliseconds: Double) {
        self.peer = peer
        self.acceptedAtMilliseconds = acceptedAtMilliseconds
    }
}

/// Who was on the other end of a connection.
public struct CallerIdentity: Sendable, Hashable {
    public var pid: Int?
    public var cwd: String?
    public var client: String?

    public init(pid: Int? = nil, cwd: String? = nil, client: String? = nil) {
        self.pid = pid
        self.cwd = cwd
        self.client = client
    }

    /// The answer when nothing could be determined. An unattributed record is worth far more than
    /// a dropped one, so this is a value rather than an error.
    public static let unknown = CallerIdentity()
}

/// Resolving which process holds the other end of a loopback connection.
///
/// `prefetch` is called at **accept time**, not when a call finishes, and that timing is the whole
/// point: the lookup asks the OS who owns the socket, so it can only answer while that process is
/// alive. Deferring it to the end of a tool call loses every short-lived client.
public protocol CallerIdentifying: Sendable {
    func prefetch(_ connection: ConnectionDescriptor)
    func identity(for connection: ConnectionDescriptor) async -> CallerIdentity
}

/// The inert identifier: everything is unknown, and nothing is looked up.
public struct NoCallerIdentifying: CallerIdentifying {
    public init() {}
    public func prefetch(_ connection: ConnectionDescriptor) {}
    public func identity(for connection: ConnectionDescriptor) async -> CallerIdentity {
        .unknown
    }
}

// MARK: - Call observation

/// One tool call, as it happened — every field the TypeScript reference records, so R3's usage
/// store can be a port rather than a redesign.
public struct CallEvent: Sendable, Hashable {
    public var timestamp: String
    public var server: String
    public var tool: String
    public var ok: Bool
    /// Wall-clock milliseconds, including any cold start.
    public var milliseconds: Int
    /// True when this call is what started the upstream — the cost the router defers.
    public var cold: Bool
    public var pid: Int?
    public var cwd: String?
    public var project: String?
    public var client: String?
    public var error: String?

    public init(
        timestamp: String,
        server: String,
        tool: String,
        ok: Bool,
        milliseconds: Int,
        cold: Bool,
        pid: Int? = nil,
        cwd: String? = nil,
        project: String? = nil,
        client: String? = nil,
        error: String? = nil
    ) {
        self.timestamp = timestamp
        self.server = server
        self.tool = tool
        self.ok = ok
        self.milliseconds = milliseconds
        self.cold = cold
        self.pid = pid
        self.cwd = cwd
        self.project = project
        self.client = client
        self.error = error
    }
}

/// Where R3's usage store attaches. Invoked **after** the result is on its way, and it must swallow
/// its own errors: attribution never delays or breaks a call.
public protocol CallObserving: Sendable {
    func record(_ event: CallEvent)
    func flush() async
}

/// The inert observer: records nothing, and cannot fail.
public struct NoCallObserving: CallObserving {
    public init() {}
    public func record(_ event: CallEvent) {}
    public func flush() async {}
}

// MARK: - Upstream authorization

/// Where R3's OAuth provider attaches, for HTTP upstreams.
///
/// The authorizer is the pinned SDK's own `HTTPClientAuthorizer` rather than an opaque `Sendable`,
/// because that is exactly what `HTTPClientTransport` accepts — `(any HTTPClientAuthorizer)?`. An
/// opaque type here would have to be cast at the point of use, and the cast would fail at the first
/// HTTP upstream rather than at compile time.
public protocol UpstreamAuthorizing: Sendable {
    /// The authorizer for this upstream, or `nil` when it declares `oauth: false` — which must
    /// suppress authorization entirely rather than merely fail it.
    func authorizer(for upstreamName: String) -> (any HTTPClientAuthorizer)?

    /// Called when an upstream reports it needs a browser authorization. The router runs under
    /// launchd with no user attached, so it records the URL rather than opening it.
    func challenge(upstreamName: String, url: String)
}

/// The inert authorizer: no upstream is authorized, and no challenge is recorded.
public struct NoUpstreamAuthorizing: UpstreamAuthorizing {
    public init() {}
    public func authorizer(for upstreamName: String) -> (any HTTPClientAuthorizer)? {
        nil
    }

    public func challenge(upstreamName: String, url: String) {}
}
