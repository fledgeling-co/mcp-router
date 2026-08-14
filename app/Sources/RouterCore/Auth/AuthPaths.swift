import Foundation

/// Where the OAuth callback lands, and where a server's credential record lives.
///
/// The port is **fixed**, not ephemeral, for the reason the reference gives: dynamic client
/// registration sends `redirect_uris` to the authorization server at registration time. Register on
/// a random port today and the next authorization, on a different random port, is rejected as an
/// unregistered redirect — so the port has to survive restarts for a saved registration to keep
/// working.
public enum AuthPaths {
    /// `Number(process.env.MCP_ROUTER_AUTH_PORT ?? 8880)`, as a JavaScript number.
    ///
    /// Resolved **once**, at first use, and cached — the reference reads it at module load and
    /// derives `AUTH_REDIRECT_URI` there too, so a later mutation of the environment changes
    /// neither (B90). A per-call read would diverge, and the difference is byte-visible: the port
    /// appears percent-encoded inside `authorizationUrl`.
    public static let portValue: Double = {
        guard let raw = ProcessInfo.processInfo.environment["MCP_ROUTER_AUTH_PORT"] else {
            return 8880
        }
        return jsNumber(raw)
    }()

    /// The port as a listener can use it, or nil when the environment supplied something that is
    /// not a bindable port. Kept separate from `portValue` because `Int(Double.nan)` traps in Swift
    /// where JavaScript would carry the NaN forward into the URI string.
    public static var bindablePort: Int? {
        guard portValue.isFinite, portValue >= 0, portValue <= 65535 else { return nil }
        return Int(portValue)
    }

    /// `http://127.0.0.1:${AUTH_CALLBACK_PORT}/callback`, derived once from the port.
    ///
    /// Rendered through `JSNumber.string`, which is R1's port of JavaScript number-to-string — so a
    /// garbage environment value produces the reference's `…:NaN/callback`, not a silent fallback
    /// to 8880. Diverging here would be invisible until a registration failed in the field.
    public static let redirectURI: String = "http://127.0.0.1:\(JSNumber.string(portValue))/callback"

    /// `join(AUTH_DIR, `${server}.json`)`.
    ///
    /// The name is carried as `JSString` and encoded to UTF-8 without normalization, which is what
    /// Node does with a JavaScript string. See B80 for why the *key* type matters, and why the
    /// filesystem is deliberately not where that is asserted.
    public static func recordPath(authDir: String, server: JSString) -> String {
        (authDir as NSString).appendingPathComponent("\(server.string).json")
    }

    /// `Number(string)` for the one case this module needs.
    ///
    /// Deliberately private and deliberately narrow. R3 owns the general `JSToNumber`, which is not
    /// on this branch; duplicating it as a shared symbol would collide at merge, so this stays a
    /// file-private helper covering exactly the inputs an environment variable can hold.
    private static func jsNumber(_ raw: String) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // `Number("")` and `Number("   ")` are 0, not NaN.
        if trimmed.isEmpty { return 0 }
        return Double(trimmed) ?? .nan
    }
}
