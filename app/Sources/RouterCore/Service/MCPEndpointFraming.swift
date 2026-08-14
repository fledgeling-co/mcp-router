import Foundation

/// The wire shapes the relay emits: the SSE header set and frame, the two JSON-RPC envelopes and the
/// tool-error body.
///
/// Split out of `MCPEndpoint.swift` because these are the parts with **no behaviour** — pure
/// functions from values to bytes, every one of them a measured copy of the reference's output
/// rather than a choice this router is free to make. They are also what the parity gate diffs and
/// what `HTTPWireTests`' own suite covers, so keeping them together makes the set that must not
/// drift readable in one screen.
extension MCPEndpoint {
    /// The reference's SSE header set, in the reference's order. `Transfer-Encoding: chunked` and
    /// `Date` are added by ``HTTPWire``; `connection` is here rather than left to the listener
    /// because the reference sends it in this position, lowercased.
    static let sseHeaders: [(name: String, value: String)] = [
        (name: "cache-control", value: "no-cache, no-transform"),
        (name: "connection", value: "keep-alive"),
        (name: "content-type", value: "text/event-stream"),
        (name: "x-accel-buffering", value: "no")
    ]

    static func sse(_ frames: [JSONValue]) -> HTTPWireResponse {
        let stream = AsyncStream<Data> { continuation in
            for frame in frames {
                continuation.yield(Data("event: message\ndata: \(JSStringify.compact(frame))\n\n".utf8))
            }
            continuation.finish()
        }
        return HTTPWireResponse(status: 200, headers: sseHeaders, body: .chunks(stream))
    }

    /// A JSON-RPC error delivered as a plain JSON body — which is what the reference does for the
    /// framing refusals, in contrast to the SSE it uses for anything the transport actually handled.
    /// The member order is the reference's: `jsonrpc`, `error`, `id`.
    static func rpcError(_ status: Int, code: Int, message: String) -> HTTPWireResponse {
        let body = JSONValue.object([
            JSONMember(key: JSString("jsonrpc"), value: .string(JSString("2.0"))),
            JSONMember(key: JSString("error"), value: .object([
                JSONMember(key: JSString("code"), value: .number(Double(code))),
                JSONMember(key: JSString("message"), value: .string(JSString(message)))
            ])),
            JSONMember(key: JSString("id"), value: .null)
        ])
        return .json(status, Data(JSStringify.compact(body).utf8))
    }

    /// `result` first, then `jsonrpc`, then `id` — the reference's envelope order, measured.
    static func success(id: JSONValue, result: JSONValue) -> JSONValue {
        .object([
            JSONMember(key: JSString("result"), value: result),
            JSONMember(key: JSString("jsonrpc"), value: .string(JSString("2.0"))),
            JSONMember(key: JSString("id"), value: id)
        ])
    }

    /// `jsonrpc`, `id`, then `error` — a different order from the success envelope, and measured
    /// separately rather than assumed symmetric.
    static func failure(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            JSONMember(key: JSString("jsonrpc"), value: .string(JSString("2.0"))),
            JSONMember(key: JSString("id"), value: id),
            JSONMember(key: JSString("error"), value: .object([
                JSONMember(key: JSString("code"), value: .number(Double(code))),
                JSONMember(key: JSString("message"), value: .string(JSString(message)))
            ]))
        ])
    }

    /// A `CallToolResult` reporting its own failure: one text content part and `isError: true`.
    static func toolError(_ text: String) -> JSONValue {
        .object([
            JSONMember(key: JSString("content"), value: .array([
                .object([
                    JSONMember(key: JSString("type"), value: .string(JSString("text"))),
                    JSONMember(key: JSString("text"), value: .string(JSString(text)))
                ])
            ])),
            JSONMember(key: JSString("isError"), value: .bool(true))
        ])
    }
}
