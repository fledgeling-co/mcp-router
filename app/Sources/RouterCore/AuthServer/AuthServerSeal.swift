import CryptoKit
import Foundation
import Network

/// The router's own authorization server — the half that faces MCP **clients**.
///
/// Everything else under `Auth/` is the router acting as a *client* to its upstreams. This is the
/// opposite role, on the same machine and the same port, which is why every path here is exact and
/// distinct from `/callback`: a request meant for one role must never be read by the other.
///
/// The port of `src/oauth.ts`. Every wire string below is the reference's, and the parity lane
/// drives both routers with the same requests and diffs the answers, so a hand-copied constant
/// that goes stale fails a gate rather than rotting.
public enum AuthServerPaths {
    public static let wellKnownResource = "/.well-known/oauth-protected-resource"
    public static let wellKnownServer = "/.well-known/oauth-authorization-server"
    public static let register = "/register"
    public static let authorize = "/authorize"
    public static let token = "/token"

    /// True when this path belongs to the authorization server.
    ///
    /// The two metadata paths also match a `/`-suffixed form, because RFC 9728 has clients probe
    /// `/.well-known/oauth-protected-resource/mcp` — the resource path appended — and a client
    /// that only ever asks the suffixed question would 404 against an exact match alone.
    ///
    /// The negatives matter as much as the positives, exactly as they do in ``ControlPaths``:
    /// `/registerx` and `/tokens` share a prefix with an owned path and are not owned.
    public static func isAuthServerPath(_ pathname: String) -> Bool {
        pathname == wellKnownResource
            || pathname.hasPrefix("\(wellKnownResource)/")
            || pathname == wellKnownServer
            || pathname.hasPrefix("\(wellKnownServer)/")
            || pathname == register
            || pathname == authorize
            || pathname == token
    }
}

/// The one persisted secret, and the sealed values it signs.
///
/// There is no user database and no registration store. `client_id`, access tokens and refresh
/// tokens are all self-encoded blobs signed with this key, so a token minted before a restart
/// still validates after it and re-registering the same redirect URIs is idempotent.
///
/// The failure that design avoids is concrete: an in-memory authorization server forgets its
/// registrations, the next `refresh_token` grant answers `invalid_client`, and some clients mark
/// the server logged-out and stop sending its tools — which is R14's own bug arriving by another
/// route.
public struct AuthServerSeal: Sendable {
    /// `~/.claude/mcp-router/auth/issuer.key`, `0600` in a `0700` directory, beside the upstream
    /// credentials it sits next to and under the same modes ``FileAuthStore`` writes.
    public static func keyPath(authDir: String) -> String {
        (authDir as NSString).appendingPathComponent("issuer.key")
    }

    private let key: SymmetricKey

    /// Read the key, or mint one. Not `try?`-and-default: a key that cannot be written is a router
    /// whose tokens would not survive its own restart, and that is worth failing on.
    public init(authDir: String, fileSystem: any FileSystem & FileModeWriting = RealFileSystem()) throws {
        let path = Self.keyPath(authDir: authDir)
        if fileSystem.fileExists(atPath: path),
           let data = try? fileSystem.readFile(atPath: path)
        {
            let hex = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let bytes = Self.bytes(fromHex: hex), bytes.count == 32 {
                key = SymmetricKey(data: Data(bytes))
                return
            }
        }
        var fresh = [UInt8](repeating: 0, count: 32)
        for index in fresh.indices { fresh[index] = UInt8.random(in: 0 ... 255) }
        try fileSystem.createDirectory(atPath: authDir, mode: 0o700)
        let hex = fresh.map { String(format: "%02x", $0) }.joined()
        try fileSystem.writeFile(Data((hex + "\n").utf8), atPath: path, mode: 0o600)
        key = SymmetricKey(data: Data(fresh))
    }

    /// For a suite that wants a fixed key rather than a filesystem.
    public init(rawKey: Data) {
        key = SymmetricKey(data: rawKey)
    }

    private static func bytes(fromHex hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    /// base64url, unpadded — `Buffer.toString('base64url')`, which is what the reference seals with.
    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func data(fromBase64url text: String) -> Data? {
        var padded = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        return Data(base64Encoded: padded)
    }

    func sign(_ payload: String) -> String {
        Self.base64url(Data(HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)))
    }

    /// Constant-time, and length-checked first. A leaked signature is a forged `client_id`, and a
    /// timing oracle on an HMAC comparison is how one is obtained.
    func signatureOk(_ payload: String, _ supplied: String) -> Bool {
        let expected = Array(sign(payload).utf8)
        let given = Array(supplied.utf8)
        guard expected.count == given.count else { return false }
        var difference: UInt8 = 0
        for index in expected.indices { difference |= expected[index] ^ given[index] }
        return difference == 0
    }

    /// `<b64url(json)>.<signature>` — the one shape every self-encoded value here takes.
    ///
    /// The JSON is serialised through ``JSStringify`` from an explicitly ordered value, not from a
    /// `Codable` encoder, for the reason ``MCPEndpoint`` gives: member order is part of the bytes,
    /// and a blob whose members came out in another order is a different `client_id` for the same
    /// registration — so a client that registered before a rebuild would stop matching.
    public func seal(_ value: JSONValue) -> String {
        let payload = Self.base64url(Data(JSStringify.compact(value).utf8))
        return "\(payload).\(sign(payload))"
    }

