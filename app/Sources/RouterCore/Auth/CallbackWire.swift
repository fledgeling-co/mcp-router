import Foundation

/// The listener's wire format, and the request-head parsing that feeds it.
///
/// A separate file because these are **pure functions over bytes** and the socket machinery is not:
/// everything here is assertable without binding a port, which is what lets the response bytes and
/// every malformed-head case be pinned cheaply. Kept as an extension so the call sites read as one
/// type.
extension LoopbackCallbackListener {
    /// What one read of the head amounts to.
    enum HeadRead: Equatable {
        /// A request line was parsed; this is `req.url`.
        case target(String)
        /// The head is not terminated yet — more bytes may still arrive.
        case incomplete
        /// The head **is** terminated and carries no usable request line. More bytes will not help.
        case unparseable
    }

    /// The request target — `req.url` — from however much of the head has arrived.
    ///
    /// A target can be split across TCP segments, so this answers only once the head is terminated.
    /// Both CRLF and bare-LF terminators are accepted, as Node's parser does, and leading empty
    /// lines are skipped: RFC 9112 §2.2 says a server SHOULD ignore them, Node does, and a request
    /// carrying one is a *real callback* that would otherwise be lost.
    static func readTarget(in head: Data) -> HeadRead {
        let bytes = [UInt8](head)
        guard headIsTerminated(bytes) else { return .incomplete }
        var cursor = bytes.startIndex
        while cursor < bytes.endIndex {
            guard let newline = bytes[cursor...].firstIndex(of: 0x0A) else { return .unparseable }
            var line = Array(bytes[cursor ..< newline])
            if line.last == 0x0D { line.removeLast() }
            cursor = bytes.index(after: newline)
            if line.isEmpty { continue } // a leading empty line, per RFC 9112 §2.2
            let fields = line.split(separator: 0x20, omittingEmptySubsequences: true)
            guard fields.count >= 2 else { return .unparseable }
            // A request target is not guaranteed to be valid UTF-8, and a malformed one must still
            // be answered — with the 404 it earns — rather than vanish. `String(decoding:)`
            // substitutes the bad bytes where the failable initializer would drop the request.
            // swiftlint:disable:next optional_data_string_conversion
            return .target(String(decoding: fields[1], as: UTF8.self))
        }
        return .unparseable
    }

    /// The origin-form target, for the tests and callers that only care about the happy shape.
    static func requestTarget(in head: Data) -> String? {
        guard case let .target(target) = readTarget(in: head) else { return nil }
        return target
    }

    private static func headIsTerminated(_ bytes: [UInt8]) -> Bool {
        if bytes.count >= 4 {
            for index in 0 ... (bytes.count - 4) where Array(bytes[index ..< index + 4]) == [
                0x0D,
                0x0A,
                0x0D,
                0x0A
            ] {
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
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "unknown"
        }
    }
}
