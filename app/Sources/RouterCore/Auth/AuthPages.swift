import Foundation

/// The two pages the loopback callback serves.
///
/// **These bytes are a contract, not a design surface.** They use `#141220`/`#eae8f5`/`#a6a2c4`,
/// which are not DESIGN.md's tokens — and R4's differential parity gate diffs them against the
/// TypeScript router. Restyling here would fail the one gate that proves this port faithful, so the
/// restyle is a deferred item that must change both routers in one commit (spec §7, §8).
///
/// **Security, deliberately preserved:** the reference interpolates `title` and `detail` into HTML
/// **without escaping**, and on the provider-refused path `detail` is the raw `error` query
/// parameter. That is a reflected-markup injection on the loopback origin. It is reproduced rather
/// than fixed for the same parity reason and is escalated in spec §6 as a cross-cutting item
/// spanning both routers. Fixing it here alone would be a divergence, not a fix.
public enum AuthPages {
    /// The reference's `PAGE(title, detail)`, byte for byte, including the concatenation seams.
    ///
    /// `title` lands in **both** `<title>` and `<h1>` (B99).
    public static func page(title: String, detail: String) -> String {
        "<!doctype html><meta charset=\"utf-8\"><title>\(title)</title>"
            + "<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;color:#eae8f5;"
            + "display:grid;place-items:center;height:100vh;margin:0;text-align:center}"
            + "h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>"
            + "<div><h1>\(title)</h1><p>\(detail)</p></div>"
    }

    /// `PAGE(`${serverName} is connected`, 'You can close this tab and return to mcp-router.')`
    public static func connected(server: JSString) -> String {
        page(
            title: "\(server.string) is connected",
            detail: "You can close this tab and return to mcp-router."
        )
    }

    /// Every failure page. The heading is always the literal `Authorization failed` (B99); only the
    /// detail varies, and each variant's exact string is pinned by the clause named beside it.
    public static func failed(detail: String) -> String {
        page(title: "Authorization failed", detail: detail)
    }

    /// The detail the reference renders when the provider returned neither a code nor an error.
    ///
    /// Distinct from the *rejection* string, which is `noCodeRejection` — the reference uses two
    /// different sentences for the same event, and B86 exists because a port that reuses one for
    /// both produces the wrong log line.
    public static let noCodePageDetail = "the provider returned no code"
    /// `new Error(error ?? 'no authorization code returned')`
    public static let noCodeRejection = "no authorization code returned"
    /// The overall-timeout rejection (B99).
    public static let timedOutRejection = "authorization timed out"
    /// The 20 s authorization-URL race (B84).
    public static let noURLRejection = "the server never produced an authorization URL"
}
