import Foundation

/// The parts of a URL the router actually asks for, resolved the way the WHATWG parser behind
/// JavaScript's `new URL()` resolves them.
///
/// Foundation's `URL` is a different specification and disagrees in ways that matter here: it
/// accepts strings `new URL()` rejects, and it reports a port that was written out even when that
/// port is the scheme's default. The second one decides ``SelfReference``, where the reference
/// compares against the port *as reported* — so `http://localhost:80` is not a self-reference for
/// port 80, because WHATWG reports its port as empty.
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

        var rest = String(trimmed[trimmed.index(after: colon)...])
        let isSpecial = Self.specialSchemes.contains(rawScheme)

        if isSpecial {
            // A special scheme tolerates a missing or singular slash — `http:/example.com` reaches
            // the same place as `http://example.com` — but only **two** are the authority marker.
            // Consuming a third would swallow the path: `file:///tmp/x` has an empty host and a
            // path of `/tmp/x`, not a host of `tmp`.
            var consumed = 0
            while consumed < 2, rest.hasPrefix("/") {
                rest.removeFirst()
                consumed += 1
            }
        } else if rest.hasPrefix("//") {
            // A non-special scheme still parses an authority when one is written: `x://y` has
            // hostname `y`. Only a scheme with no `//` at all is opaque.
            rest.removeFirst(2)
        } else {
            host = ""
            port = ""
            return
        }

        // The authority ends at the first path, query or fragment delimiter.
        let authorityEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        var authority = String(rest[rest.startIndex ..< authorityEnd])

        // Userinfo is discarded; the last `@` separates it from the host.
        if let at = authority.lastIndex(of: "@") {
            authority = String(authority[authority.index(after: at)...])
        }

        var hostPart = authority
        var portPart = ""
        if hostPart.hasPrefix("[") {
            guard let close = hostPart.firstIndex(of: "]") else { return nil }
            let after = hostPart.index(after: close)
            if after < hostPart.endIndex, hostPart[after] == ":" {
                portPart = String(hostPart[hostPart.index(after: after)...])
            }
            hostPart = String(hostPart[hostPart.startIndex ... close])
        } else if let colonIndex = hostPart.lastIndex(of: ":") {
            portPart = String(hostPart[hostPart.index(after: colonIndex)...])
            hostPart = String(hostPart[hostPart.startIndex ..< colonIndex])
        }

        // `file:` is the one special scheme allowed an empty host; every other special one throws.
        guard !hostPart.isEmpty || !isSpecial || rawScheme == "file" else { return nil }
        guard portPart.isEmpty || portPart.allSatisfy(\.isNumber) else { return nil }

        host = hostPart.lowercased()
        // Normalise *first*, then compare: `http://host:00080` is port 80, which is the default for
        // http, so it is reported as empty — while `http://host:0` is reported as `0`.
        let normalised = Self.normalisedPort(portPart)
        port = normalised == Self.defaultPorts[rawScheme] ? "" : normalised
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
