import Foundation

/// The two pages the authorization server draws.
///
/// **Not `AuthPages`.** That type serves the *callback* pages for the router's upstream OAuth
/// client, its bytes are pinned by a parity row, and its own documentation records that it
/// interpolates without escaping — a reflected-markup hole preserved deliberately for parity.
/// Nothing here inherits that: every interpolated value goes through ``escapeHtml``, because
/// upstream names, recorded error text and query values are all attacker-influenceable in
/// principle and this page is served on the loopback origin.
public enum AuthServerPage {
    /// The reference's `escapeHtml`, character for character and in the same order.
    public static func escapeHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static let style = "<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;"
        + "color:#eae8f5;margin:0;padding:40px 20px}main{max-width:640px;margin:0 auto}"
        + "h1{font-size:19px;margin:0 0 6px}h2{font-size:15px;font-weight:600;margin:28px 0 10px}"
        + "h3{font-size:13px;margin:0 0 2px;font-family:ui-monospace,SFMono-Regular,monospace}"
        + "p{margin:0 0 6px;color:#a6a2c4}ul{list-style:none;padding:0;margin:0}"
        + "li{border:1px solid #2b2842;border-radius:10px;padding:14px 16px;margin:0 0 10px}"
        + ".state{color:#eae8f5}.err{color:#ff9230;font-family:ui-monospace,monospace;font-size:12px}"
        + ".none{font-size:12px}"
        + "pre.cmd{background:#0f0d18;border-radius:6px;padding:8px 10px;margin:8px 0 0;overflow-x:auto;"
        + "font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#eae8f5}"
        + "button{font:inherit;background:#0091ff;color:#fff;border:0;border-radius:7px;"
        + "padding:8px 16px;margin-top:24px;cursor:pointer}</style>"

    /// The interstitial: what the token means, then every upstream that is serving nothing and
    /// what to do about each, then Continue.
    public static func consent(rows: [UpstreamReport], hidden: [(String, String)]) -> String {
        let silent = rows.filter { $0.kind != .serving }
        let serving = rows.count - silent.count

        let list = silent.map { row -> String in
            let command = row.command.map { "<pre class=\"cmd\">\(escapeHtml($0))</pre>" }
                ?? "<p class=\"none\">Nothing to run — see above.</p>"
            let detail = row.detail.map { "<p class=\"err\">It last reported: \(escapeHtml($0))</p>" }
                ?? ""
            return "<li><h3>\(escapeHtml(row.name))</h3>"
                + "<p class=\"state\">\(escapeHtml(row.headline))</p>"
                + "<p>\(escapeHtml(row.remedy))</p>\(detail)\(command)</li>"
        }.joined()

        let body = silent.isEmpty
            ? "<h2>All \(rows.count) upstreams are serving tools</h2>"
            : "<h2>\(silent.count) of \(rows.count) are serving no tools</h2><ul>\(list)</ul>"

        let fields = hidden.map { key, value in
            "<input type=\"hidden\" name=\"\(escapeHtml(key))\" value=\"\(escapeHtml(value))\">"
        }.joined()

        return "<!doctype html><meta charset=\"utf-8\"><title>mcp-router</title>"
            + style
            + "<main><h1>Connect to mcp-router</h1>"
            + "<p>This router runs on your own machine and authenticates nobody: the token it is "
            + "about to issue means &quot;a local user completed this flow&quot;, and it grants "
            + "nothing that loopback access does not already grant. "
            + "\(serving) of \(rows.count) upstreams are serving tools.</p>"
            + body
            + "<form method=\"POST\" action=\"\(AuthServerPaths.authorize)\">\(fields)"
            + "<button type=\"submit\">Continue</button></form></main>"
    }

    /// The refusal page. Reached only where redirecting the error would mean a hop to a
    /// destination this router has just decided not to trust.
    public static func fatal(reason: String) -> String {
        "<!doctype html><meta charset=\"utf-8\"><title>Authorization failed</title>"
            + "<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;"
            + "color:#eae8f5;display:grid;place-items:center;height:100vh;margin:0;text-align:center}"
            + "h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>"
            + "<div><h1>Authorization failed</h1><p>\(escapeHtml(reason))</p></div>"
    }
}
