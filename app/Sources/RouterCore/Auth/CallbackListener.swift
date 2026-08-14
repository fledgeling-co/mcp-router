import Foundation
import Network

/// The production `CallbackListening`: an HTTP/1.1 server bound to **IPv4 loopback only**, on the
/// fixed callback port.
///
/// Every termination in `CallbackResponder` is proven against a double that binds nothing; this is
/// the socket those proofs are worthless without. It carries no request semantics of its own — it
/// reads a request target off the wire, hands it to the flow's handler, and writes back the
/// `CallbackReply` it is given. Anything that decides *what* to answer lives in `CallbackResponder`,
/// where it is testable without a port.
///
/// Three properties here are load-bearing rather than incidental:
///
/// 1. **Loopback only, pinned in the parameters.** `NWListener(using:on:)` binds every interface.
///    Doing that would put the callback — and the page it renders from a provider-supplied `error`
///    parameter, which spec §6 records as unescaped — on the LAN. `requiredLocalEndpoint` is the
///    documented way to pin the bind address, so it is what this uses. IPv4 only, matching the
///    reference's `listen(port, '127.0.0.1')`: the redirect URI we register is literally
///    `http://127.0.0.1:<port>/callback`, so no browser resolves this through `::1`.
/// 2. **A bind failure throws.** B84's first pre-flow failure is `listen EADDRINUSE`, and the flow
///    depends on it surfacing rather than being retried in the background. `NWListener` reports an
///    in-use port as `.failed(POSIXErrorCode 48)` — measured, not assumed — but `.waiting` is
///    treated as a failure too, because a fixed loopback port has no legitimate transient wait and
///    a listener left waiting would hang `start` forever.
/// 3. **`stop()` does not touch an in-flight connection.** The reference's `cleanup` calls
///    `callback.close()`, which stops accepting and lets an open response finish. That is not a
///    detail: the flow settles *inside* the handler, so by the time a reply comes back the listener
///    has already been stopped by that very settle. Cancelling connections there would mean the
///    browser never receives the success page it just earned.
public actor LoopbackCallbackListener: CallbackListening {
    /// How long a connection may hold the socket open without completing a request head.
    ///
    /// Node's `headersTimeout` defaults to 60 s. A client that connects and says nothing would
    /// otherwise pin a connection for the life of the process, because nothing else closes it.
    static let headDeadlineNanoseconds: UInt64 = 60 * 1_000_000_000

    /// The most a request head may run to before the connection is dropped. Node's default
    /// `maxHeaderSize`. Past this the request is not answered at all — a head that never terminates
    /// is not a request, and the reference's 431 belongs to a framing layer this port does not have.
    static let maximumHeadBytes = 16384

    /// How long `stop()` waits for the socket to actually come back before giving up on it.
    ///
    /// A listener that never reports `.cancelled` must not hang cleanup — cleanup is on the path of
    /// every termination, so hanging here would hang the flow rather than end it.
    static let stopDeadlineNanoseconds: UInt64 = 2 * 1_000_000_000

    private struct Pending {
        let connection: NWConnection
        var head: Data
        var deadline: Task<Void, Never>?
    }

    private let queue = DispatchQueue(label: "app.fledgeling.mcp-router.auth-callback")
    private var listener: NWListener?
    private var handler: (@Sendable (String) async -> CallbackReply)?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var pending: [ObjectIdentifier: Pending] = [:]
    private var boundPortValue: Int?

    public init() {}

    /// The port actually bound, once `start` has returned.
    ///
    /// Equal to the requested port in production, where it is fixed. Port 0 binds an ephemeral one,
    /// which is how a test drives this without fighting whatever is on 8880.
    public var boundPort: Int? { boundPortValue }

    public func start(
        port: Int,
        handler: @escaping @Sendable (String) async -> CallbackReply
    ) async throws {
        guard listener == nil else {
            throw AuthFailure("the callback listener is already bound")
        }
        guard let parameters = Self.loopbackParameters(port: port) else {
            throw AuthFailure("the callback port is not a bindable port")
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Self.listenFailure(port: port, error: error)
        }
        self.listener = listener
        self.handler = handler
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.listenerStateChanged(state, port: port) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                startContinuation = continuation
                listener.start(queue: queue)
            }
        } catch {
            // Nothing stays half-bound: a listener that reported `.failed` or `.waiting` is still an
            // object holding an intent to bind, and leaving it would retry underneath a flow that
            // has already been told the bind failed.
            listener.cancel()
            self.listener = nil
            self.handler = nil
            throw error
        }
        boundPortValue = listener.port.map { Int($0.rawValue) }
    }

    /// `callback.close()` — stop accepting, and leave every open response alone.
    ///
    /// **Waits for the socket to actually come back.** `NWListener.cancel()` is asynchronous: it
    /// returns long before the listening socket is released. Returning there looks correct in
    /// isolation and breaks the one case that matters — supersession rebinds the *fixed* port
    /// immediately after cleanup, so a `stop()` that only asks for cancellation makes the second
    /// authorization fail with `EADDRINUSE` and leaves the user with a browser tab that can never
    /// land. Measured, not theorised: an immediate rebind after an unwaited cancel fails.
    ///
    /// Idempotent, because every termination path runs cleanup and two of them can race.
    public func stop() async {
        guard let listener else { return }
        self.listener = nil
        handler = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stopContinuation = continuation
            listener.cancel()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.stopDeadlineNanoseconds)
                await self?.resumeStop()
            }
        }
    }

    // MARK: - Binding

    /// The bind parameters, separated so the loopback pin is assertable without opening a socket.
    static func loopbackParameters(port: Int) -> NWParameters? {
        guard let raw = UInt16(exactly: port), let endpointPort = NWEndpoint.Port(rawValue: raw) else {
            return nil
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: endpointPort
        )
        // Explicit rather than inherited: with reuse allowed, a second router would bind the same
        // port and each would receive half the callbacks. B84 wants the second one to fail.
        parameters.allowLocalEndpointReuse = false
        return parameters
    }

    private func listenerStateChanged(_ state: NWListener.State, port: Int) {
        switch state {
        case .ready:
            resumeStart(with: nil)
        case let .failed(error):
            resumeStart(with: Self.listenFailure(port: port, error: error))
        case let .waiting(error):
            resumeStart(with: Self.listenFailure(port: port, error: error))
        case .cancelled:
            resumeStart(with: AuthFailure("the callback listener was cancelled before it bound"))
            resumeStop()
        default:
            break
        }
    }

    private func resumeStop() {
        guard let continuation = stopContinuation else { return }
        stopContinuation = nil
        continuation.resume()
    }

    private func resumeStart(with failure: Error?) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        if let failure {
            continuation.resume(throwing: failure)
        } else {
            continuation.resume()
        }
    }

    /// The reference's message shape — `listen EADDRINUSE: address already in use 127.0.0.1:8880` —
    /// because this string is what B77's 502 body carries to the app, and an app showing
    /// `nw_error 48` teaches the user nothing about the port already being taken.
    static func listenFailure(port: Int, error: Error) -> AuthFailure {
        let (code, detail) = describe(error)
        return AuthFailure("listen \(code): \(detail) 127.0.0.1:\(port)")
    }

    private static func describe(_ error: Error) -> (code: String, detail: String) {
        guard case let NWError.posix(posix) = error else {
            return ("EFAILED", String(describing: error))
        }
        switch posix {
        case .EADDRINUSE: return ("EADDRINUSE", "address already in use")
        case .EACCES: return ("EACCES", "permission denied")
        case .EADDRNOTAVAIL: return ("EADDRNOTAVAIL", "address not available")
        default: return ("EPOSIX\(posix.rawValue)", String(describing: posix))
        }
    }

    // MARK: - One connection

    private func accept(_ connection: NWConnection) {
        // A connection arriving after `stop()` has nothing to answer it. Refuse rather than hold it.
        guard listener != nil else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        let deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.headDeadlineNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.close(id)
        }
        pending[id] = Pending(connection: connection, head: Data(), deadline: deadline)
        connection.start(queue: queue)
        receive(id: id)
    }

    private func receive(id: ObjectIdentifier) {
        guard let connection = pending[id]?.connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, isComplete, error in
            Task {
                await self?.received(id: id, data: data, isComplete: isComplete, failed: error != nil)
            }
        }
    }

    private func received(id: ObjectIdentifier, data: Data?, isComplete: Bool, failed: Bool) async {
        guard var entry = pending[id] else { return }
        if let data { entry.head.append(data) }
        pending[id] = entry

        if let target = Self.requestTarget(in: entry.head) {
            await answer(id: id, target: target)
            return
        }
        if failed || isComplete || entry.head.count > Self.maximumHeadBytes {
            close(id)
            return
        }
        receive(id: id)
    }

    private func answer(id: ObjectIdentifier, target: String) async {
        guard let entry = pending[id], let handler else {
            close(id)
            return
        }
        entry.deadline?.cancel()
        // The request target is never logged. On the success path it carries the authorization
        // code, and B66's guarantee is that no credential reaches a log line.
        let reply = await handler(target)
        // Deliberately unconditional on the listener still being bound — see the type's note 3.
        pending[id] = nil
        let connection = entry.connection
        connection.send(
            content: Data(Self.wire(for: reply).utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private func close(_ id: ObjectIdentifier) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.deadline?.cancel()
        entry.connection.cancel()
    }

    // MARK: - The wire

    /// The request target — `req.url` — or nil while the head is still arriving.
    ///
    /// A target can be split across TCP segments, so this answers only once the head is terminated.
    /// Both CRLF and bare-LF terminators are accepted, as Node's parser does.
    static func requestTarget(in head: Data) -> String? {
        let bytes = [UInt8](head)
        guard headIsTerminated(bytes) else { return nil }
        guard let newline = bytes.firstIndex(of: 0x0A) else { return nil }
        var line = Array(bytes[bytes.startIndex ..< newline])
        if line.last == 0x0D { line.removeLast() }
        let fields = line.split(separator: 0x20, omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }
        return String(decoding: fields[1], as: UTF8.self)
    }

    private static func headIsTerminated(_ bytes: [UInt8]) -> Bool {
        if bytes.count >= 4 {
            for index in 0 ... (bytes.count - 4) where Array(bytes[index ..< index + 4]) == [0x0D, 0x0A, 0x0D, 0x0A] {
                return true
            }
        }
        guard bytes.count >= 2 else { return false }
        for index in 0 ... (bytes.count - 2) where bytes[index] == 0x0A && bytes[index + 1] == 0x0A {
            return true
        }
        return false
    }

    /// The bytes one `CallbackReply` becomes.
    ///
    /// A pure function, so the response head is assertable without a socket.
    ///
    /// **Declared framing divergence.** The reference sets `content-type` and nothing else, leaving
    /// Node to frame the page with `Transfer-Encoding: chunked` and keep the connection alive; this
    /// sends `content-length` and `connection: close` instead. Both are valid HTTP/1.1 and a browser
    /// renders them identically. The application-visible contract — status, `content-type`, body —
    /// is byte-identical, which is what every clause from B65 through B99 is written against. The
    /// close is the honest framing here: this listener is torn down the moment the flow settles, so
    /// a promise to keep the connection alive would be one we break a millisecond later. The 404
    /// keeps its zero-length body and no `content-type`, per B82.
    static func wire(for reply: CallbackReply) -> String {
        var head = "HTTP/1.1 \(reply.status) \(reason(for: reply.status))\r\n"
        if let contentType = reply.contentType {
            head += "content-type: \(contentType)\r\n"
        }
        head += "content-length: \(reply.body.utf8.count)\r\n"
        head += "connection: close\r\n\r\n"
        return head + reply.body
    }

    /// `http.STATUS_CODES[code] ?? 'unknown'`, for the four statuses this server can produce.
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "unknown"
        }
    }
}
