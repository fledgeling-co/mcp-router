import Foundation
import Synchronization
import Testing
@testable import RouterCore

/// R15 — the Host check guards every route, including one added later.
///
/// The exposure this arms was measured on 2026-08-21 against both live routers: `/health`,
/// `/status`, `/servers` and `/usage` answered **200** to `Host: evil.example` while `/mcp`
/// answered 403, because the check lived inside the MCP transport and the dispatch ladder reaches
/// that transport only after everything else has already answered.
///
/// The arming that matters is ``aRouteThisSuiteInventedIsRefusedWithNoAuthorityCodeOfItsOwn``. A
/// per-route assertion can only prove the routes that exist today; a throwaway route proves the
/// property the fix actually claims — that a route added tomorrow inherits the refusal without its
/// author knowing this file exists.
@Suite("Request authority")
struct RequestAuthorityTests {
    private static let port = 8879
    private static let allowed = RequestAuthority.allowedHosts(host: "127.0.0.1", port: port)

    private static func request(
        _ target: String, host: String?, method: String = "GET"
    ) -> HTTPWireRequest {
        HTTPWireRequest(
            method: method,
            target: target,
            headers: host.map { [(name: "Host", value: $0)] } ?? []
        )
    }

    private static func bodyText(_ response: HTTPWireResponse) -> String {
        guard case let .bytes(bytes) = response.body else { return "<stream>" }
        return String(bytes: bytes, encoding: .utf8) ?? "<not utf-8>"
    }

    /// A counter a `@Sendable` closure may increment. `Mutex` rather than a `var` captured by the
    /// closure, because the dispatch seam is `@Sendable` and has to stay so.
    private final class Ran: Sendable {
        private let count = Mutex(0)
        func record() {
            count.withLock { $0 += 1 }
        }

        var times: Int { count.withLock { $0 } }
    }

    // MARK: - The property, armed by a route that exists only here

    @Test("a route this suite invented is refused a foreign Host, with no authority code of its own")
    func aRouteThisSuiteInventedIsRefusedWithNoAuthorityCodeOfItsOwn() async {
        let ran = Ran()
        // The whole of the throwaway route. It reads no header, knows no allowed list, and would
        // happily answer anyone — which is the point: everything protecting it is the seam.
        let throwaway: @Sendable (HTTPWireRequest) async -> HTTPWireResponse = { _ in
            ran.record()
            return .json(200, Data(#"{"throwaway":true}"#.utf8))
        }

        let refused = await RequestAuthority.guarding(
            Self.request("/a-route-added-after-r15", host: "evil.example"),
            allowedHosts: Self.allowed,
            dispatch: throwaway
        )
        #expect(refused.status == 403)
        #expect(
            ran.times == 0,
            "the route ran, so the guard is inside the ladder rather than ahead of it"
        )

        let served = await RequestAuthority.guarding(
            Self.request("/a-route-added-after-r15", host: "127.0.0.1:\(Self.port)"),
            allowedHosts: Self.allowed,
            dispatch: throwaway
        )
        #expect(served.status == 200)
        #expect(Self.bodyText(served) == #"{"throwaway":true}"#)
        #expect(ran.times == 1)
    }

    // MARK: - The allowed set

    @Test("[::1] is in the allowed set, at the bound port")
    func ipv6LoopbackIsAllowed() async {
        #expect(Self.allowed.contains("[::1]:\(Self.port)"))
        let ran = Ran()
        let response = await RequestAuthority.guarding(
            Self.request("/status", host: "[::1]:\(Self.port)"),
            allowedHosts: Self.allowed,
            dispatch: { _ in ran.record(); return .json(200, Data("{}".utf8)) }
        )
        #expect(response.status == 200)
        #expect(ran.times == 1)
    }

    @Test("the three loopback spellings and the bound host are allowed, de-duplicated")
    func theLoopbackSpellings() {
        #expect(Self.allowed == ["127.0.0.1:8879", "localhost:8879", "[::1]:8879"])
        #expect(
            RequestAuthority.allowedHosts(host: "0.0.0.0", port: 9) ==
                ["0.0.0.0:9", "127.0.0.1:9", "localhost:9", "[::1]:9"]
        )
    }

    @Test("the right port is required, not merely the right name")
    func theBoundPortIsPartOfTheAuthority() {
        #expect(
            RequestAuthority.refusal(
                for: Self.request("/health", host: "127.0.0.1:1"),
                path: "/health",
                allowedHosts: Self.allowed
            ) != nil
        )
    }

    // MARK: - The two refusal bodies

    /// Measured against the reference on 2026-08-21, `POST /mcp` with `Host: evil.example`:
    /// `HTTP/1.1 403 Forbidden`, `content-type: application/json`, `content-length: 97`, and the
    /// envelope below. `content-length` is the byte count of exactly this string, so a member
    /// re-ordering or a re-worded message fails here rather than in the parity gate.
    @Test("/mcp's refusal is the reference transport's own bytes")
    func mcpRefusalIsByteIdentical() {
        let response = RequestAuthority.refusal(
            for: Self.request("/mcp", host: "evil.example", method: "POST"),
            path: "/mcp",
            allowedHosts: Self.allowed
        )
        // Split only so the line fits the lint; the bytes are unchanged and the length assertion
        // below is what proves that.
        let expected = #"{"jsonrpc":"2.0","error":{"code":-32000,"#
            + #""message":"Invalid Host header: evil.example"},"id":null}"#
        #expect(response?.status == 403)
        #expect(response?.reason == "Forbidden")
        #expect(response.map(Self.bodyText) == expected)
        #expect(expected.utf8.count == 97)
        let headers = response?.headers.map { "\($0.name): \($0.value)" } ?? []
        #expect(headers == ["content-type: application/json", "content-length: 97"])
    }

    @Test("every other route gets the ordinary error envelope, naming the host it sent")
    func ordinaryRefusal() {
        for path in ["/health", "/status", "/servers", "/usage", "/registry/search", "/nope"] {
            let response = RequestAuthority.refusal(
                for: Self.request(path, host: "evil.example"),
                path: path,
                allowedHosts: Self.allowed
            )
            #expect(response?.status == 403, "\(path) was not refused")
            #expect(
                response.map(Self.bodyText) == #"{"error":"Invalid Host header: evil.example"}"#,
                "\(path) refused with the wrong body"
            )
        }
    }

    /// Node answers 400 to an HTTP/1.1 request carrying no Host header, so the reference can never
    /// produce a refusal for one. Refusing here would be a divergence rather than a fix, and a page
    /// cannot send a Host-less request in any case.
    @Test("a request with no Host header is left to the layer that already refuses it")
    func noHostHeaderIsNotThisCheck() {
        #expect(
            RequestAuthority.refusal(
                for: Self.request("/health", host: nil), path: "/health", allowedHosts: Self.allowed
            ) == nil
        )
    }
}
