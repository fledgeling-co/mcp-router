import Foundation

/// One HTTP/1.1 request, as the listener read it off the wire.
///
/// Headers are an **ordered array of pairs**, not a dictionary. Two reasons, both load-bearing:
/// a repeated header is a real thing a client can send and a dictionary silently keeps one of them,
/// and the control API's own request type is built from these in order. Lookup is
/// case-insensitive through ``first(_:)`` because HTTP field names are.
public struct HTTPWireRequest: Sendable {
    public var method: String
    /// The request target exactly as received — percent-encoding intact, query attached.
    /// `ControlHandler` decodes its own path, and a target normalised here would move the wire.
    public var target: String
    public var httpVersion: String
    public var headers: [(name: String, value: String)]
    public var body: Data
    public var connection: ConnectionDescriptor

    public init(
        method: String,
        target: String,
        httpVersion: String = "HTTP/1.1",
        headers: [(name: String, value: String)] = [],
        body: Data = Data(),
        connection: ConnectionDescriptor = ConnectionDescriptor(peer: "", acceptedAtMilliseconds: 0)
    ) {
        self.method = method
        self.target = target
        self.httpVersion = httpVersion
        self.headers = headers
        self.body = body
        self.connection = connection
    }

    /// The first value for this field name, matched case-insensitively.
    public func first(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.name.lowercased() == wanted }?.value
    }

    /// The path with the query removed, and the raw query string without its `?`.
    ///
    /// Split on the **first** `?` only: a query value may legitimately contain another one, and
    /// splitting on all of them would truncate it.
    public var pathAndQuery: (path: String, query: String?) {
        guard let mark = target.firstIndex(of: "?") else { return (target, nil) }
        return (
            String(target[target.startIndex ..< mark]),
            String(target[target.index(after: mark)...])
        )
    }
}

/// What a handler wants written back.
///
/// The body is an enum rather than `Data?` because `/usage/stream` and the MCP endpoint both need a
/// response whose length is unknown when the head is written. Modelling only `Data` would force the
/// listener to buffer a stream that ends when the client leaves.
public struct HTTPWireResponse: Sendable {
    public enum Body: Sendable {
        case bytes(Data)
        /// Written as HTTP chunked transfer-encoding, one chunk per element, until the stream ends.
        case chunks(AsyncStream<Data>)
    }

    public var status: Int
    /// Explicit rather than derived from the status: the reference's reason phrases come from
    /// Node's own table and a lookup that guessed would put a different word on the status line.
    public var reason: String
    public var headers: [(name: String, value: String)]
    public var body: Body
    /// Whether the connection may be reused. False makes the listener close after this response,
    /// which is what a streaming body has to do.
    public var keepAlive: Bool

    public init(
        status: Int,
        reason: String? = nil,
        headers: [(name: String, value: String)] = [],
        body: Body = .bytes(Data()),
        keepAlive: Bool = true
    ) {
        self.status = status
        self.reason = reason ?? HTTPWire.reasonPhrase(for: status)
        self.headers = headers
        self.body = body
        self.keepAlive = keepAlive
    }

    public static func json(_ status: Int, _ bytes: Data, reason: String? = nil) -> HTTPWireResponse {
        HTTPWireResponse(
            status: status,
            reason: reason,
            headers: [
                (name: "content-type", value: "application/json"),
                (name: "content-length", value: String(bytes.count))
            ],
            body: .bytes(bytes)
        )
    }
}

/// Parsing and serialising HTTP/1.1, with no socket anywhere near it.
///
/// Separated from the listener deliberately: every framing rule below is a decision that can be
/// wrong, and a rule that can only be exercised by opening a port is a rule that gets tested once.
public enum HTTPWire {
    /// How much of a request head is tolerated before the connection is dropped. Node's default
    /// `maxHeaderSize`, matching R5's listener.
    public static let maximumHeadBytes = 16384

