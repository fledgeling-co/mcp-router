import Foundation
import Network
import Testing
@testable import RouterCore

/// The listener's wire layer, exercised without opening a socket.
///
/// Every rule in `HTTPWire` is a decision that can be wrong, and a rule that can only be reached by
/// binding a port is a rule that gets tested once and then trusted. These are the ones where being
/// wrong is silent: a head terminator that is never recognised looks like a slow client, and a
/// response header emitted in the wrong order passes every functional check and fails the parity
/// gate for a reason nobody can find.
@Suite("The HTTP wire layer")
struct HTTPWireTests {
    @Test("a head is not parsed until its terminator arrives")
    func incompleteHead() throws {
        #expect(throws: HTTPWire.ParseFailure.incomplete) {
            _ = try HTTPWire.parseHead(Data("GET /health HTTP/1.1\r\nHost: x\r\n".utf8))
        }
    }

    @Test("a bare LFLF terminator is accepted, because real clients send it")
    func lfTerminator() throws {
        let head = try HTTPWire.parseHead(Data("GET /health HTTP/1.1\nHost: x\n\n".utf8))
        #expect(head.method == "GET")
        #expect(head.target == "/health")
        #expect(head.headers.first?.name == "Host")
    }

    @Test("the request target keeps its percent-encoding and its query")
    func targetIsRaw() throws {
        let head = try HTTPWire.parseHead(Data("GET /servers%2Fx?a=1&a=2 HTTP/1.1\r\n\r\n".utf8))
        #expect(head.target == "/servers%2Fx?a=1&a=2")
        let request = HTTPWireRequest(method: head.method, target: head.target)
        #expect(request.pathAndQuery.path == "/servers%2Fx")
        #expect(request.pathAndQuery.query == "a=1&a=2")
    }

    @Test("a query value containing a question mark is not truncated")
    func firstQuestionMarkOnly() {
        let request = HTTPWireRequest(method: "GET", target: "/usage?q=a?b")
        #expect(request.pathAndQuery.query == "q=a?b")
    }

    @Test("repeated headers are all kept, and lookup takes the first")
    func repeatedHeaders() throws {
        let head = try HTTPWire.parseHead(
            Data("GET / HTTP/1.1\r\nX-A: one\r\nX-A: two\r\n\r\n".utf8)
        )
        #expect(head.headers.count == 2)
        let request = HTTPWireRequest(method: "GET", target: "/", headers: head.headers)
        #expect(request.first("x-a") == "one")
    }

    @Test("whitespace before the colon is refused rather than trimmed")
    func smugglingShape() {
        #expect(throws: (any Error).self) {
            _ = try HTTPWire.parseHead(Data("GET / HTTP/1.1\r\nHost : x\r\n\r\n".utf8))
        }
    }

    @Test("obsolete line folding is refused")
    func obsoleteFolding() {
        #expect(throws: (any Error).self) {
            _ = try HTTPWire.parseHead(Data("GET / HTTP/1.1\r\nX: a\r\n b\r\n\r\n".utf8))
        }
    }

    @Test("a chunked request is refused rather than half-implemented")
    func chunkedRequestRefused() throws {
        let head = try HTTPWire.parseHead(
            Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        )
        #expect(throws: (any Error).self) { _ = try HTTPWire.bodyLength(of: head) }
    }

    @Test("content-length is read, and a non-numeric one is an error not a zero")
    func contentLength() throws {
        let good = try HTTPWire.parseHead(Data("POST / HTTP/1.1\r\nContent-Length: 7\r\n\r\n".utf8))
        #expect(try HTTPWire.bodyLength(of: good) == 7)

        let bad = try HTTPWire.parseHead(Data("POST / HTTP/1.1\r\nContent-Length: x\r\n\r\n".utf8))
        #expect(throws: (any Error).self) { _ = try HTTPWire.bodyLength(of: bad) }
    }

    /// The order below is the reference's, measured on 2026-08-14. It is asserted here as well as by
    /// the parity lane because the lane needs a live Node to run and this does not — a developer who
    /// reorders these will find out at `swift test` rather than at the gate.
    @Test("a buffered response emits handler headers, then Date, then the connection pair")
    func headOrderForBufferedResponse() throws {
        let response = HTTPWireResponse.json(200, Data("{}".utf8))
        let head = try utf8(HTTPWire.head(for: response, now: Date(timeIntervalSince1970: 0)))
        let lines = head.components(separatedBy: "\r\n")
        #expect(lines[0] == "HTTP/1.1 200 OK")
        #expect(lines[1] == "content-type: application/json")
        #expect(lines[2] == "content-length: 2")
        #expect(lines[3] == "Date: Thu, 01 Jan 1970 00:00:00 GMT")
        #expect(lines[4] == "Connection: keep-alive")
        #expect(lines[5] == "Keep-Alive: timeout=5")
    }

    @Test("a streaming response puts Transfer-Encoding last, after Date")
    func headOrderForStreamingResponse() throws {
        let response = HTTPWireResponse(
            status: 200,
            headers: MCPEndpoint.sseHeaders,
            body: .chunks(AsyncStream { $0.finish() })
        )
        let head = try utf8(HTTPWire.head(for: response, now: Date(timeIntervalSince1970: 0)))
        let lines = head.components(separatedBy: "\r\n")
        #expect(lines[1] == "cache-control: no-cache, no-transform")
        #expect(lines[2] == "connection: keep-alive")
        #expect(lines[3] == "content-type: text/event-stream")
        #expect(lines[4] == "x-accel-buffering: no")
        #expect(lines[5] == "Date: Thu, 01 Jan 1970 00:00:00 GMT")
        #expect(lines[6] == "Transfer-Encoding: chunked")
        // The handler set `connection` itself, so the automatic pair is suppressed — which is the
        // rule that explains both this order and the buffered one above with a single mechanism.
        #expect(!head.contains("Keep-Alive: timeout=5"))
    }

    @Test("the Date header is IMF-fixdate in GMT, whatever the machine's locale")
    func dateFormat() {
        #expect(HTTPWire.imfFixdate(Date(timeIntervalSince1970: 1_755_165_069))
            == "Thu, 14 Aug 2025 09:51:09 GMT")
    }

    @Test("a chunk carries its length in lowercase hex")
    func chunkFraming() throws {
        let chunk = try utf8(HTTPWire.chunk(Data(repeating: 0x61, count: 26)))
        #expect(chunk == "1a\r\n" + String(repeating: "a", count: 26) + "\r\n")
        #expect(try utf8(HTTPWire.lastChunk) == "0\r\n\r\n")
    }
}

