import Foundation

/// The parts of a URL the router actually asks for, resolved the way the WHATWG parser behind
/// JavaScript's `new URL()` resolves them.
///
/// Foundation's `URL` is a different specification and disagrees in ways that matter here: it
/// accepts strings `new URL()` rejects, and it reports a port that was written out even when that
/// port is the scheme's default. The second decides ``SelfReference``, where the reference compares
/// against the port *as reported* — so `http://localhost:80` is not a self-reference for port 80.
///
/// Every rule below is pinned by a vector generated from `new URL()` itself, and three of them were
/// found that way rather than reasoned: a non-special scheme still parses a host when `//` is
/// written, a port is normalised before it is compared against the scheme default, and only the
/// first two slashes are the authority marker.
struct JSURL {
    let scheme: String
    /// Includes the brackets for an IPv6 address, as `URL.hostname` does.
    let host: String
    /// Empty when absent **or** when it is the default for the scheme.
    let port: String

    private static let defaultPorts: [String: String] = [
        "http": "80", "https": "443", "ws": "80", "wss": "443", "ftp": "21"
    ]

    private static let specialSchemes: Set<String> = ["http", "https", "ws", "wss", "ftp", "file"]

    init?(_ text: String) {
        // Leading and trailing C0 controls and spaces are stripped before parsing.
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}...\u{20}"))
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }

        let rawScheme = String(trimmed[trimmed.startIndex ..< colon]).lowercased()
        guard Self.isValidScheme(rawScheme) else { return nil }
        scheme = rawScheme

        let rest = String(trimmed[trimmed.index(after: colon)...])
        let isSpecial = Self.specialSchemes.contains(rawScheme)

        guard let authority = Self.authority(in: rest, isSpecial: isSpecial) else {
            // A non-special scheme with no `//` is opaque: `mailto:a@b` has no host.
            host = ""
            port = ""
            return
        }

        let split = Self.split(authority: authority)
        guard let hostPart = split.host else { return nil }
        // `file:` is the one special scheme allowed an empty host; every other special one throws.
        guard !hostPart.isEmpty || !isSpecial || rawScheme == "file" else { return nil }
        guard split.port.isEmpty || split.port.allSatisfy(\.isNumber) else { return nil }

        host = hostPart.lowercased()
        // Normalise *first*, then compare: `http://host:00080` is port 80, the default for http, so
        // it is reported as empty — while `http://host:0` is reported as `0`.
        let normalised = Self.normalisedPort(split.port)
        port = normalised == Self.defaultPorts[rawScheme] ? "" : normalised
    }

    /// The authority slice, or nil when this URL has none at all.
    private static func authority(in rest: String, isSpecial: Bool) -> String? {
        var remainder = rest
        if isSpecial {
            // A special scheme tolerates a missing or singular slash — `http:/example.com` reaches
            // the same place as `http://example.com` — but only **two** are the authority marker.
            // Consuming a third would swallow the path: `file:///tmp/x` has an empty host and a
            // path of `/tmp/x`, not a host of `tmp`.
            var consumed = 0
            while consumed < 2, remainder.hasPrefix("/") {
                remainder.removeFirst()
                consumed += 1
            }
        } else if remainder.hasPrefix("//") {
            remainder.removeFirst(2)
        } else {
            return nil
        }
        let end = remainder.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? remainder.endIndex
        return String(remainder[remainder.startIndex ..< end])
    }

    /// Splits an authority into host and port. A nil host means the brackets were unbalanced.
    private static func split(authority: String) -> (host: String?, port: String) {
        var hostPart = authority
        // Userinfo is discarded; the last `@` separates it from the host.
        if let at = hostPart.lastIndex(of: "@") {
            hostPart = String(hostPart[hostPart.index(after: at)...])
        }

        if hostPart.hasPrefix("[") {
            guard let close = hostPart.firstIndex(of: "]") else { return (nil, "") }
            let after = hostPart.index(after: close)
            var portPart = ""
            if after < hostPart.endIndex, hostPart[after] == ":" {
                portPart = String(hostPart[hostPart.index(after: after)...])
            }
            return (String(hostPart[hostPart.startIndex ... close]), portPart)
        }

        if let colon = hostPart.lastIndex(of: ":") {
            let portPart = String(hostPart[hostPart.index(after: colon)...])
            return (String(hostPart[hostPart.startIndex ..< colon]), portPart)
        }
        return (hostPart, "")
    }

    private static func normalisedPort(_ text: String) -> String {
        guard !text.isEmpty, let value = Int(text) else { return "" }
        return String(value)
    }

    private static func isValidScheme(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first,
              ("a" ... "z").contains(first) || ("A" ... "Z").contains(first)
        else { return false }
        return scheme.unicodeScalars.allSatisfy { scalar in
            ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
                || ("0" ... "9").contains(scalar) || scalar == "+" || scalar == "-" || scalar == "."
        }
    }
}