    /// The largest body the router will buffer. `src/router.ts:readBody` uses 32 MiB and destroys
    /// the request past it; anything smaller here would refuse a request the reference accepts.
    public static let maximumBodyBytes = 32 * 1024 * 1024

    public enum ParseFailure: Error, Equatable, Sendable {
        /// The head is not finished yet. Read more.
        case incomplete
        /// The head is finished and is not a request. Nothing will make it one.
        case malformed(String)
        case headTooLarge
        case bodyTooLarge
    }

    public struct ParsedHead: Sendable {
        public var method: String
        public var target: String
        public var httpVersion: String
        public var headers: [(name: String, value: String)]
        /// Where the body starts in the buffer the head was parsed from.
        public var bodyOffset: Int
    }

    /// Parse a request head, or say why it cannot be parsed yet.
    ///
    /// A head is terminated by CRLFCRLF. A bare LFLF terminator is **also** accepted, because
    /// `curl --http1.0`, hand-written probes and R5's own hostile-input tests send it, and a server
    /// that waits for a CR that is never coming looks from the outside exactly like a hung router.
    public static func parseHead(_ buffer: Data) throws -> ParsedHead {
        guard let terminator = headTerminator(in: buffer) else {
            if buffer.count > maximumHeadBytes { throw ParseFailure.headTooLarge }
            throw ParseFailure.incomplete
        }
        if terminator.end > maximumHeadBytes { throw ParseFailure.headTooLarge }

        let headBytes = buffer[buffer.startIndex ..< buffer.index(buffer.startIndex, offsetBy: terminator.start)]
        guard let head = String(bytes: headBytes, encoding: .utf8) else {
            throw ParseFailure.malformed("the request head is not UTF-8")
        }

        var lines = head.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        guard !lines.isEmpty else { throw ParseFailure.malformed("empty request head") }

        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ParseFailure.malformed("not a request line: \(requestLine)")
        }