/// `String(decoding:as:)` substitutes U+FFFD for invalid UTF-8, so a wire assertion built on it
/// still passes on bytes no peer could decode — the defect resurfaces, if at all, as a confusing
/// mismatch in the expected string rather than as a decode failure. This fails on the decode
/// itself, at the line that produced the bytes.
private func utf8(
    _ bytes: Data,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> String {
    try #require(
        String(bytes: bytes, encoding: .utf8),
        "wire bytes were not valid UTF-8",
        sourceLocation: sourceLocation
    )
}

/// The relay's envelope and framing, which are what the parity gate diffs.
@Suite("The MCP endpoint's envelope")
struct MCPEndpointTests {
    /// `result, jsonrpc, id` on success and `jsonrpc, id, error` on failure — two DIFFERENT orders,
    /// measured separately rather than assumed symmetric. No `Codable` encoder produces either by
    /// accident, which is why the relay serialises through `JSStringify` instead.
    @Test("the success envelope is result, jsonrpc, id")
    func successEnvelopeOrder() {
        let value = MCPEndpoint.success(id: .number(1), result: .object([]))
        #expect(JSStringify.compact(value) == #"{"result":{},"jsonrpc":"2.0","id":1}"#)
    }

    @Test("the error envelope is jsonrpc, id, error")
    func failureEnvelopeOrder() {
        let value = MCPEndpoint.failure(id: .number(3), code: -32601, message: "Method not found")
        #expect(JSStringify.compact(value)
            == #"{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"Method not found"}}"#)
    }