    public func unseal(_ blob: String) -> JSONValue? {
        guard let dot = blob.lastIndex(of: ".") else { return nil }
        let payload = String(blob[blob.startIndex ..< dot])
        guard !payload.isEmpty else { return nil }
        guard signatureOk(payload, String(blob[blob.index(after: dot)...])) else { return nil }
        guard let data = Self.data(fromBase64url: payload),
              let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text)
        else { return nil }
        return parsed
    }
}

/// Which `redirect_uri` values this router will ever hand a code to, and which origins may POST.
public enum AuthServerAuthority {
    /// Loopback only, enforced at registration **and** again at authorize time.
    ///
    /// This is the constraint that matters most on the whole surface. Without it a page the user
    /// is visiting navigates them to `/authorize?redirect_uri=https://attacker.example/cb`, the
    /// approval fires, and the attacker holds a code. Checking only at registration is not enough:
    /// `client_id` is a self-encoded blob, so the authorize leg re-verifies what it carries rather
    /// than trusting it.
    ///
    /// `[::1]` is here alongside `127.0.0.1` and `localhost`, at any port, per RFC 8252 §7.3.
    public static func isLoopbackRedirect(_ uri: String) -> Bool {
        guard uri.count <= 2048, let url = URL(string: uri),
              url.scheme?.lowercased() == "http"
        else { return false }
        // `URL.host` strips the brackets from an IPv6 literal, so `[::1]` arrives as `::1`.
        guard let host = url.host else { return false }
        return isLoopbackHost(host)
    }

    /// Is this host the loopback, in any spelling the two URL parsers can hand us?
    ///
    /// Foundation's `URL` and Node's WHATWG parser normalise differently, and the difference was
    /// MEASURED across 21 hostile and benign shapes on 2026-08-21 rather than assumed. Two of them
    /// mattered and are handled here:
    ///
    ///   · **Case.** Node lowercases the host, so `http://LOCALHOST/cb` arrives as `localhost`;
    ///     Foundation preserves it. Without the lowercase below a client registering an uppercase
    ///     host works against the reference and is refused here.
    ///   · **IPv6 spelling.** Node canonicalises `[0:0:0:0:0:0:0:1]` to `[::1]`; Foundation hands
    ///     back the long form verbatim. Parsed as an address rather than compared as text, every
    ///     spelling of the loopback resolves to the same 16 bytes.
    ///
    /// What is NOT reconciled, and is a declared divergence rather than an oversight: Node's
    /// parser also accepts IPv4 shorthand — `http://127.1/cb` and `http://2130706433/cb` both
    /// normalise to `127.0.0.1` — and this does not. That direction is safe (the reference accepts
    /// a registration this router refuses; neither ever redirects off the machine) and matching it
    /// would mean reimplementing WHATWG host parsing, which is a larger surface with its own
    /// failure modes than the shapes it would buy. See the `div-r14-redirect-host` parity row.
    ///
    /// Every userinfo trick was measured to be refused by BOTH parsers — `http://[::1]@evil.example/cb`
    /// resolves to `evil.example` at each — because the host is read from the parsed URL rather
    /// than matched against the raw string.
    static func isLoopbackHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        if lowered == "127.0.0.1" || lowered == "localhost" { return true }
        let bare = lowered.hasPrefix("[") && lowered.hasSuffix("]")
            ? String(lowered.dropFirst().dropLast())
            : lowered
        guard bare.contains(":") else { return false }
        return IPv6Address(bare)?.rawValue == IPv6Address.loopback.rawValue
    }

    /// The origins this router is willing to be POSTed to by a browser.
    ///
    /// Browsers attach `Origin` to every cross-origin POST and MCP clients send none, so refusing
    /// a non-self `Origin` closes the CORS simple-request hole on `/token` without touching CORS
    /// at all. A form-encoded POST is a *simple* request: no preflight stands in the way, and
    /// while the page cannot read the reply, the side effect lands.
    public static func selfOrigins(host: String, port: Int) -> [String] {
        var seen: [String] = []
        for candidate in [
            "http://\(host):\(port)",
            "http://127.0.0.1:\(port)",
            "http://localhost:\(port)",
            "http://[::1]:\(port)"
        ] where !seen.contains(candidate) {
            seen.append(candidate)
        }
        return seen
    }

    /// An **absent** `Origin` is allowed, because that is what an MCP client sends. Anything else
    /// must be one of ours — including the literal `null`.
    ///
    /// `Origin: null` was allowed in the first cut, and the out-of-family review named it as the
    /// one control actually bypassable. It is attacker-reachable: a sandboxed `<iframe>` without
    /// `allow-same-origin`, a `data:` or `blob:` document, and some redirect chains all emit it.
    /// That matters most on `/register`, because a form with `enctype="text/plain"` and a crafted
    /// field name produces a body a JSON parser accepts — so the JSON content type is not itself a
    /// defence and this check is the only one standing there.
    ///
    /// It is not a complete exploit today: with no `Access-Control-Allow-Origin` the 201 is
    /// unreadable cross-origin, so the attacker never learns the `client_id` it would need. But
    /// that is the browser's behaviour rather than this router's control, and refusing `null`
    /// costs nothing — a real MCP client sends no header at all.
    public static func originRefused(_ request: HTTPWireRequest, host: String, port: Int) -> Bool {
        guard let origin = request.first("origin") else { return false }
        return !selfOrigins(host: host, port: port).contains(origin)
    }
}