        var headers: [(name: String, value: String)] = []
        for line in lines where !line.isEmpty {
            // A continuation line (obs-fold) is refused rather than folded: it is deprecated, no
            // client this router serves emits one, and folding it would let a header value carry a
            // newline into the control API's own parsing.
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                throw ParseFailure.malformed("obsolete line folding is not accepted")
            }
            guard let colon = line.firstIndex(of: ":") else {
                throw ParseFailure.malformed("header line has no colon: \(line)")
            }
            let name = String(line[line.startIndex ..< colon])
            // Whitespace between the field name and the colon is a request-smuggling shape and is
            // rejected by RFC 7230 §3.2.4 in exactly these words.
            guard !name.hasSuffix(" "), !name.hasSuffix("\t"), !name.isEmpty else {
                throw ParseFailure.malformed("whitespace before the colon in \"\(name)\"")
            }
            headers.append((
                name: name,
                value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            ))
        }

        return ParsedHead(
            method: String(parts[0]),
            target: String(parts[1]),
            httpVersion: parts.count > 2 ? String(parts[2]) : "HTTP/1.0",
            headers: headers,
            bodyOffset: terminator.end
        )
    }

    /// How many body bytes this head declares.
    ///
    /// `Transfer-Encoding` is refused rather than implemented. No client of this router sends a
    /// chunked request — the MCP clients, the control API clients and the installer all send
    /// `content-length` — and a server that accepts both without agreeing on precedence is the
    /// classic request-smuggling shape. Refusing is the safe half.
    public static func bodyLength(of head: ParsedHead) throws -> Int {
        let lookup = { (name: String) -> String? in
            head.headers.first { $0.name.lowercased() == name }?.value
        }
        if let encoding = lookup("transfer-encoding"), !encoding.isEmpty {
            throw ParseFailure.malformed("transfer-encoding is not accepted on a request")
        }
        guard let raw = lookup("content-length"), !raw.isEmpty else { return 0 }
        guard let length = Int(raw), length >= 0 else {
            throw ParseFailure.malformed("content-length is not a number: \(raw)")
        }
        guard length <= maximumBodyBytes else { throw ParseFailure.bodyTooLarge }
        return length
    }

    /// The head bytes of a response: status line, headers, blank line.
    ///
    /// `Date`, `Connection` and `Keep-Alive` are appended only when the handler did not set them,
    /// which is what lets the MCP endpoint send its own `connection: keep-alive` in the position
    /// the reference sends it while `/health` still gets Node's automatic trio in Node's order.
    public static func head(for response: HTTPWireResponse, now: Date) -> Data {
        var text = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        var present = Set(response.headers.map { $0.name.lowercased() })

        for header in response.headers {
            text += "\(header.name): \(header.value)\r\n"
        }
        // The order below is Node's, measured on 2026-08-14 against two different responses and
        // not inferred: `/health` emits `content-type, content-length, Date, Connection,
        // Keep-Alive`, and `DELETE /mcp` emits `Date, Connection, Keep-Alive, Transfer-Encoding`.
        // Both are explained by one rule — the handler's own headers, then Date, then the
        // connection pair, then the transfer encoding — and the SSE response confirms it, because
        // there `connection` is one of the handler's own headers and the automatic pair is
        // suppressed, leaving `…, Date, Transfer-Encoding`.
        if !present.contains("date") {
            text += "Date: \(imfFixdate(now))\r\n"
        }
        if !present.contains("connection") {
            text += response.keepAlive ? "Connection: keep-alive\r\n" : "Connection: close\r\n"
            if response.keepAlive, !present.contains("keep-alive") {
                text += "Keep-Alive: timeout=5\r\n"
            }
        }
        if case .chunks = response.body, !present.contains("transfer-encoding") {
            text += "Transfer-Encoding: chunked\r\n"
            present.insert("transfer-encoding")
        }
        text += "\r\n"
        return Data(text.utf8)
    }

    /// One chunk in HTTP chunked transfer-encoding. An empty chunk is the terminator, so a caller
    /// must never pass empty data for a real write.
    public static func chunk(_ payload: Data) -> Data {
        var out = Data(String(format: "%x\r\n", payload.count).utf8)
        out.append(payload)
        out.append(Data("\r\n".utf8))
        return out
    }

    public static let lastChunk = Data("0\r\n\r\n".utf8)

    /// RFC 7231 IMF-fixdate, which is what Node's `Date` header carries. Fixed to GMT and the C
    /// locale so a machine set to another region does not emit a localised month name.
    public static func imfFixdate(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        guard let gmt = TimeZone(identifier: "GMT") else { return "" }
        calendar.timeZone = gmt
        let parts = calendar.dateComponents(
            [.weekday, .day, .month, .year, .hour, .minute, .second], from: date
        )
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        ]
        guard
            let weekday = parts.weekday, weekday >= 1, weekday <= 7,
            let month = parts.month, month >= 1, month <= 12,
            let day = parts.day, let year = parts.year,
            let hour = parts.hour, let minute = parts.minute, let second = parts.second
        else { return "" }
        return String(
            format: "%@, %02d %@ %04d %02d:%02d:%02d GMT",
            days[weekday - 1], day, months[month - 1], year, hour, minute, second
        )
    }

    /// Node's reason phrases, for the statuses this router actually sends.
    public static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 409: "Conflict"
        case 415: "Unsupported Media Type"
        case 422: "Unprocessable Entity"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        default: "Unknown"
        }
    }

    /// Where the head ends: the offset of the terminator and the offset just past it.
    private static func headTerminator(in buffer: Data) -> (start: Int, end: Int)? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }
        var index = 0
        while index < bytes.count {
            if index + 3 < bytes.count,
               bytes[index] == 13, bytes[index + 1] == 10,
               bytes[index + 2] == 13, bytes[index + 3] == 10 {
                return (index, index + 4)
            }
            if index + 1 < bytes.count, bytes[index] == 10, bytes[index + 1] == 10 {
                return (index, index + 2)
            }
            index += 1
        }
        return nil
    }
}