    @Test("a framing refusal is plain JSON with jsonrpc, error, id and a null id")
    func refusalShape() throws {
        let response = MCPEndpoint.rpcError(403, code: -32000, message: "Invalid Host header: evil")
        #expect(response.status == 403)
        guard case let .bytes(body) = response.body else {
            Issue.record("a refusal must be a buffered body, not a stream")
            return
        }
        #expect(try utf8(body)
            == #"{"jsonrpc":"2.0","error":{"code":-32000,"message":"Invalid Host header: evil"},"id":null}"#)
        #expect(response.headers.first?.name == "content-type")
    }

    /// `content` then `isError` — the order the reference emits after its own SDK has re-serialised
    /// the result, which is not the order its source constructs the object in. Measured, not read.
    @Test("a tool error carries content before isError")
    func toolErrorShape() {
        let value = MCPEndpoint.toolError(#"Tool "bare" is not namespaced <server>__<tool>."#)
        let expected = #"{"content":[{"type":"text","#
            + #""text":"Tool \"bare\" is not namespaced <server>__<tool>."}],"#
            + #""isError":true}"#
        #expect(JSStringify.compact(value) == expected)
    }

    @Test("the SSE frame is event then data, terminated by a blank line")
    func sseFraming() async throws {
        let response = MCPEndpoint.sse([.object([JSONMember(key: JSString("a"), value: .number(1))])])
        guard case let .chunks(stream) = response.body else {
            Issue.record("an SSE response must stream")
            return
        }
        var joined = Data()
        for await piece in stream {
            joined.append(piece)
        }
        #expect(try utf8(joined) == "event: message\ndata: {\"a\":1}\n\n")
    }
}

/// The startup failure a user actually acts on.
@Suite("Bringing the listener up")
struct ListenerFailureTests {
    @Test("a port outside the bindable range is refused rather than truncated")
    func unbindablePort() {
        #expect(LoopbackHTTPServer.loopbackParameters(port: 70000) == nil)
        #expect(LoopbackHTTPServer.loopbackParameters(port: -1) == nil)
    }

    @Test("the bind is pinned to IPv4 loopback, never every interface")
    func loopbackPinned() throws {
        let parameters = try #require(LoopbackHTTPServer.loopbackParameters(port: 8999))
        // `requiredLocalEndpoint` is the documented way to pin the bind address. Without it
        // `NWListener` binds every interface, which would put an endpoint that runs every MCP server
        // the user owns — with the user's environment — on the LAN.
        //
        // Which host, not merely that a host was pinned. Measured 2026-08-19 by the campaign's
        // arming gate: with `host: .ipv4(.any)` in `loopbackParameters` — the LAN bind this clause
        // exists to stop — `requiredLocalEndpoint != nil` stayed true and this suite stayed green.
        // An assertion that cannot fail on the defect it names is a decoration, so the endpoint is
        // now read rather than counted.
        let endpoint = try #require(parameters.requiredLocalEndpoint)
        guard case let .hostPort(host, port) = endpoint else {
            Issue.record("the pin is not a host/port endpoint, so no address was asserted: \(endpoint)")
            return
        }
        #expect(host == .ipv4(.loopback), "bound \(host) rather than IPv4 loopback")
        #expect(port.rawValue == 8999)
        #expect(parameters.allowLocalEndpointReuse == false)
    }

    @Test("EADDRINUSE reads like the reference's message, not like an NWError")
    func addressInUseWording() {
        let failure = LoopbackHTTPServer.listenFailure(port: 8879, error: NWErrorStub.addressInUse)
        #expect(failure.description == "listen EADDRINUSE: address already in use 127.0.0.1:8879")
    }
}

/// A stand-in for the one `NWError` case whose wording is asserted. Constructing a real
/// `NWError.posix` is possible, so this is only a named alias for readability at the call site.
private enum NWErrorStub {
    static let addressInUse: any Error = NWError.posix(.EADDRINUSE)
}
