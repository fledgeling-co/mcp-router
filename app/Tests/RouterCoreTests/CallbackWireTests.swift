import Foundation
import Network
import Testing
@testable import RouterCore

// MARK: - The parts that need no socket

@Suite("R5 auth — the callback listener's wire format")
struct CallbackWireTests {
    @Test("the page responses carry content-type, a byte-counted length, and close")
    func pageResponseBytes() {
        let wire = LoopbackCallbackListener.wire(
            for: CallbackReply(status: 200, contentType: "text/html", body: "<p>hi</p>")
        )
        #expect(wire == "HTTP/1.1 200 OK\r\ncontent-type: text/html\r\ncontent-length: 9\r\n"
            + "connection: close\r\n\r\n<p>hi</p>")
    }

    @Test("B82 — the 404 carries no content-type and no body")
    func notFoundBytes() {
        let wire = LoopbackCallbackListener.wire(
            for: CallbackReply(status: 404, contentType: nil, body: "")
        )
        #expect(wire == "HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
        #expect(!wire.lowercased().contains("content-type"))
    }

    @Test("content-length counts UTF-8 bytes, not characters")
    func contentLengthIsBytes() {
        // The failure pages render a provider-supplied detail verbatim, and a provider writes in its
        // own language. Counting characters truncates the page in the browser by exactly the number
        // of multi-byte characters in it — which renders as a page that is subtly cut off.
        let wire = LoopbackCallbackListener.wire(
            for: CallbackReply(status: 400, contentType: "text/html", body: "é☃")
        )
        #expect(wire.contains("content-length: 5\r\n"))
    }

    @Test("the status lines are the reference's, and an unmapped status reads 'unknown'")
    func statusReasons() {
        #expect(LoopbackCallbackListener.reason(for: 200) == "OK")
        #expect(LoopbackCallbackListener.reason(for: 400) == "Bad Request")
        #expect(LoopbackCallbackListener.reason(for: 404) == "Not Found")
        #expect(LoopbackCallbackListener.reason(for: 500) == "Internal Server Error")
        #expect(LoopbackCallbackListener.reason(for: 418) == "unknown")
    }

    @Test("the bind is pinned to IPv4 loopback, never every interface")
    func bindIsLoopbackOnly() throws {
        let parameters = try #require(LoopbackCallbackListener.loopbackParameters(port: 8880))
        let endpoint = try #require(parameters.requiredLocalEndpoint)
        guard case let .hostPort(host, port) = endpoint else {
            Issue.record("the local endpoint is not a host/port")
            return
        }
        // Binding every interface would put the callback — and the unescaped page it renders from a
        // provider-supplied `error`, spec §6 — on the LAN.
        #expect(host == .ipv4(.loopback))
        #expect(port.rawValue == 8880)
        #expect(parameters.allowLocalEndpointReuse == false)
    }

    @Test("a port outside the bindable range is refused rather than truncated")
    func unbindablePorts() {
        #expect(LoopbackCallbackListener.loopbackParameters(port: 65536) == nil)
        #expect(LoopbackCallbackListener.loopbackParameters(port: -1) == nil)
        #expect(LoopbackCallbackListener.loopbackParameters(port: 65535) != nil)
    }

    @Test("the request target is read only once the head is terminated")
    func requestTargetNeedsAWholeHead() {
        let partial = Data("GET /callback?code=a HTTP/1.1\r\nHost: 127.0.0.1\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: partial) == nil)

        let whole = Data("GET /callback?code=a HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == "/callback?code=a")
    }

    @Test("bare-LF line endings are read, as Node's parser reads them")
    func bareLineFeedHead() {
        let whole = Data("GET /callback?code=b HTTP/1.1\nHost: 127.0.0.1\n\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == "/callback?code=b")
    }

    @Test("a request line with no target is not answered")
    func malformedRequestLine() {
        let whole = Data("GET\r\n\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == nil)
    }

    @Test("any method reaches the handler, as the reference's handler accepts any")
    func methodIsNotFiltered() {
        let whole = Data("POST /callback?code=c HTTP/1.1\r\n\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == "/callback?code=c")
    }
}
