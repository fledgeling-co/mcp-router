import Foundation
import Testing
@testable import RouterCore

/// Reading a JSON-RPC error off the wire rather than off the SDK.
///
/// DEF-047: the pinned swift-sdk 0.12.1 passes the server's `message` through `unwrapDetail` for
/// -32700, -32600, -32601 and -32602, and passes `nil` for -32603. A server answering -32603 with a
/// message and no `data.detail` therefore loses that message entirely, and -32603 is the code
/// servers use for an arbitrary application error — so it is the one that loses the most. Measured
/// against a fixture returning `Authentication required`, the TypeScript reference recorded the
/// sentence and this router recorded `[-32603] Internal error`.
///
/// Every case below is written so that removing the read makes it fail: each asserts on the
/// upstream's own words, which is precisely what is absent without it.
@Suite("The error an upstream actually sent")
struct UpstreamRPCErrorTests {
    /// The frame DEF-047 was measured against: a message, and no `data.detail` to fall back to.
    private static let refusal = Data("""
    {"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"Internal error: Authentication required"}}
    """.utf8)

    @Test("the message the SDK discards is read off the response")
    func theMessageSurvives() throws {
        let reported = try #require(UpstreamRPCError.read(from: Self.refusal))
        #expect(reported.code == -32603)
        #expect(reported.message == "Internal error: Authentication required")
    }

    /// The half that makes this a fix rather than a reading: what the router goes on to report.
    /// `[-32603] Internal error` is what it said before, and the sentence is the part that tells a
    /// user their credential was refused rather than that something unspecified went wrong.
    @Test("the router reports the upstream's own sentence, not the canonical name alone")
    func theDescriptionCarriesTheReason() throws {
        let reported = try #require(UpstreamRPCError.read(from: Self.refusal))
        #expect(reported.description == "[-32603] Internal error: Authentication required")
        #expect(reported.description.contains("Authentication required"))
    }

    /// The server's `message` already begins with the canonical name for its code, so composing one
    /// would render it twice. Asserted rather than assumed, because "Internal error: Internal
    /// error: …" is the shape a well-meant prefix produces and it reads as a bug in the router.
    @Test("the canonical name is not composed on top of a message that already carries it")
    func theNameIsNotDoubled() throws {
        let reported = try #require(UpstreamRPCError.read(from: Self.refusal))
        #expect(!reported.description.contains("Internal error: Internal error"))
    }

    @Test("a response carrying no error member reads as nothing, so the SDK's error stands")
    func aResultIsNotAnError() {
        let ok = Data(#"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#.utf8)
        #expect(UpstreamRPCError.read(from: ok) == nil)
    }

    /// Both members are required. A frame carrying one without the other is not a JSON-RPC error
    /// object, and reporting a partial read as a whole one puts a guess where a reading belongs.
    @Test("an error object missing code or message reads as nothing rather than as a guess")
    func aPartialErrorIsNotRead() {
        let noMessage = Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603}}"#.utf8)
        let noCode = Data(#"{"jsonrpc":"2.0","id":1,"error":{"message":"Authentication required"}}"#.utf8)
        #expect(UpstreamRPCError.read(from: noMessage) == nil)
        #expect(UpstreamRPCError.read(from: noCode) == nil)
    }

    /// The wire's `message` is the field being restored, so it is the field read — including when a
    /// `data.detail` is also present and disagrees. This is what stops the fix quietly becoming a
    /// second implementation of the SDK's own `unwrapDetail`, which is the thing that lost it.
    @Test("the message is read even when a data.detail is present beside it")
    func theMessageWinsOverDetail() throws {
        let both = Data("""
        {"jsonrpc":"2.0","id":1,"error":{"code":-32603,\
        "message":"Internal error: Authentication required",\
        "data":{"detail":"something else entirely"}}}
        """.utf8)
        let reported = try #require(UpstreamRPCError.read(from: both))
        #expect(reported.message == "Internal error: Authentication required")
    }

    /// Codes other than -32603 are read the same way. The SDK happens to preserve their messages,
    /// so this is not a fix for them — it asserts the reader is not special-cased to one code,
    /// because a reader that only works on the code in the defect report is a workaround rather
    /// than a reading.
    @Test("the reader is not special-cased to the code the defect was found on")
    func otherCodesReadTheSameWay() throws {
        let notFound = Data("""
        {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found: tools/call"}}
        """.utf8)
        let reported = try #require(UpstreamRPCError.read(from: notFound))
        #expect(reported.code == -32601)
        #expect(reported.message == "Method not found: tools/call")
    }
}
