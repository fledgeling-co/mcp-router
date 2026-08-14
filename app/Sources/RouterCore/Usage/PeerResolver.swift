import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Who was on the other end of a loopback connection.
///
/// Every field is optional and an empty identity is a normal answer, never an error: the reference
/// records an unattributed call rather than dropping one, and that judgement is kept.
public struct ClientIdentity: Sendable, Hashable {
    public var pid: Int32?
    public var cwd: String?
    public var client: String?

    public init(pid: Int32? = nil, cwd: String? = nil, client: String? = nil) {
        self.pid = pid
        self.cwd = cwd
        self.client = client
    }

    /// The answer for "nobody could be named". Distinct from a *failure* to look, which never
    /// reaches a caller — see ``LibProcPeerResolver``.
    public static let unknown = ClientIdentity()

    public var isUnknown: Bool { pid == nil && cwd == nil && client == nil }
}

/// Resolves the process holding one end of a TCP connection.
///
/// Behind a protocol for one reason that matters: the clauses about this behaviour are about what
/// happens when a lookup *cannot* answer. Those are states the real machine will not enter on
/// request, and a test that cannot enter them only ever proves the happy path.
public protocol PeerResolver: Sendable {
    /// The identity of the process holding `port` as its **local** port, excluding this process.
    /// Returns ``ClientIdentity/unknown`` when nothing can be named. Never throws: a lookup failure
    /// and "no such peer" are the same answer to a caller, and an unattributed record is worth far
    /// more than a dropped one.
    func identity(peerPort: UInt16) -> ClientIdentity
}

/// The real resolver: `libproc`, in this process, synchronously — see ``LibProcProcessProbe`` for
/// why that replaces the reference's two `lsof` executions, and what it was measured at.
///
/// ## What "never a partial identity" does and does not mean (B69)
///
/// B69 requires every *peer-identification* failure to yield an empty identity. All four paths it
/// enumerates — no such pid, a pid exiting mid-scan, a non-TCP socket, unlistable descriptors —
/// happen inside ``pidHolding(localPort:)`` and return ``ClientIdentity/unknown``.
///
/// One further path is **not** a peer-identification failure and is deliberately partial: a pid
/// that is named but whose working directory cannot be read. That is the reference's own
/// behaviour — `{ pid, client, cwd: cwd || undefined }` — and B71 requires this resolver to return
/// what the reference returns for the same connection. Making it empty here would satisfy a
/// literal reading of B69 by breaking B71, so B69 is scoped to its own enumeration and this case is
/// enumerated as its exception, exactly as B12 is scoped away from its two 422 bodies.
///
/// The path that *was* wrong, and is fixed here: a pid found whose **name** cannot be read used to
/// yield `{pid}` with no client. The reference cannot produce that state — it reads the pid and the
/// command from a single `lsof -Fpc` record, so a pid always arrives with a command, and a process
/// that has exited is simply absent from the scan. A named-less pid therefore means the process
/// went away, and the honest answer — the one the reference gives — is that nobody was named.
public struct LibProcPeerResolver: PeerResolver {
    /// The pid to exclude — this router's own, since `-i :port` style matching names both ends.
    private let selfPid: Int32
    private let probe: any ProcessProbe
    private let cache: AttributionCache

    public init(
        selfPid: Int32 = getpid(),
        probe: any ProcessProbe = LibProcProcessProbe(),
        cache: AttributionCache = AttributionCache()
    ) {
        self.selfPid = selfPid
        self.probe = probe
        self.cache = cache
    }

    public func identity(peerPort: UInt16) -> ClientIdentity {
        guard let pid = pidHolding(localPort: peerPort) else { return .unknown }

        // Consulted after the pid is known and before the working directory is read, which is the
        // reference's order: a cache hit skips the second lookup entirely.
        if let known = cache.identity(for: pid) { return known }

        // A pid with no readable name is a process that has gone. See the type comment.
        guard let client = probe.processName(of: pid) else { return .unknown }

        let identity = ClientIdentity(
            pid: pid,
            cwd: probe.workingDirectory(of: pid),
            client: client
        )
        cache.store(identity, for: pid)
        return identity
    }

    /// The process holding `localPort` on an established TCP socket.
    ///
    /// Every guard here returns "keep looking" rather than failing the scan: a process that exits
    /// between being listed and being inspected is the common case on a busy machine, and treating
    /// it as an error would make attribution flakier than no attribution at all.
    func pidHolding(localPort: UInt16) -> Int32? {
        for pid in probe.allPids() where pid != selfPid {
            guard let ports = probe.tcpLocalPorts(of: pid) else { continue }
            if ports.contains(localPort) { return pid }
        }
        return nil
    }
}
